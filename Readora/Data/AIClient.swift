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
        // Mock response so UI works immediately.
        let text = """
            Explanation (mock):
            You're asking about: "\(context.selectedText)"

            Based on nearby context, this likely means:
            - The author is emphasizing tone/intent.
            - The phrase depends on what was stated just before.

            (Replace this with real API call later.)
            """

        return Explanation(output: text, model: "mock", cached: false)
    }
}

struct OpenAIClient: AIClient {
    private let apiKey: String
    private let model: String

    init(apiKey: String, model: String = "gpt-4.1") {
        self.apiKey = apiKey
        self.model = model
    }

    static func fromEnvironment() throws -> OpenAIClient {
        guard
            let key = ProcessInfo.processInfo.environment["OPENAI_API_KEY"]?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !key.isEmpty
        else {
            throw AIClientError.missingConfiguration
        }

        let model = ProcessInfo.processInfo.environment["OPENAI_MODEL"] ?? "gpt-4.1"
        return OpenAIClient(apiKey: key, model: model)
    }

    func explainPassage(context: ContextBundle) async throws -> Explanation {
        let messages: [[String: String]] = [
            [
                "role": "system",
                "content":
                    "You are an AI reading companion embedded in a book app. When a user selects a passage, explain it clearly, engagingly, and concisely. Focus on meaning, tone, literary devices, or historical context as relevant. Keep responses under 200 words.",
            ],
            [
                "role": "user",
                "content":
                    "I'm reading and I selected this passage:\n\n\"\(context.selectedText)\"\n\nCan you explain it?",
            ],
        ]

        return try await sendRequest(messages: messages)
    }

    func chat(
        messages: [AIMessage],
        passageText: String,
        retrievedContext: String?
    ) async throws -> String {
        let contextBlock: String
        if let retrievedContext, !retrievedContext.isEmpty {
            contextBlock = "\n\nUse this spoiler-safe narrative context when answering:\n\(retrievedContext)"
        } else {
            contextBlock = ""
        }

        var payload: [[String: String]] = [
            [
                "role": "system",
                "content":
                    "You are an AI reading companion embedded in a book app. The user selected this passage: \"\(passageText)\". Help them understand it, covering meaning, tone, literary devices, or historical context as relevant. Keep responses concise and under 200 words. Never reveal spoilers beyond the provided context.\(contextBlock)",
            ]
        ]
        payload +=
            messages
            .filter { $0.role != .system }
            .map { ["role": $0.role.rawValue, "content": $0.content] }
        let response = try await sendRequest(messages: payload)
        return response.output
    }

    private func sendRequest(messages: [[String: String]]) async throws -> Explanation {
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": model,
            "messages": messages,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw AIClientError.badResponse
        }

        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = json["choices"] as? [[String: Any]],
            let first = choices.first,
            let message = first["message"] as? [String: Any],
            let content = message["content"] as? String
        else {
            throw AIClientError.badResponse
        }

        return Explanation(output: content, model: model, cached: false)
    }
}
