import CoreML
import Foundation
import NaturalLanguage
import os

/// Ranks dictionary senses against the sentence a word was selected in, using
/// the bundled gte-base Core ML encoder (768-dim, mean-pooled, L2-normalized
/// — cosine similarity is a plain dot product).
///
/// Scoring model, per sense (subsenses included as their own candidates;
/// scheme selected empirically against real Wiktionary entries — see
/// tools/embedding-model/):
///   gloss doc    = "word (pos): definition"
///   example docs = up to 3 example sentences / usage quotes
///   anchor discount: every doc similarity is reduced by λ·cosine(bareWord,
///                 doc), so senses can't win on merely echoing the headword —
///                 only context-driven similarity counts
///   defScore     = disc(gloss); example contribution = (defScore + disc(ex))/2
///   similarity   = max(defScore, example contributions)
///   PoS prior    = small multiplicative penalty when the tagged part of
///                 speech disagrees (soft — never excludes a sense outright)
/// Similarities are softmax-calibrated across candidates so the returned
/// score behaves like a probability, and confidence comes from the margin
/// between the top two candidates.
///
/// Gloss/example embeddings are cached per headword, so re-ranking the same
/// word (or re-opening the sheet) only embeds the context sentence.
actor EmbeddingSenseRanker: SenseRanker {
    static let shared = EmbeddingSenseRanker()

    private static let embeddingDimension = 768
    private static let softmaxTemperature = 0.05
    /// Ratio of top-1 probability over top-2 required for "high confidence".
    private static let confidenceRatio = 1.35
    /// Multiplier applied to the similarity of PoS-mismatched senses.
    private static let posMismatchPenalty = 0.94
    /// λ for the headword-anchor discount.
    private static let anchorDiscount = 0.25
    private static let maxExamplesPerSense = 3
    private static let cacheLimit = 40

    private let logger = Logger(subsystem: "com.fathom", category: "EmbeddingSenseRanker")

    private var model: MLModel?
    private var tokenizer: WordPieceTokenizer?
    private var didFailToLoad = false
    private var unloadTask: Task<Void, Never>?

    /// Per-headword cache of sense-document + anchor embeddings (LRU by insertion).
    private struct WordVectors {
        let anchor: [Float]
        let candidates: [SenseCandidate]
    }
    private var senseCache: [String: WordVectors] = [:]
    private var senseCacheOrder: [String] = []

    private init() {}

    // MARK: - SenseRanker

    func prewarm() async {
        guard loadIfNeeded() else { return }
        // One throwaway inference so the first real lookup doesn't pay
        // ANE compilation / weight-paging costs.
        _ = embed("prewarm")
        recordUsage()
    }

    func rank(_ request: SenseRankingRequest) async -> RankedDefinition? {
        let start = ContinuousClock.now
        guard loadIfNeeded() else { return nil }
        recordUsage()

        guard let wordVectors = senseVectors(for: request) else { return nil }
        var candidates = wordVectors.candidates
        guard !candidates.isEmpty else {
            logger.warning("[\(request.word)] no senses to rank")
            return nil
        }
        guard let contextVec = embed(request.sentence) else {
            logger.warning("[\(request.word)] failed to embed context sentence")
            return nil
        }

        // Soft PoS prior from the surface word in its sentence.
        let detectedPoS = Self.detectPartOfSpeech(
            of: request.surfaceWord, in: request.sentence, at: request.wordRange)

        // Similarity to the bare headword, subtracted from every doc score so
        // a sense can't win by merely echoing the word ("cramp: that which
        // cramps") — only similarity driven by the context counts.
        let anchor = wordVectors.anchor
        func discounted(_ doc: [Float]) -> Double {
            Self.dot(contextVec, doc) - Self.anchorDiscount * Self.dot(anchor, doc)
        }

        for i in candidates.indices {
            let defScore = discounted(candidates[i].glossVector)
            var similarity = defScore
            for exampleVec in candidates[i].exampleVectors {
                // Examples support the definition rather than replace it.
                similarity = max(similarity, (defScore + discounted(exampleVec)) / 2)
            }
            if let detectedPoS,
                !Self.posMatches(detected: detectedPoS, candidate: candidates[i].partOfSpeech)
            {
                similarity *= Self.posMismatchPenalty
            }
            candidates[i].similarity = similarity
        }

        // Softmax calibration across candidates.
        let maxSim = candidates.map(\.similarity).max() ?? 0
        var total = 0.0
        for i in candidates.indices {
            let e = exp((candidates[i].similarity - maxSim) / Self.softmaxTemperature)
            candidates[i].probability = e
            total += e
        }
        for i in candidates.indices { candidates[i].probability /= total }

        candidates.sort { $0.probability > $1.probability }
        guard let best = candidates.first else { return nil }
        let runnerUp = candidates.count > 1 ? candidates[1].probability : 0
        let ratio = runnerUp > 0 ? best.probability / runnerUp : 999.0
        let isHighConfidence = ratio >= Self.confidenceRatio

        let elapsed = start.duration(to: .now)
        logger.info(
            "[\(request.word)] ranked \(candidates.count) senses in \(elapsed.description): p=\(String(format: "%.3f", best.probability)) ratio=\(String(format: "%.3f", ratio)) pos=\(detectedPoS ?? "?") → \"\(best.sense.definition.prefix(80))\""
        )

        return RankedDefinition(
            sense: best.sense,
            partOfSpeech: best.partOfSpeech,
            score: best.probability,
            isHighConfidence: isHighConfidence
        )
    }

    private func recordUsage() {
        unloadTask?.cancel()
        unloadTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(300))
            guard !Task.isCancelled else { return }
            await self?.unload()
        }
    }

    func unload() {
        guard model != nil || tokenizer != nil else { return }
        logger.info("Unloading sense-embedding model due to inactivity")
        model = nil
        tokenizer = nil
    }

    // MARK: - Sense candidates

    private struct SenseCandidate {
        let sense: DictionarySense
        let partOfSpeech: String
        let glossVector: [Float]
        /// Embeddings of usable example sentences and usage quotes.
        let exampleVectors: [[Float]]
        var similarity: Double = 0
        var probability: Double = 0
    }

    private func senseVectors(for request: SenseRankingRequest) -> WordVectors? {
        let cacheKey = "\(request.word.lowercased())|\(request.entry.entries.count)"
        if let cached = senseCache[cacheKey] { return cached }

        guard let anchor = embed(request.word) else { return nil }
        var candidates: [SenseCandidate] = []
        for entry in request.entry.entries {
            for sense in entry.senses {
                appendCandidates(
                    for: sense, word: request.word, partOfSpeech: entry.partOfSpeech,
                    into: &candidates
                )
            }
        }
        let wordVectors = WordVectors(anchor: anchor, candidates: candidates)
        guard !candidates.isEmpty else { return wordVectors }

        senseCache[cacheKey] = wordVectors
        senseCacheOrder.append(cacheKey)
        if senseCacheOrder.count > Self.cacheLimit {
            senseCache.removeValue(forKey: senseCacheOrder.removeFirst())
        }
        return wordVectors
    }

    /// Flattens a sense and its subsenses into scored candidates.
    private func appendCandidates(
        for sense: DictionarySense, word: String, partOfSpeech: String,
        into candidates: inout [SenseCandidate]
    ) {
        let definition = sense.definition.trimmingCharacters(in: .whitespacesAndNewlines)
        if !definition.isEmpty,
            let glossVector = embed("\(word) (\(partOfSpeech)): \(definition)")
        {
            let usageTexts = (sense.examples ?? []) + (sense.quotes ?? []).map(\.text)
            let exampleVectors = usageTexts
                .compactMap(Self.cleanUsageText)
                .prefix(Self.maxExamplesPerSense)
                .compactMap { embed($0) }
            candidates.append(
                SenseCandidate(
                    sense: sense, partOfSpeech: partOfSpeech,
                    glossVector: glossVector, exampleVectors: Array(exampleVectors)
                ))
        }
        for subsense in sense.subsenses ?? [] {
            appendCandidates(
                for: subsense, word: word, partOfSpeech: partOfSpeech, into: &candidates)
        }
    }

    /// Filters out citation lines and fragments that would add noise
    /// (Wiktionary quotes often carry years, attributions, page numbers).
    private static func cleanUsageText(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 10, trimmed.count < 160 else { return nil }
        guard trimmed.range(of: #"\d{4}|letter to|page \d"#, options: .regularExpression) == nil
        else { return nil }
        return trimmed
    }

    // MARK: - Model loading & inference

    private func loadIfNeeded() -> Bool {
        if model != nil, tokenizer != nil { return true }
        if didFailToLoad { return false }

        guard
            let modelURL = Bundle.main.url(forResource: "SenseEmbedding", withExtension: "mlmodelc"),
            let vocabURL = Bundle.main.url(forResource: "bge_vocab", withExtension: "txt")
        else {
            logger.error("SenseEmbedding.mlmodelc or bge_vocab.txt missing from bundle")
            didFailToLoad = true
            return false
        }
        do {
            let clock = ContinuousClock()
            let elapsed = try clock.measure {
                let config = MLModelConfiguration()
                // ANE + CPU only: the GPU path returns all-zero embeddings on
                // the iOS simulator, and on device the ANE is the fast path
                // for this fixed-shape transformer anyway.
                config.computeUnits = .cpuAndNeuralEngine
                model = try MLModel(contentsOf: modelURL, configuration: config)
                tokenizer = try WordPieceTokenizer(vocabFileURL: vocabURL)
            }
            logger.info("Loaded sense-embedding model + tokenizer in \(elapsed.description)")
            return true
        } catch {
            logger.error("Failed to load sense-embedding model: \(error.localizedDescription)")
            didFailToLoad = true
            return false
        }
    }

    /// Embed one text into a unit-length 384-dim vector.
    private func embed(_ text: String) -> [Float]? {
        guard let model, let tokenizer else { return nil }
        let encoded = tokenizer.encode(text)
        do {
            let length = WordPieceTokenizer.sequenceLength
            let ids = try MLMultiArray(shape: [1, NSNumber(value: length)], dataType: .int32)
            let mask = try MLMultiArray(shape: [1, NSNumber(value: length)], dataType: .int32)
            for i in 0..<length {
                ids[i] = NSNumber(value: encoded.inputIDs[i])
                mask[i] = NSNumber(value: encoded.attentionMask[i])
            }
            let input = try MLDictionaryFeatureProvider(dictionary: [
                "input_ids": MLFeatureValue(multiArray: ids),
                "attention_mask": MLFeatureValue(multiArray: mask),
            ])
            let output = try model.prediction(from: input)
            guard let result = output.featureValue(for: "embedding")?.multiArrayValue else {
                return nil
            }
            var vector = [Float](repeating: 0, count: Self.embeddingDimension)
            for i in 0..<min(Self.embeddingDimension, result.count) {
                vector[i] = result[i].floatValue
            }
            return vector
        } catch {
            logger.error("Embedding inference failed: \(error.localizedDescription)")
            return nil
        }
    }

    private static func dot(_ a: [Float], _ b: [Float]) -> Double {
        // Vectors are L2-normalized by the model, so this is cosine similarity.
        var sum: Float = 0
        for i in 0..<min(a.count, b.count) { sum += a[i] * b[i] }
        return Double(sum)
    }

    // MARK: - Part of speech

    private static func detectPartOfSpeech(
        of word: String, in sentence: String, at knownRange: Range<String.Index>?
    ) -> String? {
        guard
            let wordRange = knownRange
                ?? sentence.range(of: word, options: [.caseInsensitive])
        else { return nil }
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = sentence
        var detected: String?
        tagger.enumerateTags(in: wordRange, unit: .word, scheme: .lexicalClass, options: []) {
            tag, _ in
            if let tag { detected = tag.rawValue.lowercased() }
            return false
        }
        return detected
    }

    private static func posMatches(detected: String, candidate: String) -> Bool {
        let c = candidate.lowercased()
        return c.contains(detected) || detected.contains(c)
    }
}
