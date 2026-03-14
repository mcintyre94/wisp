import Foundation
import os

private let logger = Logger(subsystem: "com.wisp.app", category: "API")

enum SpriteWakeOutcome: Equatable, CustomStringConvertible {
    case alreadyRunning
    case runningAfterWake
    case timedOut

    var description: String {
        switch self {
        case .alreadyRunning:
            return "alreadyRunning"
        case .runningAfterWake:
            return "runningAfterWake"
        case .timedOut:
            return "timedOut"
        }
    }
}

@MainActor
struct SpriteWakeCoordinator {
    let fetchStatus: () async throws -> SpriteStatus
    let triggerWake: () async -> Void
    var sleep: (TimeInterval) async -> Void = { seconds in
        try? await Task.sleep(for: .seconds(seconds))
    }
    var timeout: TimeInterval = 45
    var pollInterval: TimeInterval = 2
    var wakeRetryInterval: TimeInterval = 12
    var maxConsecutiveNetworkFailures = 3

    func waitUntilRunning() async throws -> SpriteWakeOutcome {
        let pollCount = max(1, Int(ceil(timeout / pollInterval)))
        let wakeRetryPolls = max(1, Int(ceil(wakeRetryInterval / pollInterval)))

        var triggeredWake = false
        var lastWakePoll: Int?
        var consecutiveNetworkFailures = 0

        for poll in 0..<pollCount {
            do {
                let status = try await fetchStatus()
                consecutiveNetworkFailures = 0

                if status == .running {
                    return triggeredWake ? .runningAfterWake : .alreadyRunning
                }
            } catch {
                if Self.isGenuineNetworkIssue(error) {
                    consecutiveNetworkFailures += 1
                    if consecutiveNetworkFailures >= maxConsecutiveNetworkFailures {
                        throw error
                    }
                } else {
                    consecutiveNetworkFailures = 0
                }
            }

            if shouldTriggerWake(poll: poll, lastWakePoll: lastWakePoll, wakeRetryPolls: wakeRetryPolls) {
                triggeredWake = true
                lastWakePoll = poll
                await triggerWake()
            }

            if poll < pollCount - 1 {
                await sleep(pollInterval)
            }
        }

        return .timedOut
    }

    private func shouldTriggerWake(poll: Int, lastWakePoll: Int?, wakeRetryPolls: Int) -> Bool {
        guard let lastWakePoll else { return true }
        return poll - lastWakePoll >= wakeRetryPolls
    }

    static func isGenuineNetworkIssue(_ error: Error) -> Bool {
        if let appError = error as? AppError {
            switch appError {
            case .networkError(let underlying):
                return isGenuineNetworkIssue(underlying)
            default:
                return false
            }
        }

        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else {
            return false
        }
        let code = URLError.Code(rawValue: nsError.code)

        switch code {
        case .notConnectedToInternet,
             .networkConnectionLost,
             .cannotFindHost,
             .cannotConnectToHost,
             .dnsLookupFailed,
             .internationalRoamingOff,
             .callIsActive,
             .dataNotAllowed,
             .secureConnectionFailed,
             .cannotLoadFromNetwork:
            return true
        default:
            return false
        }
    }
}

@Observable
@MainActor
final class SpritesAPIClient {
    private let baseURL = "https://api.sprites.dev/v1"
    private let decoder = JSONDecoder.apiDecoder()
    private let encoder = JSONEncoder.apiEncoder()
    private let keychain = KeychainService.shared

    // Stored properties so @Observable tracks them for SwiftUI
    private(set) var isAuthenticated: Bool
    private(set) var hasClaudeToken: Bool
    private(set) var hasGitHubToken: Bool

    init() {
        let keychain = KeychainService.shared
        self.isAuthenticated = keychain.load(key: .spritesToken) != nil
        self.hasClaudeToken = keychain.load(key: .claudeToken) != nil
        self.hasGitHubToken = keychain.load(key: .githubToken) != nil
    }

    /// Call after saving/deleting tokens to update tracked auth state
    func refreshAuthState() {
        isAuthenticated = keychain.load(key: .spritesToken) != nil
        hasClaudeToken = keychain.load(key: .claudeToken) != nil
        hasGitHubToken = keychain.load(key: .githubToken) != nil
    }

    var spritesToken: String? {
        keychain.load(key: .spritesToken)
    }

    var claudeToken: String? {
        keychain.load(key: .claudeToken)
    }

    var githubToken: String? {
        keychain.load(key: .githubToken)
    }

    // MARK: - Sprites

    func listSprites() async throws -> [Sprite] {
        let response: SpritesListResponse = try await request(method: "GET", path: "/sprites")
        return response.sprites
    }

    func createSprite(name: String) async throws -> Sprite {
        let body = CreateSpriteRequest(name: name)
        return try await request(method: "POST", path: "/sprites", body: body)
    }

    func getSprite(name: String) async throws -> Sprite {
        return try await request(method: "GET", path: "/sprites/\(name)")
    }

    /// Best-effort wake helper for commands that work better against a running sprite.
    /// Returns `.timedOut` for slow warm-ups so callers can continue when appropriate,
    /// and only throws after repeated genuine connectivity failures.
    @discardableResult
    func wakeSpriteIfNeeded(name: String, timeout: TimeInterval = 25, pollInterval: TimeInterval = 2) async throws -> SpriteWakeOutcome {
        let coordinator = SpriteWakeCoordinator(
            fetchStatus: { [weak self] in
                guard let self else { return .unknown }
                return try await self.getSprite(name: name).status
            },
            triggerWake: { [weak self] in
                guard let self else { return }
                logger.info("Triggering wake ping for sprite \(name, privacy: .public)")
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    _ = await self.runExec(spriteName: name, command: "true", timeout: 20)
                }
            },
            timeout: timeout,
            pollInterval: pollInterval
        )

        let outcome = try await coordinator.waitUntilRunning()
        logger.info("wakeSpriteIfNeeded(\(name, privacy: .public)) -> \(outcome.description, privacy: .public)")
        return outcome
    }

    func deleteSprite(name: String) async throws {
        let _: EmptyResponse = try await request(method: "DELETE", path: "/sprites/\(name)")
    }

    func updateSprite(name: String, urlSettings: Sprite.UrlSettings) async throws -> Sprite {
        let body = UpdateSpriteRequest(urlSettings: urlSettings)
        return try await request(method: "PUT", path: "/sprites/\(name)", body: body)
    }

    // MARK: - Checkpoints

    func listCheckpoints(spriteName: String) async throws -> [Checkpoint] {
        return try await request(method: "GET", path: "/sprites/\(spriteName)/checkpoints")
    }

    func createCheckpoint(spriteName: String, comment: String?) async throws {
        try await streamingRequest(
            method: "POST",
            path: "/sprites/\(spriteName)/checkpoint",
            body: CreateCheckpointRequest(comment: comment)
        )
    }

    func restoreCheckpoint(spriteName: String, checkpointId: String) async throws {
        try await streamingRequest(
            method: "POST",
            path: "/sprites/\(spriteName)/checkpoints/\(checkpointId)/restore"
        )
    }

    // MARK: - Auth Validation

    func validateToken() async throws {
        let _: SpritesListResponse = try await request(method: "GET", path: "/sprites")
    }

    // MARK: - Exec WebSocket

    func createExecSession(spriteName: String, command: String, env: [String: String] = [:], maxRunAfterDisconnect: Int? = nil) -> ExecSession {
        var components = URLComponents()
        components.scheme = "wss"
        components.host = "api.sprites.dev"
        components.path = "/v1/sprites/\(spriteName)/exec"

        var queryItems = [
            URLQueryItem(name: "cmd", value: "bash"),
            URLQueryItem(name: "cmd", value: "-c"),
            URLQueryItem(name: "cmd", value: command),
        ]

        if let maxRunAfterDisconnect {
            queryItems.append(URLQueryItem(name: "max_run_after_disconnect", value: String(maxRunAfterDisconnect)))
        }

        for (key, value) in env {
            queryItems.append(URLQueryItem(name: "env", value: "\(key)=\(value)"))
        }

        components.queryItems = queryItems

        // URLQueryItem doesn't percent-encode semicolons (they're allowed in RFC 3986),
        // but Go's net/url (1.17+) silently drops query parameters containing literal
        // semicolons. Manually encode them so the server receives the full command.
        if let encoded = components.percentEncodedQuery {
            components.percentEncodedQuery = encoded
                .replacingOccurrences(of: ";", with: "%3B")
                .replacingOccurrences(of: "+", with: "%2B")
        }

        guard let url = components.url else {
            preconditionFailure("URLComponents with scheme=wss, host=api.sprites.dev failed to produce URL")
        }
        return ExecSession(url: url, token: spritesToken ?? "")
    }

    func attachExecSession(spriteName: String, execSessionId: String) -> ExecSession {
        var components = URLComponents()
        components.scheme = "wss"
        components.host = "api.sprites.dev"
        components.path = "/v1/sprites/\(spriteName)/exec/\(execSessionId)"

        guard let url = components.url else {
            preconditionFailure("URLComponents with scheme=wss, host=api.sprites.dev failed to produce URL")
        }
        return ExecSession(url: url, token: spritesToken ?? "")
    }

    // MARK: - Services

    /// Create or update a service and stream log events via NDJSON.
    func streamService(
        spriteName: String,
        serviceName: String,
        config: ServiceRequest,
        duration: String = "3600s"
    ) -> AsyncThrowingStream<ServiceLogEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let token = spritesToken else {
                        continuation.finish(throwing: AppError.noToken)
                        return
                    }

                    let path = "\(baseURL)/sprites/\(spriteName)/services/\(serviceName)?duration=\(duration)"
                    guard let url = URL(string: path) else {
                        continuation.finish(throwing: AppError.invalidURL)
                        return
                    }

                    var urlRequest = URLRequest(url: url)
                    urlRequest.httpMethod = "PUT"
                    urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    // Idle timeout: if no data arrives for 120s, assume connection dropped.
                    // The reconnect logic will re-establish from service logs.
                    urlRequest.timeoutInterval = 120
                    urlRequest.httpBody = try encoder.encode(config)

                    let (bytes, response) = try await URLSession.shared.bytes(for: urlRequest)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        continuation.finish(throwing: AppError.networkError(URLError(.badServerResponse)))
                        return
                    }

                    guard (200...299).contains(httpResponse.statusCode) else {
                        switch httpResponse.statusCode {
                        case 401: continuation.finish(throwing: AppError.unauthorized)
                        case 404: continuation.finish(throwing: AppError.notFound)
                        case 409: continuation.finish(throwing: AppError.serverError(statusCode: 409, message: "Service conflict"))
                        default: continuation.finish(throwing: AppError.serverError(statusCode: httpResponse.statusCode, message: nil))
                        }
                        return
                    }

                    let decoder = self.decoder
                    for try await line in bytes.lines {
                        guard !line.isEmpty, let data = line.data(using: .utf8) else { continue }
                        do {
                            let event = try decoder.decode(ServiceLogEvent.self, from: data)
                            continuation.yield(event)
                        } catch {
                            logger.warning("Failed to decode service event: \(error.localizedDescription, privacy: .public) line: \(line.prefix(200), privacy: .public)")
                        }
                    }
                    continuation.finish()
                } catch {
                    logger.error("streamService error: \(error.localizedDescription, privacy: .public)")
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    /// Reconnect to service logs (full history + continued streaming).
    func streamServiceLogs(
        spriteName: String,
        serviceName: String,
        duration: String = "3600s"
    ) -> AsyncThrowingStream<ServiceLogEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let token = spritesToken else {
                        continuation.finish(throwing: AppError.noToken)
                        return
                    }

                    let path = "\(baseURL)/sprites/\(spriteName)/services/\(serviceName)/logs?duration=\(duration)"
                    guard let url = URL(string: path) else {
                        continuation.finish(throwing: AppError.invalidURL)
                        return
                    }

                    var urlRequest = URLRequest(url: url)
                    urlRequest.httpMethod = "GET"
                    urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    urlRequest.timeoutInterval = 120

                    let (bytes, response) = try await URLSession.shared.bytes(for: urlRequest)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        continuation.finish(throwing: AppError.networkError(URLError(.badServerResponse)))
                        return
                    }

                    guard (200...299).contains(httpResponse.statusCode) else {
                        switch httpResponse.statusCode {
                        case 401: continuation.finish(throwing: AppError.unauthorized)
                        case 404: continuation.finish(throwing: AppError.notFound)
                        default: continuation.finish(throwing: AppError.serverError(statusCode: httpResponse.statusCode, message: nil))
                        }
                        return
                    }

                    let decoder = self.decoder
                    for try await line in bytes.lines {
                        guard !line.isEmpty, let data = line.data(using: .utf8) else { continue }
                        do {
                            let event = try decoder.decode(ServiceLogEvent.self, from: data)
                            continuation.yield(event)
                        } catch {
                            logger.warning("Failed to decode service log event: \(error.localizedDescription, privacy: .public) line: \(line.prefix(200), privacy: .public)")
                        }
                    }
                    continuation.finish()
                } catch {
                    logger.error("streamServiceLogs error: \(error.localizedDescription, privacy: .public)")
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    /// List all services on a sprite.
    func listServices(spriteName: String) async throws -> [ServiceInfo] {
        return try await request(method: "GET", path: "/sprites/\(spriteName)/services")
    }

    /// Check the status of a service.
    func getServiceStatus(spriteName: String, serviceName: String) async throws -> ServiceInfo {
        return try await request(method: "GET", path: "/sprites/\(spriteName)/services/\(serviceName)")
    }

    // ServiceLogsProvider conformance — bridges the default-argument version to the protocol signature.
    func streamServiceLogs(spriteName: String, serviceName: String) -> AsyncThrowingStream<ServiceLogEvent, Error> {
        streamServiceLogs(spriteName: spriteName, serviceName: serviceName, duration: "3600s")
    }
}

// MARK: - ServiceLogsProvider

/// Minimal protocol covering the two API calls used by the reconnect loop,
/// allowing the loop to be tested without a live network connection.
@MainActor
protocol ServiceLogsProvider {
    func streamServiceLogs(spriteName: String, serviceName: String) -> AsyncThrowingStream<ServiceLogEvent, Error>
    func getServiceStatus(spriteName: String, serviceName: String) async throws -> ServiceInfo
}

extension SpritesAPIClient: ServiceLogsProvider {}

extension SpritesAPIClient {

    /// Delete a service (5s timeout to avoid blocking callers if sprite is unresponsive).
    func deleteService(spriteName: String, serviceName: String) async throws {
        let _: EmptyResponse = try await request(method: "DELETE", path: "/sprites/\(spriteName)/services/\(serviceName)", timeout: 5)
    }

    // MARK: - File Upload

    struct FileUploadResponse: Codable, Sendable {
        let path: String
        let size: Int
        let mode: String
    }

    func fileExists(spriteName: String, remotePath: String) async throws -> Bool {
        guard let token = spritesToken else {
            throw AppError.noToken
        }

        guard var components = URLComponents(string: baseURL + "/sprites/\(spriteName)/fs/read") else {
            throw AppError.invalidURL
        }
        components.queryItems = [
            URLQueryItem(name: "path", value: remotePath),
        ]

        guard let url = components.url else {
            throw AppError.invalidURL
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "GET"
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (_, response) = try await URLSession.shared.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppError.networkError(URLError(.badServerResponse))
        }

        switch httpResponse.statusCode {
        case 200...299:
            return true
        case 404:
            return false
        case 401:
            throw AppError.unauthorized
        default:
            throw AppError.serverError(statusCode: httpResponse.statusCode, message: nil)
        }
    }

    func uploadFile(spriteName: String, remotePath: String, data: Data) async throws -> FileUploadResponse {
        let maxSize = 10 * 1024 * 1024 // 10 MB
        guard data.count <= maxSize else {
            throw AppError.fileTooLarge(data.count)
        }

        guard let token = spritesToken else {
            throw AppError.noToken
        }

        guard var components = URLComponents(string: baseURL + "/sprites/\(spriteName)/fs/write") else {
            throw AppError.invalidURL
        }
        components.queryItems = [
            URLQueryItem(name: "path", value: remotePath),
            URLQueryItem(name: "mkdir", value: "true"),
        ]

        guard let url = components.url else {
            throw AppError.invalidURL
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "PUT"
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = data

        let (responseData, response) = try await URLSession.shared.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppError.networkError(URLError(.badServerResponse))
        }

        let raw = String(data: responseData, encoding: .utf8) ?? "<binary>"
        logger.info("PUT /sprites/\(spriteName)/fs/write → \(httpResponse.statusCode): \(raw)")

        switch httpResponse.statusCode {
        case 200...299:
            do {
                return try decoder.decode(FileUploadResponse.self, from: responseData)
            } catch {
                logger.error("Decode FileUploadResponse: \(error)")
                throw AppError.decodingError(error)
            }
        case 401:
            throw AppError.unauthorized
        case 404:
            throw AppError.notFound
        default:
            let message = String(data: responseData, encoding: .utf8)
            throw AppError.serverError(statusCode: httpResponse.statusCode, message: message)
        }
    }

    // MARK: - Exec Helpers

    /// Run a command on a sprite via exec WebSocket, collecting output.
    /// Returns the accumulated stdout/stderr text and whether the command exited successfully before timeout.
    func runExec(spriteName: String, command: String, env: [String: String] = [:], timeout: Int = 15) async -> (output: String, success: Bool) {
        let session = createExecSession(spriteName: spriteName, command: command, env: env)
        session.connect()
        var output = Data()
        var timedOut = false
        var exitCode: Int?

        let timeoutTask = Task {
            try await Task.sleep(for: .seconds(timeout))
            timedOut = true
            session.disconnect()
        }

        do {
            for try await event in session.events() {
                if case .data(let chunk) = event {
                    output.append(chunk)
                } else if case .exit(let code) = event {
                    exitCode = code
                }
            }
        } catch {
            // Expected on timeout disconnect
        }

        timeoutTask.cancel()
        session.disconnect()
        let text = String(data: output, encoding: .utf8) ?? ""
        let succeeded = !timedOut && (exitCode.map { $0 == 0 } ?? true)
        return (text, succeeded)
    }

    // MARK: - Private

    private func request<T: Decodable>(
        method: String,
        path: String,
        body: (some Encodable)? = nil as String?,
        timeout: TimeInterval? = nil
    ) async throws -> T {
        guard let token = spritesToken else {
            throw AppError.noToken
        }

        guard let url = URL(string: baseURL + path) else {
            throw AppError.invalidURL
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = method
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let timeout {
            urlRequest.timeoutInterval = timeout
        }

        if let body {
            urlRequest.httpBody = try encoder.encode(body)
        }

        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppError.networkError(URLError(.badServerResponse))
        }

        let raw = String(data: data, encoding: .utf8) ?? "<binary>"
        logger.info("\(method) \(path) → \(httpResponse.statusCode): \(raw)")

        switch httpResponse.statusCode {
        case 200...299:
            if T.self == EmptyResponse.self {
                return EmptyResponse() as! T
            }
            do {
                return try decoder.decode(T.self, from: data)
            } catch {
                logger.error("Decode \(String(describing: T.self)): \(error)")
                throw AppError.decodingError(error)
            }
        case 401:
            throw AppError.unauthorized
        case 404:
            throw AppError.notFound
        default:
            let message = String(data: data, encoding: .utf8)
            throw AppError.serverError(statusCode: httpResponse.statusCode, message: message)
        }
    }

    /// Consume a streaming NDJSON response (checkpoint create/restore).
    /// Reads all events and throws if any event has type "error".
    private func streamingRequest(
        method: String,
        path: String,
        body: (some Encodable)? = nil as String?
    ) async throws {
        guard let token = spritesToken else {
            throw AppError.noToken
        }
        guard let url = URL(string: baseURL + path) else {
            throw AppError.invalidURL
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = method
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let body {
            urlRequest.httpBody = try encoder.encode(body)
        }

        let (bytes, response) = try await URLSession.shared.bytes(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppError.networkError(URLError(.badServerResponse))
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            switch httpResponse.statusCode {
            case 401: throw AppError.unauthorized
            case 404: throw AppError.notFound
            default: throw AppError.serverError(statusCode: httpResponse.statusCode, message: nil)
            }
        }

        let decoder = self.decoder
        for try await line in bytes.lines {
            guard !line.isEmpty, let data = line.data(using: .utf8) else { continue }
            if let event = try? decoder.decode(CheckpointStreamEvent.self, from: data) {
                if event.type == "error" {
                    throw AppError.serverError(statusCode: 500, message: event.error ?? event.data)
                }
                logger.info("Checkpoint stream: \(event.type) — \(event.data ?? "")")
            }
        }
    }
}

private struct EmptyResponse: Decodable {
    init() {}
    init(from decoder: Decoder) throws {}
}
