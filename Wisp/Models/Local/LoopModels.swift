import Foundation
import SwiftData

// MARK: - Enums

enum LoopState: String, Codable, Sendable {
    case active
    case paused
    case stopped
}

enum LoopInterval: Double, Codable, Sendable, CaseIterable {
    case fiveMinutes = 300
    case tenMinutes = 600
    case fifteenMinutes = 900
    case thirtyMinutes = 1800
    case oneHour = 3600

    var seconds: TimeInterval {
        rawValue
    }

    var displayName: String {
        switch self {
        case .fiveMinutes: "5m"
        case .tenMinutes: "10m"
        case .fifteenMinutes: "15m"
        case .thirtyMinutes: "30m"
        case .oneHour: "1h"
        }
    }
}

enum LoopDuration: Double, Codable, Sendable, CaseIterable {
    case oneDay = 86400
    case threeDays = 259200
    case oneWeek = 604800
    case oneMonth = 2592000

    var timeInterval: TimeInterval {
        rawValue
    }

    var displayName: String {
        switch self {
        case .oneDay: "1 Day"
        case .threeDays: "3 Days"
        case .oneWeek: "1 Week"
        case .oneMonth: "1 Month"
        }
    }
}

enum IterationStatus: Codable, Sendable, Equatable {
    case running
    case completed
    case failed(String)
    case skipped
}

// MARK: - SpriteLoop

@Model
final class SpriteLoop {
    var id: UUID
    var spriteName: String
    var workingDirectory: String
    var prompt: String
    var intervalRaw: Double
    var stateRaw: String
    var createdAt: Date
    var expiresAt: Date
    var lastRunAt: Date?
    var iterationsData: Data?

    var interval: LoopInterval {
        get { LoopInterval(rawValue: intervalRaw) ?? .tenMinutes }
        set { intervalRaw = newValue.rawValue }
    }

    var state: LoopState {
        get { LoopState(rawValue: stateRaw) ?? .active }
        set { stateRaw = newValue.rawValue }
    }

    var isExpired: Bool {
        Date() >= expiresAt
    }

    var timeRemainingDisplay: String {
        let remaining = expiresAt.timeIntervalSince(Date())
        if remaining <= 0 { return "Expired" }

        let hours = Int(remaining) / 3600
        let days = hours / 24

        if days > 0 {
            return "\(days)d \(hours % 24)h remaining"
        } else if hours > 0 {
            let minutes = (Int(remaining) % 3600) / 60
            return "\(hours)h \(minutes)m remaining"
        } else {
            let minutes = Int(remaining) / 60
            return "\(minutes)m remaining"
        }
    }

    var iterations: [LoopIteration] {
        get {
            guard let data = iterationsData else { return [] }
            return (try? JSONDecoder().decode([LoopIteration].self, from: data)) ?? []
        }
        set {
            iterationsData = try? JSONEncoder().encode(newValue)
        }
    }

    init(
        spriteName: String,
        workingDirectory: String,
        prompt: String,
        interval: LoopInterval,
        duration: LoopDuration = .oneWeek
    ) {
        self.id = UUID()
        self.spriteName = spriteName
        self.workingDirectory = workingDirectory
        self.prompt = prompt
        self.intervalRaw = interval.rawValue
        self.stateRaw = LoopState.active.rawValue
        self.createdAt = Date()
        self.expiresAt = Date().addingTimeInterval(duration.timeInterval)
    }
}

// MARK: - LoopIteration

struct LoopIteration: Identifiable, Codable, Sendable {
    var id: UUID
    var startedAt: Date
    var completedAt: Date?
    var prompt: String
    var responseText: String?
    var status: IterationStatus
    var notificationSummary: String?

    init(prompt: String) {
        self.id = UUID()
        self.startedAt = Date()
        self.prompt = prompt
        self.status = .running
    }
}
