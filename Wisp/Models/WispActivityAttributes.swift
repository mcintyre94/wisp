import ActivityKit
import Foundation

struct WispActivityAttributes: ActivityAttributes {
    var spriteName: String
    var userTask: String

    struct ContentState: Codable, Hashable {
        var subject: String?
        var currentIntent: String
        var currentIntentIcon: String?
        var previousIntent: String?
        var secondPreviousIntent: String?
        var intentStartDate: Date
        var intentEndDate: Date?
        var stepNumber: Int

        var isFinished: Bool { intentEndDate != nil }
    }
}
