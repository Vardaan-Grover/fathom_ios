import Foundation

enum AppLogger {
    /// Toggle this flag to enable or disable all app-wide debugging logs.
    nonisolated(unsafe) static var isEnabled = true

    nonisolated static func log(tag: String = "App", _ message: String) {
        guard isEnabled else { return }
        print("[\(tag)] \(message)")
    }

    nonisolated static func logNetworkRequest(_ request: URLRequest) {
        guard isEnabled else { return }
        var log = "🚀 [NETWORK REQUEST]\n"
        log += "URL: \(request.url?.absoluteString ?? "Unknown")\n"
        log += "Method: \(request.httpMethod ?? "Unknown")\n"
        if let headers = request.allHTTPHeaderFields {
            log += "Headers: \(headers)\n"
        }
        if let body = request.httpBody, let bodyString = String(data: body, encoding: .utf8) {
            log += "Body: \(bodyString)\n"
        }
        print(log)
    }

    nonisolated static func logNetworkResponse(_ response: URLResponse?, data: Data?) {
        guard isEnabled else { return }
        var log = "📥 [NETWORK RESPONSE]\n"
        if let httpResponse = response as? HTTPURLResponse {
            log += "Status: \(httpResponse.statusCode)\n"
            log += "URL: \(httpResponse.url?.absoluteString ?? "Unknown")\n"
        }
        if let data = data, let dataString = String(data: data, encoding: .utf8) {
            log += "Body: \(dataString)\n"
        }
        print(log)
    }

    nonisolated static func logError(tag: String = "Error", _ error: Error) {
        guard isEnabled else { return }
        print("❌ [\(tag)] \(error.localizedDescription)")
    }
}
