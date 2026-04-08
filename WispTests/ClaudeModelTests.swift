import Testing
@testable import Wisp

@Suite("ClaudeEffortLevel")
struct ClaudeEffortLevelTests {

    @Test func onlyMediumIsDefault() {
        for level in ClaudeEffortLevel.allCases {
            #expect(level.isDefault == (level == .medium))
        }
    }

    @Test func allCasesHaveDisplayNames() {
        #expect(ClaudeEffortLevel.low.displayName == "Low")
        #expect(ClaudeEffortLevel.medium.displayName == "Medium")
        #expect(ClaudeEffortLevel.high.displayName == "High")
        #expect(ClaudeEffortLevel.max.displayName == "Max")
    }

    @Test func rawValuesMatchCLIFlag() {
        #expect(ClaudeEffortLevel.low.rawValue == "low")
        #expect(ClaudeEffortLevel.medium.rawValue == "medium")
        #expect(ClaudeEffortLevel.high.rawValue == "high")
        #expect(ClaudeEffortLevel.max.rawValue == "max")
    }

    @Test func identifiableUsesRawValue() {
        for level in ClaudeEffortLevel.allCases {
            #expect(level.id == level.rawValue)
        }
    }
}

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
