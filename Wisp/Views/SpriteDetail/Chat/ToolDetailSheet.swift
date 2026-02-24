import SwiftUI

struct ToolDetailSheet: View {
    let card: ToolUseCard

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    inputSection
                    resultSection
                }
                .padding()
            }
            .navigationTitle(card.toolName)
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: card.iconName)
                .font(.system(size: 16))
                .foregroundStyle(.secondary)

            Text(card.toolName)
                .font(.headline)

            Spacer()

            if let elapsed = card.elapsedString {
                Text(elapsed)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(.systemGray5), in: Capsule())
            }
        }
    }

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Input")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            ToolInputDetailView(toolName: card.toolName, input: card.input)
                .padding(12)
                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    @ViewBuilder
    private var resultSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Output")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            if let resultCard = card.result {
                ScrollView([.horizontal, .vertical], showsIndicators: true) {
                    Text(resultCard.displayContent)
                        .font(.system(.caption2, design: .monospaced))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: true, vertical: true)
                        .padding(12)
                }
                .frame(maxHeight: 400)
                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 8))
            } else {
                Text("No output")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .italic()
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}
