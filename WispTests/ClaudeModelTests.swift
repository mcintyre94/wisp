import Testing
@testable import Wisp

@Suite("ClaudeModel")
struct ClaudeModelTests {

    @Test func allCasesHaveDisplayNames() {
        #expect(ClaudeModel.sonnet.displayName == "Sonnet")
        #expect(ClaudeModel.opus.displayName == "Opus")
        #expect(ClaudeModel.haiku.displayName == "Haiku")
    }

    @Test func rawValuesAre1MContextAliases() {
        #expect(ClaudeModel.sonnet.rawValue == "sonnet[1m]")
        #expect(ClaudeModel.opus.rawValue == "opus[1m]")
        #expect(ClaudeModel.haiku.rawValue == "haiku")
    }

    @Test func identifiableUsesRawValue() {
        for model in ClaudeModel.allCases {
            #expect(model.id == model.rawValue)
        }
    }

    @Test func initFromRawValue() {
        #expect(ClaudeModel(rawValue: "opus[1m]") == .opus)
        #expect(ClaudeModel(rawValue: "invalid") == nil)
    }
}
