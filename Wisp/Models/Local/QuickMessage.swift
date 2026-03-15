import Foundation
import SwiftData

@Model
final class QuickMessage {
    var id: UUID
    var text: String
    var createdAt: Date

    init(text: String) {
        self.id = UUID()
        self.text = text
        self.createdAt = Date()
    }
}
