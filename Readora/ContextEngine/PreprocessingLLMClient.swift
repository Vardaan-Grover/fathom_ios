import Foundation

nonisolated struct ExtractedMention: Codable {
    let absoluteIndex: Int
    let surfaceForm: String // exact text found
    let confidence: Double
}

nonisolated struct ExtractedEntity: Codable {
    let name: String
    let type: String
    let aliases: [String]
    let paragraphMentions: [ExtractedMention]
}

nonisolated struct EntityExtractionResponse: Codable {
    let entities: [ExtractedEntity]
}

actor PreprocessingLLMClient {
    private let apiKey: String
    private let model = "gemini-3-flash-preview"

    init(_ apiKey: String) {
        self.apiKey = apiKey
    }

    func extractEntities(chunk: ParagraphChunk) async throws -> EntityExtractionResponse {
        let userPrompt = buildEntityExtractionPrompt(chunk: chunk)

        let systemPrompt = """
        You are a literary analysis engine processing a novel for an AI Reading Companion app.
        
        You task: extract all named entities (characters, places, organizations, objects of significance) \
        from the PARAGRAPHS TO ANALYZE section.

        For each entity, return:
        - name: the most complete name used (e.g., "Elizabeth Bennet")
        - type: one of "character", "place", "organization", "object", "other"
        - aliases: other names/forms used for this entity in these paragraphs (e.g., ["Lizzy", "Miss Bennet"])
        - paragraphMentions: each specific mention, with:
        - absoluteIndex: the paragraph number (from the [N] label)
        - surfaceForm: the exact text as it appears
        - confidence: 0.0-1.0 (how confident you are this mention refers to this entity)
        RULES:
        - Do NOT extract from the CONTEXT ONLY section.
        - Derive names ONLY from the provided text. Do not use external knowledge of the book to supply surnames or first names (e.g., if a character is only called 'Miss Smith' in the text, do not output 'Jane Smith').
        - For the 'name' field, evaluate all mentions and select the longest, most formal proper name found in the text (e.g., prefer 'Maria Lucas' over 'Maria', or 'Elizabeth' over 'Eliza').
        - Do NOT include pronouns or descriptive phrases (e.g., "her daughter", "the lady", "cousin", "patroness") as aliases or mentions.
        - Only include named entities. However, capitalized honorifics or titles that function as direct substitutes for a proper name (e.g., 'Her Ladyship', 'The Colonel') SHOULD be captured as aliases and mentions. Do not capture generic lowercase nouns ('the woman', 'the man').
        - ONLY extract from paragraphs in the PARAGRAPHS TO ANALYZE section.
        - Only include named entities — not generic nouns like "man", "room", "letter".
        """

        let body: [String: Any] = [
            "systemInstruction": [
                "parts": [
                    ["text": systemPrompt]
                ]
            ],
            "contents": [
                [
                    "parts": [
                        ["text": userPrompt]
                    ]
                ]
            ],
            "generationConfig": [
                "responseMimeType": "application/json",
                "responseSchema": [
                    "type": "object",
                    "properties": [
                        "entities": [
                            "type": "array",
                            "items": [
                                "type": "object",
                                "properties": [
                                    "name": [
                                        "type": "string"
                                    ],
                                    "type": [
                                        "type": "string",
                                        "enum": [
                                            "character",
                                            "place",
                                            "organization",
                                            "object",
                                            "other"
                                        ]
                                    ],
                                    "aliases": [
                                        "type": "array",
                                        "items": [
                                            "type": "string"
                                        ]
                                    ],
                                    "paragraphMentions": [
                                        "type": "array",
                                        "items": [
                                            "type": "object",
                                            "properties": [
                                                "absoluteIndex": [
                                                    "type": "integer"
                                                ],
                                                "surfaceForm": [
                                                    "type": "string"
                                                ],
                                                "confidence": [
                                                    "type": "number"
                                                ]
                                            ],
                                            "propertyOrdering": [
                                                "absoluteIndex",
                                                "surfaceForm",
                                                "confidence"
                                            ],
                                            "required": [
                                                "absoluteIndex",
                                                "surfaceForm",
                                                "confidence"
                                            ]
                                        ]
                                    ]
                                ],
                                "propertyOrdering": [
                                    "name",
                                    "type",
                                    "aliases",
                                    "paragraphMentions"
                                ],
                                "required": [
                                    "name",
                                    "type",
                                    "aliases",
                                    "paragraphMentions"
                                ]
                            ]
                        ]
                    ],
                    "propertyOrdering": [
                        "entities"
                    ],
                    "required": [
                        "entities"
                    ]
                ]
            ]
        ]

        let url = URL(string:"https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!
        var request = URLRequest(url: url, timeoutInterval: 120)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            if let errorText = String(data: data, encoding: .utf8) {
                print("Gemini API Error: \(errorText)")
            }
            throw PreprocessingError.llmCallFailed
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let firstPart = parts.first,
              let text = firstPart["text"] as? String,
              let textData = text.data(using: .utf8)
        else {
            if let responseText = String(data: data, encoding: .utf8) {
                print("Gemini Invalid JSON Response: \(responseText)")
            }
            throw PreprocessingError.invalidResponse
        }

        let decoder = JSONDecoder()
        return try decoder.decode(EntityExtractionResponse.self, from: textData)
    }

    func buildEntityExtractionPrompt(chunk: ParagraphChunk) -> String {
        var prompt = ""

        if !chunk.prefixParagraphs.isEmpty {
            prompt += "=== CONTEXT ONLY (do not extract entities from these) ===\n"
            for p in chunk.prefixParagraphs {
                prompt += "[\(p.absoluteIndex)] \(p.text)\n\n"
            }
            prompt += "=== END CONTEXT ===\n\n"
        }

        prompt += "=== PARAGRAPHS TO ANALYZE===\n"
        for p in chunk.paragraphs {
            prompt += "[\(p.absoluteIndex)] \(p.text)\n\n"
        }

        return prompt
    }
}

enum PreprocessingError: Error {
    case llmCallFailed
    case invalidResponse
}