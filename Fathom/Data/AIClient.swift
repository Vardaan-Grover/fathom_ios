import Foundation

protocol AIClient {
    func explainPassage(context: ContextBundle) async throws -> Explanation
}

enum AIClientError: Error {
    case network
    case badResponse
    case missingConfiguration
}

struct MockAIClient: AIClient {
    func explainPassage(context: ContextBundle) async throws -> Explanation {
        let text = """
            Explanation (mock):
            You're asking about: "\(context.selectedText)"

            Based on nearby context, this likely means:
            - The author is emphasizing tone/intent.
            - The phrase depends on what was stated just before.
            """

        return Explanation(output: text, model: "mock", cached: false)
    }
}

struct BackendAIClient: AIClient {
    func explainPassage(context: ContextBundle) async throws -> Explanation {
        let absoluteIndex =
            await NarrativeContextStore.shared.getAbsoluteIndex(
                for: context.bookID,
                selectedText: context.selectedText,
                locatorJSON: nil
            ) ?? 0

        let query = "Explain this passage: \"\(context.selectedText)\""

        let client = BackendService.shared
        let answer = try await client.queryBook(
            bookID: context.bookID,
            absoluteIndex: absoluteIndex,
            query: query
        )

        return Explanation(output: answer, model: "backend", cached: false)
    }
}
