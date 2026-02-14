import SwiftUI

struct ToolUseCardView: View {
    @Bindable var card: ToolUseCard

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    card.isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: card.iconName)
                        .font(.system(size: 13))
                        .foregroundStyle(.orange)
                        .frame(width: 20)

                    Text(card.toolName)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)

                    Text(card.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(card.isExpanded ? 90 : 0))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)

            if card.isExpanded {
                Divider()
                ToolInputDetailView(toolName: card.toolName, input: card.input)
                    .padding(12)
            }
        }
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color(.systemGray4), lineWidth: 0.5)
        )
    }
}
