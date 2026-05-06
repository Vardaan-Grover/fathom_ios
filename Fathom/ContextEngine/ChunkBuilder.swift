import Foundation

struct ParagraphChunk {
    let prefixParagraphs: [NarrativeParagraph]
    let paragraphs: [NarrativeParagraph]
}

struct ChunkBuilder {
    nonisolated static let targetTokenCount = 2000
    nonisolated static let charsPerToken = 4
    nonisolated static let maxParagraphs = 40
    nonisolated static let prefixSize = 3

    nonisolated static func buildChunks(from paragraphs: [NarrativeParagraph]) -> [ParagraphChunk] {
        var chunks: [ParagraphChunk] = []
        var index = 0

        while index < paragraphs.count {
            var chunkParagraphs: [NarrativeParagraph] = []
            var estimatedTokens = 0

            while index < paragraphs.count {
                let p = paragraphs[index]
                let tokens = p.text.count / charsPerToken

                if chunkParagraphs.isEmpty {
                    chunkParagraphs.append(p)
                    estimatedTokens += tokens
                    index += 1
                } else if estimatedTokens + tokens <= targetTokenCount && chunkParagraphs.count < maxParagraphs {
                    chunkParagraphs.append(p)
                    estimatedTokens += tokens
                    index += 1
                } else {
                    break
                }
            }

            let previousChunkParagraphs = chunks.last?.paragraphs ?? []
            let prefix = Array(previousChunkParagraphs.suffix(prefixSize))

            chunks.append(ParagraphChunk(
                prefixParagraphs: prefix, paragraphs: chunkParagraphs
            ))
        }

        return chunks
    }
}