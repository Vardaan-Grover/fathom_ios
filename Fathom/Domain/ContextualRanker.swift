import Foundation
import NaturalLanguage
import os

struct RankedDefinition {
    let sense: DictionarySense
    let partOfSpeech: String
    let score: Double
    let isHighConfidence: Bool
}

@available(iOS 17, *)
actor ContextualRanker {
    static let shared = ContextualRanker()

    // Score gap between first and second place required for HIGH confidence.
    private static let confidenceDeltaThreshold = 0.04

    private var embedding: NLContextualEmbedding?
    private var modelWasCached = false
    private let logger = Logger(subsystem: "com.fathom", category: "ContextualRanker")

    private init() {}

    // MARK: - Public API

    func rank(
        word: String,
        surfaceWord: String,
        in sentence: String,
        entry: DictionaryWordEntry
    ) -> RankedDefinition? {
        let start = Date()

        guard let emb = loadedEmbedding() else {
            logger.error("[\(word)] Model unavailable — skipping rank")
            return nil
        }

        // Extract the word's contextual vector using the surface form (the exact
        // string in the sentence, which may differ from the dictionary lemma).
        guard let wordVec = contextVector(for: surfaceWord, in: sentence, embedding: emb) else {
            logger.warning("[\(word)] '\(surfaceWord)' not found in source sentence")
            logger.debug("[\(word)] Sentence: \"\(sentence)\"")
            return nil
        }

        // Detect the part-of-speech of the surface word to penalise PoS mismatches.
        let detectedPoS = detectPartOfSpeech(of: surfaceWord, in: sentence)
        if let pos = detectedPoS {
            logger.debug("[\(word)] Detected source PoS: \(pos) (surface: '\(surfaceWord)')")
        } else {
            logger.debug("[\(word)] PoS detection failed — mismatch penalty disabled")
        }

        // Score every sense.
        struct Candidate {
            let sense: DictionarySense
            let partOfSpeech: String
            let score: Double
            let scoreSource: String     // "def" or "ex#N"
            let posMatch: Bool
            let defScore: Double
            let exampleScores: [(text: String, score: Double, viaWordVec: Bool)]
        }

        var candidates: [Candidate] = []
        for dictEntry in entry.entries {
            for sense in dictEntry.senses {
                // 1. Prefixed definition: anchors the embedding to the target word concept.
                let prefixedDef = "\(word): \(sense.definition)"
                let defScore = sentenceVector(for: prefixedDef, embedding: emb)
                    .map { cosineSimilarity(wordVec, $0) } ?? 0

                // 2. Example sentences: word-vector ↔ word-vector when possible.
                var exampleScores: [(text: String, score: Double, viaWordVec: Bool)] = []
                for example in (sense.examples ?? []) {
                    if let exWordVec = contextVector(for: word, in: example, embedding: emb) {
                        exampleScores.append((example, cosineSimilarity(wordVec, exWordVec), true))
                    } else if let exSentVec = sentenceVector(for: example, embedding: emb) {
                        exampleScores.append((example, cosineSimilarity(wordVec, exSentVec), false))
                    }
                }

                // 3. Best score = max(definition score, example scores).
                var bestScore = defScore
                var bestSource = "def"
                for (i, ex) in exampleScores.enumerated() {
                    if ex.score > bestScore {
                        bestScore = ex.score
                        bestSource = "ex#\(i + 1)"
                    }
                }

                let posMatch: Bool
                if let detectedPoS {
                    posMatch = posMatches(detected: detectedPoS, candidate: dictEntry.partOfSpeech)
                } else {
                    posMatch = true
                }

                candidates.append(Candidate(
                    sense: sense,
                    partOfSpeech: dictEntry.partOfSpeech,
                    score: bestScore,
                    scoreSource: bestSource,
                    posMatch: posMatch,
                    defScore: defScore,
                    exampleScores: exampleScores
                ))
            }
        }

        guard !candidates.isEmpty else {
            logger.warning("[\(word)] No candidates could be scored")
            return nil
        }

        // Hard PoS filter with fallback: if at least one candidate matches the detected
        // PoS, restrict consideration to those. Otherwise consider all (covers the case
        // where NLTagger misclassifies or the dictionary uses uncommon PoS labels).
        let matchingCount = candidates.filter { $0.posMatch }.count
        let posFilterActive = detectedPoS != nil && matchingCount > 0
        let considered = posFilterActive ? candidates.filter { $0.posMatch } : candidates

        // Sort full list for logging clarity; pick winner from considered set.
        candidates.sort { $0.score > $1.score }
        let sortedConsidered = considered.sorted { $0.score > $1.score }

        let elapsed = Date().timeIntervalSince(start)
        let modelSource = modelWasCached ? "cache" : "fresh load"

        logger.info("[\(word)] Ranked \(candidates.count) definition(s) in \(String(format: "%.0f", elapsed * 1000))ms (model: \(modelSource))")
        if posFilterActive, let detectedPoS {
            logger.info("[\(word)] PoS filter: keeping \(matchingCount) of \(candidates.count) candidates matching '\(detectedPoS)'")
        } else if detectedPoS != nil {
            logger.info("[\(word)] PoS filter inactive: no candidates matched detected PoS — falling back to full ranking")
        }
        logger.debug("[\(word)] Sentence: \"\(sentence)\"")

        for (i, c) in candidates.enumerated() {
            let isWinner = c.sense.definition == sortedConsidered.first?.sense.definition
                && c.partOfSpeech == sortedConsidered.first?.partOfSpeech
            let marker: String
            if isWinner {
                marker = "▶"
            } else if posFilterActive && !c.posMatch {
                marker = "✗"   // excluded by PoS filter
            } else {
                marker = " "
            }
            logger.debug("\(marker) [\(c.partOfSpeech)] score=\(String(format: "%.4f", c.score)) via=\(c.scoreSource)  \"\(c.sense.definition)\"")
            logger.debug("      def_score=\(String(format: "%.4f", c.defScore))")
            for (j, ex) in c.exampleScores.enumerated() {
                let method = ex.viaWordVec ? "wordVec" : "sentVec"
                logger.debug("      ex#\(j + 1) (\(method)) score=\(String(format: "%.4f", ex.score))  \"\(ex.text)\"")
            }
        }

        guard let best = sortedConsidered.first else { return nil }
        let delta = sortedConsidered.count > 1 ? best.score - sortedConsidered[1].score : 1.0
        let isHighConfidence = delta >= Self.confidenceDeltaThreshold

        logger.info("[\(word)] Winner: \"\(best.sense.definition)\" [\(best.partOfSpeech)] score=\(String(format: "%.4f", best.score)) via=\(best.scoreSource) delta=\(String(format: "%.4f", delta)) confidence=\(isHighConfidence ? "HIGH" : "LOW")")

        return RankedDefinition(
            sense: best.sense,
            partOfSpeech: best.partOfSpeech,
            score: best.score,
            isHighConfidence: isHighConfidence
        )
    }

    // MARK: - Model loading

    private func loadedEmbedding() -> NLContextualEmbedding? {
        if let cached = embedding {
            modelWasCached = true
            return cached
        }
        guard let emb = NLContextualEmbedding(language: .english) else {
            logger.error("NLContextualEmbedding unavailable for English on this device")
            return nil
        }
        do {
            let loadStart = Date()
            try emb.load()
            let loadElapsed = Date().timeIntervalSince(loadStart)
            logger.info("Model loaded in \(String(format: "%.0f", loadElapsed * 1000))ms (dim=\(emb.dimension))")
        } catch {
            logger.error("Model load failed: \(error.localizedDescription)")
            return nil
        }
        modelWasCached = false
        embedding = emb
        return emb
    }

    // MARK: - Embedding helpers

    private func contextVector(for word: String, in sentence: String, embedding: NLContextualEmbedding) -> [Double]? {
        guard let result = try? embedding.embeddingResult(for: sentence, language: .english) else { return nil }
        guard let wordRange = sentence.range(of: word, options: .caseInsensitive) else { return nil }

        var vectors: [[Double]] = []
        result.enumerateTokenVectors(in: wordRange) { vector, _ in
            vectors.append(vector)
            return false
        }

        if vectors.count > 1 {
            logger.debug("'\(word)' tokenized into \(vectors.count) subwords — averaging")
        }
        return vectors.isEmpty ? nil : meanPool(vectors)
    }

    private func sentenceVector(for text: String, embedding: NLContextualEmbedding) -> [Double]? {
        guard let result = try? embedding.embeddingResult(for: text, language: .english) else { return nil }
        var vectors: [[Double]] = []
        result.enumerateTokenVectors(in: text.startIndex..<text.endIndex) { vector, _ in
            vectors.append(vector)
            return false
        }
        return vectors.isEmpty ? nil : meanPool(vectors)
    }

    private func meanPool(_ vectors: [[Double]]) -> [Double] {
        guard let first = vectors.first else { return [] }
        let dim = first.count
        var sum = [Double](repeating: 0, count: dim)
        for vec in vectors {
            for i in 0..<min(dim, vec.count) { sum[i] += vec[i] }
        }
        let n = Double(vectors.count)
        return sum.map { $0 / n }
    }

    private func cosineSimilarity(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        let dot = zip(a, b).reduce(0.0) { $0 + $1.0 * $1.1 }
        let normA = sqrt(a.reduce(0.0) { $0 + $1 * $1 })
        let normB = sqrt(b.reduce(0.0) { $0 + $1 * $1 })
        guard normA > 0, normB > 0 else { return 0 }
        return dot / (normA * normB)
    }

    // MARK: - Part-of-speech detection

    private func detectPartOfSpeech(of word: String, in sentence: String) -> String? {
        guard let wordRange = sentence.range(of: word, options: .caseInsensitive) else { return nil }
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = sentence
        var detected: String? = nil
        tagger.enumerateTags(in: wordRange, unit: .word, scheme: .lexicalClass, options: []) { tag, _ in
            if let tag { detected = nlTagToPoS(tag) }
            return false
        }
        return detected
    }

    private func nlTagToPoS(_ tag: NLTag) -> String {
        switch tag {
        case .noun:         return "noun"
        case .verb:         return "verb"
        case .adjective:    return "adjective"
        case .adverb:       return "adverb"
        case .pronoun:      return "pronoun"
        case .determiner:   return "determiner"
        case .particle:     return "particle"
        case .preposition:  return "preposition"
        case .conjunction:  return "conjunction"
        case .interjection: return "interjection"
        case .number:       return "numeral"
        default:            return tag.rawValue.lowercased()
        }
    }

    // Flexible matching: handles "proper noun" containing "noun", "phrasal verb", etc.
    private func posMatches(detected: String, candidate: String) -> Bool {
        let d = detected.lowercased()
        let c = candidate.lowercased()
        return c.contains(d) || d.contains(c)
    }
}
