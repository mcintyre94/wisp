import SwiftUI
import SwiftData

struct LoopDetailView: View {
    @Bindable var loop: SpriteLoop
    @Environment(LoopManager.self) private var loopManager
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        List {
            Section("Configuration") {
                LabeledContent("Sprite", value: loop.spriteName)
                LabeledContent("Interval", value: "Every \(loop.interval.displayName)")
                LabeledContent("Status") {
                    HStack(spacing: 4) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(statusColor)
                        Text(loop.state.rawValue.capitalized)
                    }
                }
                LabeledContent("Expires", value: loop.timeRemainingDisplay)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Prompt")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(loop.prompt)
                        .font(.body)
                }
            }

            Section {
                if loop.state == .active {
                    Button {
                        loopManager.pause(loopId: loop.id, modelContext: modelContext)
                    } label: {
                        Label("Pause Loop", systemImage: "pause.circle")
                    }
                    .tint(.orange)
                } else if loop.state == .paused {
                    Button {
                        loopManager.resume(loop: loop, modelContext: modelContext)
                    } label: {
                        Label("Resume Loop", systemImage: "play.circle")
                    }
                    .tint(.green)
                }

                Button(role: .destructive) {
                    loopManager.stop(loopId: loop.id, modelContext: modelContext)
                    modelContext.delete(loop)
                    try? modelContext.save()
                } label: {
                    Label("Delete Loop", systemImage: "trash")
                }
            }

            Section("Iterations (\(loop.iterations.count))") {
                if loop.iterations.isEmpty {
                    Text("No iterations yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(loop.iterations.reversed()) { iteration in
                        DisclosureGroup {
                            iterationContent(iteration)
                        } label: {
                            iterationLabel(iteration)
                        }
                    }
                }
            }
        }
        .navigationTitle("Loop Details")
    }

    // MARK: - Iteration Views

    @ViewBuilder
    private func iterationLabel(_ iteration: LoopIteration) -> some View {
        HStack(spacing: 8) {
            Image(systemName: iterationIcon(iteration.status))
                .foregroundStyle(iterationColor(iteration.status))

            VStack(alignment: .leading, spacing: 2) {
                Text(iteration.startedAt, style: .date)
                    .font(.subheadline)
                + Text(" ")
                    .font(.subheadline)
                + Text(iteration.startedAt, style: .time)
                    .font(.subheadline)

                if let summary = iteration.notificationSummary {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    @ViewBuilder
    private func iterationContent(_ iteration: LoopIteration) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let responseText = iteration.responseText, !responseText.isEmpty {
                Text(responseText)
                    .font(.body)
                    .textSelection(.enabled)
            } else if case .failed(let errorMessage) = iteration.status {
                Text(errorMessage)
                    .font(.body)
                    .foregroundStyle(.red)
            } else if case .running = iteration.status {
                ProgressView()
            } else {
                Text("No response")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func iterationIcon(_ status: IterationStatus) -> String {
        switch status {
        case .running: "arrow.clockwise"
        case .completed: "checkmark.circle"
        case .failed: "xmark.circle"
        case .skipped: "forward"
        }
    }

    private func iterationColor(_ status: IterationStatus) -> Color {
        switch status {
        case .running: .blue
        case .completed: .green
        case .failed: .red
        case .skipped: .gray
        }
    }

    private var statusColor: Color {
        switch loop.state {
        case .active: .green
        case .paused: .orange
        case .stopped: .gray
        }
    }
}

#Preview {
    NavigationStack {
        LoopDetailView(loop: SpriteLoop(
            spriteName: "my-sprite",
            workingDirectory: "/home/sprite/project",
            prompt: "Check PR #42 for new review comments and respond to them",
            interval: .tenMinutes
        ))
    }
    .modelContainer(for: SpriteLoop.self, inMemory: true)
}
