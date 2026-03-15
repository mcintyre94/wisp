import SwiftUI

struct ShareView: View {
    @State private var viewModel: ShareViewModel

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    loadingView
                } else if let error = viewModel.errorMessage {
                    errorView(error)
                } else if viewModel.sprites.isEmpty {
                    emptyView
                } else {
                    spriteList
                }
            }
            .navigationTitle("Share to Wisp")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { viewModel.cancel() }
                        .disabled(viewModel.sendingToSpriteID != nil)
                }
            }
        }
        .task { await viewModel.load() }
    }

    // MARK: - Sub-views

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading sprites…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ message: String) -> some View {
        ContentUnavailableView(
            "Couldn't Load Sprites",
            systemImage: "exclamationmark.triangle",
            description: Text(message)
        )
    }

    private var emptyView: some View {
        ContentUnavailableView(
            "No Sprites",
            systemImage: "sparkles",
            description: Text("Create a sprite in Wisp first.")
        )
    }

    private var spriteList: some View {
        List(viewModel.sprites) { sprite in
            Button {
                Task { await viewModel.share(to: sprite) }
            } label: {
                HStack(spacing: 12) {
                    Circle()
                        .fill(statusColor(sprite.status))
                        .frame(width: 10, height: 10)
                    Text(sprite.name)
                        .foregroundStyle(.primary)
                    Spacer()
                    if viewModel.sendingToSpriteID == sprite.id {
                        ProgressView()
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .disabled(viewModel.sendingToSpriteID != nil)
        }
        .listStyle(.insetGrouped)
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "running": .green
        case "warm":    .orange
        case "cold":    .blue
        default:        .secondary
        }
    }
}
