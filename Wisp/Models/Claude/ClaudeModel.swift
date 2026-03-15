import Foundation

enum ClaudeModel: String, CaseIterable, Identifiable {
    case sonnet = "sonnet[1m]"
    case opus = "opus[1m]"
    case haiku

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .sonnet: "Sonnet"
        case .opus: "Opus"
        case .haiku: "Haiku"
        }
    }
}
