import SwiftUI

struct SpriteRowView: View {
    let sprite: Sprite

    var body: some View {
        HStack {
            Image(systemName: "circle.fill")
                .font(.system(size: 10))
                .foregroundStyle(statusColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(sprite.name)
                    .font(.body)
                    .fontWeight(.medium)

                if let createdAt = sprite.createdAt {
                    Text(createdAt.relativeFormatted)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text(sprite.status.displayName)
                .font(.caption)
                .foregroundStyle(statusColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(statusColor.opacity(0.15), in: Capsule())
        }
    }

    private var statusColor: Color {
        switch sprite.status {
        case .running: return .green
        case .warm: return .orange
        case .cold: return .blue
        case .unknown: return .gray
        }
    }
}
