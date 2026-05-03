import Foundation

enum BackendError: Error {
    case invalidURL
    case unauthenticated
    case networkError(Error)
    case badResponse(Int)
    case apiError(String)
}

struct UploadURLResponse: Decodable, Sendable {
    let upload_url: String
    let s3_key: String
}

struct InitBookRequest: Encodable, Sendable {
    let s3_key: String
    let title: String
    let author: String?
    let language: String
    let content_hash: String
}

struct InitBookResponse: Decodable, Sendable {
    let book_id: UUID
    let status: String
    let duplicate: Bool
}

struct BookPollResponse: Decodable, Sendable {
    let id: UUID
    let title: String
    let author: String?
    let language: String
    let status: String
    let created_at: String
}

struct ConversationMessage: Codable, Sendable {
    let role: String
    let content: String
}

struct AIQueryRequest: Encodable, Sendable {
    let absolute_index: Int
    let query: String
    let messages: [ConversationMessage]
}

struct AIQueryResponse: Decodable, Sendable {
    let answer: String
}

struct APIErrorResponse: Decodable, Sendable {
    let error: String
}

actor BackendService {
    static let shared = BackendService()

    private var baseURL: URL {
        URL(string: "http://192.168.29.149:8080")!
    }

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

    func initBook(s3Key: String, title: String, author: String?, language: String?, contentHash: String) async throws
        -> InitBookResponse
    {
        let reqBody = InitBookRequest(
            s3_key: s3Key, title: title, author: author, language: language ?? "en", content_hash: contentHash)
        let body = try JSONEncoder().encode(reqBody)
        let request = try await makeRequest(path: "/books", method: "POST", body: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let result: InitBookResponse = try handleResponse(data, response)
        return result
    }

    func startIngestion(bookID: UUID) async throws {
        let request = try await makeRequest(
            path: "/books/\(bookID.uuidString)/start-ingestion", method: "POST")
        let (data, response) = try await URLSession.shared.data(for: request)
        let _: [String: String] = try handleResponse(data, response)
    }

    func pollProcessingStatus(bookID: UUID) async throws -> BookPollResponse {
        let request = try await makeRequest(path: "/books/\(bookID.uuidString)", method: "GET")
        let (data, response) = try await URLSession.shared.data(for: request)
        return try handleResponse(data, response)
    }

    func queryBook(bookID: UUID, absoluteIndex: Int, query: String, messages: [ConversationMessage] = []) async throws -> String {
        let reqBody = AIQueryRequest(absolute_index: absoluteIndex, query: query, messages: messages)
        let body = try JSONEncoder().encode(reqBody)
        let request = try await makeRequest(
            path: "/books/\(bookID.uuidString)/query", method: "POST", body: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let result: AIQueryResponse = try handleResponse(data, response)
        return result.answer
    }
}
