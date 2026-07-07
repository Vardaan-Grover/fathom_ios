import Foundation
import Auth

enum BackendError: Error {
    case invalidURL
    case unauthenticated
    case networkError(Error)
    case badResponse(Int)
    case apiError(String)
}

struct UploadURLResponse: Decodable, Sendable {
    let uploadURL: String
    let s3Key: String

    enum CodingKeys: String, CodingKey {
        case uploadURL = "upload_url"
        case s3Key = "s3_key"
    }
}

struct InitBookRequest: Encodable, Sendable {
    let s3Key: String
    let title: String
    let author: String?
    let language: String
    let contentHash: String

    enum CodingKeys: String, CodingKey {
        case s3Key = "s3_key"
        case title, author, language
        case contentHash = "content_hash"
    }
}

struct InitBookResponse: Decodable, Sendable {
    let bookID: UUID
    let status: String
    let duplicate: Bool

    enum CodingKeys: String, CodingKey {
        case bookID = "book_id"
        case status, duplicate
    }
}

struct BookPollResponse: Decodable, Sendable {
    let id: UUID
    let title: String
    let author: String?
    let language: String
    let status: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, title, author, language, status
        case createdAt = "created_at"
    }
}

struct ConversationMessage: Codable, Sendable {
    let role: String
    let content: String
}

struct AIQueryRequest: Encodable, Sendable {
    let absoluteIndex: Int
    let query: String
    let messages: [ConversationMessage]

    enum CodingKeys: String, CodingKey {
        case absoluteIndex = "absolute_index"
        case query, messages
    }
}

struct AIQueryResponse: Decodable, Sendable {
    let answer: String
}

struct APIErrorResponse: Decodable, Sendable {
    let error: String
}

actor BackendService {
    static let shared = BackendService()

    private var baseURL: URL { AppConfig.backendBaseURL }

    // Fetches a fresh (auto-refreshed) JWT from the active Supabase session.
    // Throws BackendError.unauthenticated if no session exists.
    private func accessToken() async throws -> String {
        do {
            return try await supabase.session.accessToken
        } catch {
            throw BackendError.unauthenticated
        }
    }

    private func makeRequest(path: String, method: String, body: Data? = nil) async throws -> URLRequest {
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw BackendError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(try await accessToken())", forHTTPHeaderField: "Authorization")
        if let body = body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        AppLogger.logNetworkRequest(request)
        return request
    }

    private func handleResponse<T: Decodable>(_ data: Data, _ response: URLResponse) throws -> T {
        AppLogger.logNetworkResponse(response, data: data)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BackendError.badResponse(0)
        }

        if !(200...299).contains(httpResponse.statusCode) {
            if let apiError = try? JSONDecoder().decode(APIErrorResponse.self, from: data) {
                throw BackendError.apiError(apiError.error)
            }
            throw BackendError.badResponse(httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        return try decoder.decode(T.self, from: data)
    }

    func getUploadURL(filename: String) async throws -> UploadURLResponse {
        let body = try JSONEncoder().encode(["filename": filename])
        let request = try await makeRequest(path: "/books/upload-url", method: "POST", body: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        return try handleResponse(data, response)
    }

    func uploadEPUB(uploadURL: String, fileURL: URL) async throws {
        guard let url = URL(string: uploadURL) else { throw BackendError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/epub+zip", forHTTPHeaderField: "Content-Type")

        let fileData = try Data(contentsOf: fileURL)
        AppLogger.logNetworkRequest(request)
        let (data, response) = try await URLSession.shared.upload(for: request, from: fileData)
        AppLogger.logNetworkResponse(response, data: data)

        guard let httpResponse = response as? HTTPURLResponse,
            (200...299).contains(httpResponse.statusCode)
        else {
            throw BackendError.badResponse((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
    }

    func initBook(s3Key: String, title: String, author: String?, language: String?, contentHash: String) async throws -> InitBookResponse {
        let reqBody = InitBookRequest(
            s3Key: s3Key, title: title, author: author, language: language ?? "en",
            contentHash: contentHash)
        let body = try JSONEncoder().encode(reqBody)
        let request = try await makeRequest(path: "/books", method: "POST", body: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        return try handleResponse(data, response)
    }

    func startIngestion(bookID: UUID) async throws {
        let request = try await makeRequest(
            path: "/books/\(bookID.uuidString)/start-ingestion", method: "POST")
        let (data, response) = try await URLSession.shared.data(for: request)
        AppLogger.logNetworkResponse(response, data: data)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw BackendError.badResponse((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
    }

    func pollProcessingStatus(bookID: UUID) async throws -> BookPollResponse {
        let request = try await makeRequest(path: "/books/\(bookID.uuidString)", method: "GET")
        let (data, response) = try await URLSession.shared.data(for: request)
        return try handleResponse(data, response)
    }

    func queryBook(bookID: UUID, absoluteIndex: Int, query: String, messages: [ConversationMessage] = []) async throws -> String {
        let reqBody = AIQueryRequest(absoluteIndex: absoluteIndex, query: query, messages: messages)
        let body = try JSONEncoder().encode(reqBody)
        let request = try await makeRequest(
            path: "/books/\(bookID.uuidString)/query", method: "POST", body: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let result: AIQueryResponse = try handleResponse(data, response)
        return result.answer
    }
}
