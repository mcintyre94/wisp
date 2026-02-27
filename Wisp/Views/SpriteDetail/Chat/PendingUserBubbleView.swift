import SwiftUI

struct PendingUserBubbleView: View {
    let text: String

    var body: some View {
        HStack {
            Spacer(minLength: 60)
            VStack(alignment: .trailing, spacing: 4) {
                Text(text)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.blue.opacity(0.4), in: RoundedRectangle(cornerRadius: 16))
                    .foregroundStyle(.white)
                Label("Queued", systemImage: "clock")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
