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
