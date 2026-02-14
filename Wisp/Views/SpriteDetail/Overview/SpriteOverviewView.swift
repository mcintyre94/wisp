import SwiftUI

struct SpriteOverviewView: View {
    @Environment(SpritesAPIClient.self) private var apiClient
    @State private var viewModel: SpriteOverviewViewModel

    init(sprite: Sprite) {
        _viewModel = State(initialValue: SpriteOverviewViewModel(sprite: sprite))
    }

    var body: some View {
        List {
            Section("Status") {
                HStack {
                    Text("Status")
                    Spacer()
                    HStack(spacing: 6) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(statusColor)
                        Text(viewModel.sprite.status.displayName)
                    }
                }
            }

            Section("Details") {
                if let url = viewModel.sprite.url {
                    HStack {
                        Text("URL")
                        Spacer()
                        Text(viewModel.copiedURL ? "Copied!" : url)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        UIPasteboard.general.string = url
                        viewModel.copiedURL = true
                        Task {
                            try? await Task.sleep(for: .seconds(2))
                            viewModel.copiedURL = false
                        }
                    }
                }

                if let createdAt = viewModel.sprite.createdAt {
                    HStack {
                        Text("Created")
                        Spacer()
                        Text(createdAt.relativeFormatted)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .refreshable {
            await viewModel.refresh(apiClient: apiClient)
        }
        .task {
            await viewModel.refresh(apiClient: apiClient)
        }
        .alert("Error", isPresented: .init(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") {}
        } message: {
            if let error = viewModel.errorMessage {
                Text(error)
            }
        }
    }

    private var statusColor: Color {
        switch viewModel.sprite.status {
        case .running: return .green
        case .warm: return .orange
        case .cold: return .blue
        case .unknown: return .gray
        }
    }
}
