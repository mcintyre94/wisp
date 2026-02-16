import Testing
import Foundation
@testable import Wisp

@Suite("GitHub Device Flow Client")
struct GitHubDeviceFlowClientTests {

    @Test("DeviceCodeResponse decodes correctly")
    func deviceCodeResponseDecoding() throws {
        let json = """
        {
            "device_code": "3584d83530557fdd1f46af8289938c8ef79f9dc5",
            "user_code": "WDJB-MJHT",
            "verification_uri": "https://github.com/login/device",
            "expires_in": 899,
            "interval": 5
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(DeviceCodeResponse.self, from: json)
        #expect(response.deviceCode == "3584d83530557fdd1f46af8289938c8ef79f9dc5")
        #expect(response.userCode == "WDJB-MJHT")
        #expect(response.verificationUri == "https://github.com/login/device")
        #expect(response.expiresIn == 899)
        #expect(response.interval == 5)
    }

    @Test("AccessTokenResponse decodes success")
    func accessTokenSuccessDecoding() throws {
        let json = """
        {
            "access_token": "gho_16C7e42F292c6912E7710c838347Ae178B4a",
            "token_type": "bearer",
            "scope": "repo"
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(AccessTokenResponse.self, from: json)
        #expect(response.accessToken == "gho_16C7e42F292c6912E7710c838347Ae178B4a")
        #expect(response.tokenType == "bearer")
        #expect(response.scope == "repo")
        #expect(response.error == nil)
    }

    @Test("AccessTokenResponse decodes authorization_pending")
    func accessTokenPendingDecoding() throws {
        let json = """
        {
            "error": "authorization_pending"
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(AccessTokenResponse.self, from: json)
        #expect(response.accessToken == nil)
        #expect(response.error == "authorization_pending")
    }

    @Test("AccessTokenResponse decodes slow_down")
    func accessTokenSlowDownDecoding() throws {
        let json = """
        {
            "error": "slow_down"
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(AccessTokenResponse.self, from: json)
        #expect(response.error == "slow_down")
    }

    @Test("GitHubAuthError descriptions")
    func errorDescriptions() {
        #expect(GitHubAuthError.tokenExpired.localizedDescription == "Authorization expired. Please try again.")
        #expect(GitHubAuthError.accessDenied.localizedDescription == "Access was denied. Please try again.")
        #expect(GitHubAuthError.cancelled.localizedDescription == "Authorization was cancelled.")
        #expect(GitHubAuthError.requestFailed("test").localizedDescription == "test")
    }

    @Test("KeychainKey has githubToken")
    func keychainKey() {
        #expect(KeychainKey.githubToken.rawValue == "com.wisp.github-token")
    }
}
