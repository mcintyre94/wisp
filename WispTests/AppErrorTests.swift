import Testing
import Foundation
@testable import Wisp

@Suite("AppError")
struct AppErrorTests {

    @Test func allCasesHaveDescription() {
        let cases: [AppError] = [
            .unauthorized,
            .notFound,
            .serverError(statusCode: 500, message: "Internal"),
            .serverError(statusCode: 503, message: nil),
            .networkError(URLError(.notConnectedToInternet)),
            .decodingError(URLError(.cannotDecodeContentData)),
            .webSocketError("connection closed"),
            .invalidURL,
            .noToken,
        ]
        for error in cases {
            #expect(error.errorDescription != nil)
            #expect(!error.errorDescription!.isEmpty)
        }
    }

    @Test func serverErrorWithMessage() {
        let error = AppError.serverError(statusCode: 422, message: "Validation failed")
        let desc = error.errorDescription!
        #expect(desc.contains("422"))
        #expect(desc.contains("Validation failed"))
    }

    @Test func serverErrorWithoutMessage() {
        let error = AppError.serverError(statusCode: 500, message: nil)
        let desc = error.errorDescription!
        #expect(desc.contains("500"))
    }

    @Test func noTokenMentionsSignIn() {
        let error = AppError.noToken
        let desc = error.errorDescription!
        #expect(desc.lowercased().contains("sign in"))
    }
}

@Suite("SpriteWakeCoordinator")
@MainActor
struct SpriteWakeCoordinatorTests {

    @Test func alreadyRunningReturnsImmediately() async throws {
        let probe = WakeProbe(statuses: [.success(.running)])
        let coordinator = SpriteWakeCoordinator(
            fetchStatus: { try await probe.nextStatus() },
            triggerWake: { await probe.recordWake() },
            sleep: { _ in },
            timeout: 5,
            pollInterval: 1,
            wakeRetryInterval: 10
        )

        let outcome = try await coordinator.waitUntilRunning()

        #expect(outcome == .alreadyRunning)
        #expect(await probe.wakeCount() == 0)
    }

    @Test func wakeTransitionReturnsRunningAfterWake() async throws {
        let probe = WakeProbe(statuses: [
            .success(.cold),
            .success(.warm),
            .success(.running),
        ])
        let coordinator = SpriteWakeCoordinator(
            fetchStatus: { try await probe.nextStatus() },
            triggerWake: { await probe.recordWake() },
            sleep: { _ in },
            timeout: 5,
            pollInterval: 1,
            wakeRetryInterval: 10
        )

        let outcome = try await coordinator.waitUntilRunning()

        #expect(outcome == .runningAfterWake)
        #expect(await probe.wakeCount() == 1)
    }

    @Test func nonNetworkFailuresTimeOutInsteadOfThrowing() async throws {
        let probe = WakeProbe(statuses: [
            .failure(AppError.serverError(statusCode: 503, message: nil)),
            .failure(AppError.serverError(statusCode: 503, message: nil)),
            .failure(AppError.serverError(statusCode: 503, message: nil)),
        ])
        let coordinator = SpriteWakeCoordinator(
            fetchStatus: { try await probe.nextStatus() },
            triggerWake: { await probe.recordWake() },
            sleep: { _ in },
            timeout: 3,
            pollInterval: 1,
            wakeRetryInterval: 10
        )

        let outcome = try await coordinator.waitUntilRunning()

        #expect(outcome == .timedOut)
        #expect(await probe.wakeCount() == 1)
    }

    @Test func repeatedNetworkFailuresThrow() async {
        let probe = WakeProbe(statuses: [
            .failure(URLError(.notConnectedToInternet)),
            .failure(URLError(.notConnectedToInternet)),
            .failure(URLError(.notConnectedToInternet)),
        ])
        let coordinator = SpriteWakeCoordinator(
            fetchStatus: { try await probe.nextStatus() },
            triggerWake: { await probe.recordWake() },
            sleep: { _ in },
            timeout: 5,
            pollInterval: 1,
            wakeRetryInterval: 10,
            maxConsecutiveNetworkFailures: 3
        )

        do {
            try await coordinator.waitUntilRunning()
            Issue.record("Expected repeated network failures to throw")
        } catch is URLError {
            // Expected
        } catch {
            Issue.record("Expected URLError, got \(error)")
        }
    }
}

private actor WakeProbe {
    private var statuses: [Result<SpriteStatus, Error>]
    private var wakes = 0

    init(statuses: [Result<SpriteStatus, Error>]) {
        self.statuses = statuses
    }

    func nextStatus() throws -> SpriteStatus {
        guard !statuses.isEmpty else { return .running }
        return try statuses.removeFirst().get()
    }

    func recordWake() {
        wakes += 1
    }

    func wakeCount() -> Int {
        wakes
    }
}
