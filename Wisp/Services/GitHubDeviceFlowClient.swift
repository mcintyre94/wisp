import Foundation
import os

private let logger = Logger(subsystem: "com.wisp.app", category: "GitHub")

enum GitHubAuthError: LocalizedError {
    case requestFailed(String)
    case tokenExpired
    case accessDenied
    case cancelled

    var errorDescription: String? {
        switch self {
        case .requestFailed(let message): message
        case .tokenExpired: "Authorization expired. Please try again."
        case .accessDenied: "Access was denied. Please try again."
        case .cancelled: "Authorization was cancelled."
        }
    }
}

struct DeviceCodeResponse: Decodable, Sendable {
    let deviceCode: String
    let userCode: String
    let verificationUri: String
    let expiresIn: Int
    let interval: Int

    enum CodingKeys: String, CodingKey {
        case deviceCode = "device_code"
        case userCode = "user_code"
        case verificationUri = "verification_uri"
        case expiresIn = "expires_in"
        case interval
    }
}

struct AccessTokenResponse: Decodable, Sendable {
    let accessToken: String?
    let tokenType: String?
    let scope: String?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case scope
        case error
    }
}

struct GitHubDeviceFlowClient: Sendable {
    private static let clientID = AppConfig.githubClientID

    func requestDeviceCode() async throws -> DeviceCodeResponse {
        let url = URL(string: "https://github.com/login/device/code")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = "client_id=\(Self.clientID)&scope=repo,read:org,gist,workflow".data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw GitHubAuthError.requestFailed("Failed to request device code.")
        }

        let decoder = JSONDecoder()
        return try decoder.decode(DeviceCodeResponse.self, from: data)
    }

    func pollForToken(deviceCode: String, expiresIn: Int, interval: Int) async throws -> String {
        let deadline = Date().addingTimeInterval(TimeInterval(expiresIn))
        var currentInterval = TimeInterval(interval)

        while Date() < deadline {
            try await Task.sleep(for: .seconds(currentInterval))
            try Task.checkCancellation()

            let url = URL(string: "https://github.com/login/oauth/access_token")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = "client_id=\(Self.clientID)&device_code=\(deviceCode)&grant_type=urn:ietf:params:oauth:grant-type:device_code".data(using: .utf8)

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                logger.warning("Token poll got non-2xx response")
                continue
            }

            let tokenResponse = try JSONDecoder().decode(AccessTokenResponse.self, from: data)

            if let token = tokenResponse.accessToken {
                return token
            }

            switch tokenResponse.error {
            case "authorization_pending":
                continue
            case "slow_down":
                currentInterval += 5
                continue
            case "expired_token":
                throw GitHubAuthError.tokenExpired
            case "access_denied":
                throw GitHubAuthError.accessDenied
            default:
                throw GitHubAuthError.requestFailed(tokenResponse.error ?? "Unknown error")
            }
        }

        throw GitHubAuthError.tokenExpired
    }
}
