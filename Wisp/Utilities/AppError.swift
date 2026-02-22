import Foundation

enum AppError: LocalizedError {
    case unauthorized
    case notFound
    case serverError(statusCode: Int, message: String?)
    case networkError(Error)
    case decodingError(Error)
    case webSocketError(String)
    case invalidURL
    case noToken
    case fileTooLarge(Int)

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "Authentication failed. Please check your API token."
        case .notFound:
            return "The requested resource was not found."
        case .serverError(let statusCode, let message):
            if let message {
                return "Server error (\(statusCode)): \(message)"
            }
            return "Server error (\(statusCode))"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .decodingError(let error):
            return "Failed to parse response: \(error.localizedDescription)"
        case .webSocketError(let message):
            return "WebSocket error: \(message)"
        case .invalidURL:
            return "Invalid URL."
        case .noToken:
            return "No API token configured. Please sign in."
        case .fileTooLarge(let bytes):
            let mb = Double(bytes) / 1_000_000
            return String(format: "File too large (%.1f MB). Maximum is 10 MB.", mb)
        }
    }
}
