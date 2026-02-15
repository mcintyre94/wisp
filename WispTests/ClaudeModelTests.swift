import Testing
@testable import Wisp

@Suite("ClaudeModel")
struct ClaudeModelTests {

    @Test func allCasesHaveDisplayNames() {
        #expect(ClaudeModel.sonnet.displayName == "Sonnet")
        #expect(ClaudeModel.opus.displayName == "Opus")
        #expect(ClaudeModel.haiku.displayName == "Haiku")
    }

    @Test func rawValuesAreAliases() {
        #expect(ClaudeModel.sonnet.rawValue == "sonnet")
        #expect(ClaudeModel.opus.rawValue == "opus")
        #expect(ClaudeModel.haiku.rawValue == "haiku")
    }

    @Test func identifiableUsesRawValue() {
        for model in ClaudeModel.allCases {
            #expect(model.id == model.rawValue)
        }
    }

    @Test func initFromRawValue() {
        #expect(ClaudeModel(rawValue: "opus") == .opus)
        #expect(ClaudeModel(rawValue: "invalid") == nil)
    }
}
