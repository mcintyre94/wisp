import Foundation

enum ClaudeModel: String, CaseIterable, Identifiable {
    case sonnet
    case opus
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
