import SwiftUI

struct ToolResultCardView: View {
    @Bindable var card: ToolResultCard

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    card.isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.green)
                        .frame(width: 20)

                    Text("\(card.toolName) result")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(card.isExpanded ? 90 : 0))
                }
                .contentShape(Rectangle())
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)

            if card.isExpanded {
                Divider()
                ScrollView([.horizontal, .vertical], showsIndicators: false) {
                    Text(card.displayContent)
                        .font(.system(.caption2, design: .monospaced))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: true, vertical: true)
                        .padding(12)
                }
                .frame(maxHeight: 200)
            }
        }
        .background(Color(.systemGray6).opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }
}
