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
        // Fallback to absolute index 0 if not found, though ideally we'd have a better fallback.
        let absoluteIndex =
            await NarrativeContextStore.shared.getAbsoluteIndex(
                for: bookID,
                selectedText: passageText
            ) ?? 0

        // The user's query is the last message; everything before it is conversation history
        guard let lastMessage = messages.last, lastMessage.role == .user else {
            return "Error: No user message found."
        }

        let history = messages.dropLast().map {
            ConversationMessage(role: $0.role.rawValue, content: $0.content)
        }

        let client = BackendService.shared
        return try await client.queryBook(
            bookID: bookID,
            absoluteIndex: absoluteIndex,
            query: lastMessage.content,
            messages: history
        )
    }
}
