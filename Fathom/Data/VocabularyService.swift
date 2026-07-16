import Foundation
import os.log

public enum VocabularyServiceError: Error, LocalizedError {
    case invalidURL
    case networkError(Error)
    case notFound
    case decodingError(Error)
    case unknown(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The URL constructed for the dictionary request was invalid."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .notFound:
            return "Word not found in the dictionary."
        case .decodingError(let error):
            return "Failed to parse the dictionary response: \(error.localizedDescription)"
        case .unknown(let code):
            return "An unknown error occurred with status code: \(code)."
        }
    }
}

public class VocabularyService {
    public static let shared = VocabularyService()

    private let baseURLStr = "https://freedictionaryapi.com/api/v1/entries"
    private let logger = Logger(subsystem: "com.fathom", category: "VocabularyService")

    init() {}

    /// Retrieves dictionary entries for a specified word.
    /// - Parameters:
    ///   - word: The word to look up.
    ///   - language: ISO 639-1/639-3 language code. Defaults to "en" (English).
    ///   - includeTranslations: Whether to include translations of the word. Defaults to false.
    /// - Returns: A `DictionaryWordEntry` containing all entries and definitions.
    public func fetchWord(
        _ word: String, language: String = "en", includeTranslations: Bool = false
    ) async throws -> DictionaryWordEntry {
        guard let encodedWord = word.lowercased().addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
            let encodedLanguage = language.addingPercentEncoding(
                withAllowedCharacters: .urlPathAllowed)
        else {
            throw VocabularyServiceError.invalidURL
        }

        var urlComponents = URLComponents(string: "\(baseURLStr)/\(encodedLanguage)/\(encodedWord)")

        var queryItems = [URLQueryItem]()
        if includeTranslations {
            queryItems.append(URLQueryItem(name: "translations", value: "true"))
        }

        if !queryItems.isEmpty {
            urlComponents?.queryItems = queryItems
        }

        guard let url = urlComponents?.url else {
            throw VocabularyServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let data: Data
        let response: URLResponse

        do {
            logger.debug("Fetching dictionary entry for word: \(word), language: \(language)")
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            logger.error("Network error fetching word \(word): \(error.localizedDescription)")
            throw VocabularyServiceError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw VocabularyServiceError.unknown(-1)
        }

        switch httpResponse.statusCode {
        case 200:
            do {
                let decoder = JSONDecoder()
                let result = try decoder.decode(DictionaryWordEntry.self, from: data)
                return result
            } catch {
                logger.error("Decoding error for word \(word): \(error.localizedDescription)")
                throw VocabularyServiceError.decodingError(error)
            }
        case 404:
            logger.info("Word not found: \(word)")
            throw VocabularyServiceError.notFound
        default:
            logger.error(
                "API returned unknown status code \(httpResponse.statusCode) for word \(word)")
            throw VocabularyServiceError.unknown(httpResponse.statusCode)
        }
    }
}
