import Foundation

protocol AIChatService {
    func reply(
        bookID: UUID,
        passageText: String,
        messages: [AIMessage]
    ) async throws -> String
}

struct DefaultAIChatService: AIChatService {
    func reply(
        bookID: UUID,
        passageText: String,
        messages: [AIMessage]
    ) async throws -> String {
        let context = await NarrativeContextStore.shared.buildPromptContext(
            bookID: bookID,
            selectedText: passageText
        )

        let client = try OpenAIClient.fromEnvironment()
        return try await client.chat(
            messages: messages,
            passageText: passageText,
            retrievedContext: context.promptContext
        )
    }
}
