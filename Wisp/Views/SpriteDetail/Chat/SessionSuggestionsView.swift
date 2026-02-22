import SwiftUI

struct SessionSuggestionsView: View {
    let sessions: [ClaudeSessionEntry]
    let isLoading: Bool
    let onSelect: (ClaudeSessionEntry) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isLoading {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Checking for previous sessions...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
            } else if !sessions.isEmpty {
                Text("Resume a previous session")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)

                VStack(spacing: 8) {
                    ForEach(sessions) { entry in
                        Button {
                            onSelect(entry)
                        } label: {
                            sessionRow(entry)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.top, 20)
    }

    private func sessionRow(_ entry: ClaudeSessionEntry) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "bubble.left.and.text.bubble.right")
                .foregroundStyle(.tint)
                .font(.body)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.displayPrompt ?? entry.sessionId.prefix(12) + "...")
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 8) {
                    if let count = entry.messageCount {
                        Label("\(count)", systemImage: "text.bubble")
                    }
                    if let date = entry.modifiedDate {
                        Text(Self.relativeString(from: date))
                    }
                    if let branch = entry.gitBranch, !branch.isEmpty {
                        Label(branch, systemImage: "arrow.triangle.branch")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 10))
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()

    private static func relativeString(from date: Date) -> String {
        relativeFormatter.localizedString(for: date, relativeTo: .now)
    }
}
