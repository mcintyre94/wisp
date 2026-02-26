import SwiftUI

struct WispAskCard: View {
    let card: ToolUseCard
    let onSubmit: (String) -> Void

    @State private var freeText = ""
    @State private var isSubmitted = false

    private var question: String {
        card.input["question"]?.stringValue ?? "Question"
    }

    private var options: [(label: String, description: String?)] {
        guard case .array(let items) = card.input["options"] else { return [] }
        return items.compactMap { item -> (label: String, description: String?)? in
            guard let label = item["label"]?.stringValue else { return nil }
            return (label, item["description"]?.stringValue)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(question, systemImage: "questionmark.bubble.fill")
                .font(.subheadline)

            if isSubmitted {
                Label("Waiting for Claude...", systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                if !options.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(options, id: \.label) { option in
                            Button {
                                submit(option.label)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(option.label)
                                        .font(.subheadline.weight(.medium))
                                    if let desc = option.description {
                                        Text(desc)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                HStack(spacing: 8) {
                    TextField(
                        options.isEmpty ? "Reply..." : "Or type a response...",
                        text: $freeText,
                        axis: .vertical
                    )
                    .font(.subheadline)
                    .lineLimit(1...4)

                    Button {
                        submit(freeText.trimmingCharacters(in: .whitespacesAndNewlines))
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title3)
                            .foregroundStyle(freeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.secondary : Color.blue)
                    }
                    .disabled(freeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(10)
                .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 16))
    }

    private func submit(_ answer: String) {
        guard !answer.isEmpty else { return }
        isSubmitted = true
        freeText = ""
        onSubmit(answer)
    }
}
