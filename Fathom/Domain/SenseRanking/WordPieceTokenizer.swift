import Foundation

/// BERT-style WordPiece tokenizer matching the `bge-small-en-v1.5` tokenizer
/// (uncased: lowercasing + accent stripping + punctuation splitting, then
/// greedy longest-match subword segmentation).
///
/// Produces fixed-length id/mask arrays for the bundled Core ML encoder.
/// Parity with the HuggingFace tokenizer is verified by fixture tests.
struct WordPieceTokenizer {

    struct EncodedText {
        let inputIDs: [Int32]
        let attentionMask: [Int32]
    }

    static let sequenceLength = 128

    private let vocab: [String: Int32]
    private let unkID: Int32
    private let clsID: Int32
    private let sepID: Int32
    private let padID: Int32

    private static let maxInputCharsPerWord = 100

    enum TokenizerError: Error {
        case vocabularyNotFound
        case missingSpecialTokens
    }

    init(vocabFileURL: URL) throws {
        guard let contents = try? String(contentsOf: vocabFileURL, encoding: .utf8) else {
            throw TokenizerError.vocabularyNotFound
        }
        var vocab: [String: Int32] = [:]
        vocab.reserveCapacity(31000)
        var index: Int32 = 0
        for line in contents.split(separator: "\n", omittingEmptySubsequences: false) {
            guard !line.isEmpty else { continue }  // trailing newline, not a token
            vocab[String(line)] = index
            index += 1
        }
        guard
            let unk = vocab["[UNK]"], let cls = vocab["[CLS]"],
            let sep = vocab["[SEP]"], let pad = vocab["[PAD]"]
        else {
            throw TokenizerError.missingSpecialTokens
        }
        self.vocab = vocab
        self.unkID = unk
        self.clsID = cls
        self.sepID = sep
        self.padID = pad
    }

    /// Encode `text` to fixed-length (`sequenceLength`) ids + attention mask,
    /// with [CLS]/[SEP] wrapping and truncation, exactly like
    /// `tokenizer(text, padding="max_length", truncation=True, max_length=128)`.
    func encode(_ text: String) -> EncodedText {
        var pieces: [Int32] = []
        let budget = Self.sequenceLength - 2  // room for [CLS] and [SEP]
        outer: for word in basicTokenize(text) {
            for piece in wordpiece(word) {
                if pieces.count == budget { break outer }
                pieces.append(piece)
            }
        }

        var ids: [Int32] = [clsID]
        ids.append(contentsOf: pieces)
        ids.append(sepID)

        var mask = [Int32](repeating: 1, count: ids.count)
        if ids.count < Self.sequenceLength {
            let padding = Self.sequenceLength - ids.count
            ids.append(contentsOf: [Int32](repeating: padID, count: padding))
            mask.append(contentsOf: [Int32](repeating: 0, count: padding))
        }
        return EncodedText(inputIDs: ids, attentionMask: mask)
    }

    // MARK: - Basic tokenization (clean → whitespace split → lowercase/strip accents → punctuation split)

    private func basicTokenize(_ text: String) -> [String] {
        var cleaned = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            if scalar.value == 0 || scalar.value == 0xFFFD || isControl(scalar) {
                continue
            }
            if isWhitespace(scalar) {
                cleaned.append(" ")
            } else if isCJK(scalar) {
                // BERT surrounds CJK ideographs with spaces so each is its own token.
                cleaned.append(" ")
                cleaned.append(scalar)
                cleaned.append(" ")
            } else {
                cleaned.append(scalar)
            }
        }

        var tokens: [String] = []
        for word in String(cleaned).split(separator: " ") {
            // Lowercase, then strip combining marks (NFD accent stripping).
            let lowered = word.lowercased().decomposedStringWithCanonicalMapping
            var current = String.UnicodeScalarView()
            for scalar in lowered.unicodeScalars {
                if isCombiningMark(scalar) { continue }
                if isPunctuation(scalar) {
                    if !current.isEmpty {
                        tokens.append(String(current))
                        current = String.UnicodeScalarView()
                    }
                    tokens.append(String(String.UnicodeScalarView([scalar])))
                } else {
                    current.append(scalar)
                }
            }
            if !current.isEmpty { tokens.append(String(current)) }
        }
        return tokens
    }

    // MARK: - WordPiece (greedy longest-match-first)

    private func wordpiece(_ word: String) -> [Int32] {
        let scalars = Array(word.unicodeScalars)
        if scalars.count > Self.maxInputCharsPerWord { return [unkID] }

        var result: [Int32] = []
        var start = 0
        while start < scalars.count {
            var end = scalars.count
            var found: Int32? = nil
            while start < end {
                var candidate = String(String.UnicodeScalarView(scalars[start..<end]))
                if start > 0 { candidate = "##" + candidate }
                if let id = vocab[candidate] {
                    found = id
                    break
                }
                end -= 1
            }
            guard let id = found else { return [unkID] }
            result.append(id)
            start = end
        }
        return result
    }

    // MARK: - Character classes (mirroring HuggingFace BasicTokenizer)

    private func isWhitespace(_ s: Unicode.Scalar) -> Bool {
        if s == " " || s == "\t" || s == "\n" || s == "\r" { return true }
        return s.properties.generalCategory == .spaceSeparator
    }

    private func isControl(_ s: Unicode.Scalar) -> Bool {
        if s == "\t" || s == "\n" || s == "\r" { return false }
        switch s.properties.generalCategory {
        case .control, .format: return true
        default: return false
        }
    }

    private func isCombiningMark(_ s: Unicode.Scalar) -> Bool {
        s.properties.generalCategory == .nonspacingMark
    }

    private func isPunctuation(_ s: Unicode.Scalar) -> Bool {
        // BERT treats all non-letter/number ASCII as punctuation, plus Unicode P* categories.
        let v = s.value
        if (v >= 33 && v <= 47) || (v >= 58 && v <= 64) || (v >= 91 && v <= 96)
            || (v >= 123 && v <= 126)
        {
            return true
        }
        switch s.properties.generalCategory {
        case .connectorPunctuation, .dashPunctuation, .openPunctuation, .closePunctuation,
            .initialPunctuation, .finalPunctuation, .otherPunctuation:
            return true
        default:
            return false
        }
    }

    private func isCJK(_ s: Unicode.Scalar) -> Bool {
        let v = s.value
        return (0x4E00...0x9FFF).contains(v) || (0x3400...0x4DBF).contains(v)
            || (0x20000...0x2A6DF).contains(v) || (0x2A700...0x2B73F).contains(v)
            || (0x2B740...0x2B81F).contains(v) || (0x2B820...0x2CEAF).contains(v)
            || (0xF900...0xFAFF).contains(v) || (0x2F800...0x2FA1F).contains(v)
    }
}
