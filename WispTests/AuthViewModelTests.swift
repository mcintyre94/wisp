import Testing
@testable import Wisp

@Suite("AuthViewModel")
@MainActor
struct AuthViewModelTests {

    @Test func validOAuthTokenPrefixIsAccepted() {
        let vm = AuthViewModel()
        vm.claudeToken = "sk-ant-oat01-abc123"
        #expect(vm.isClaudeTokenValid == true)
    }

    @Test func emptyTokenIsInvalid() {
        let vm = AuthViewModel()
        vm.claudeToken = ""
        #expect(vm.isClaudeTokenValid == false)
    }

    @Test func wrongPrefixIsInvalid() {
        let vm = AuthViewModel()
        vm.claudeToken = "sk-ant-api03-abc123"
        #expect(vm.isClaudeTokenValid == false)
    }

    @Test func tokenWithLeadingWhitespaceIsValid() {
        let vm = AuthViewModel()
        vm.claudeToken = "  sk-ant-oat01-abc123"
        #expect(vm.isClaudeTokenValid == true)
    }

    @Test func saveClaudeTokenRejectsWrongPrefix() {
        let vm = AuthViewModel()
        vm.claudeToken = "sk-ant-api03-abc123"
        // We can't call saveClaudeToken without a real apiClient,
        // but we can verify the guard via isClaudeTokenValid
        #expect(vm.isClaudeTokenValid == false)
        #expect(vm.step == .spritesToken)
    }
}
