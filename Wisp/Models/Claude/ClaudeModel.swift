import Foundation

enum ClaudeEffortLevel: String, CaseIterable, Identifiable {
    case low
    case medium
    case high
    case max

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        case .max: "Max"
        }
    }

    var isDefault: Bool { self == .medium }
}

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
