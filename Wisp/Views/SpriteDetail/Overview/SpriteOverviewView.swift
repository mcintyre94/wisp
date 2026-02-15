import SwiftUI

struct SpriteOverviewView: View {
    @Environment(SpritesAPIClient.self) private var apiClient
    @Environment(\.openURL) private var openURL
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
                    if viewModel.hasLoaded {
                        HStack(spacing: 6) {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 8))
                                .foregroundStyle(statusColor)
                            Text(viewModel.sprite.status.displayName)
                        }
                    } else {
                        ProgressView()
                    }
                }
            }

            Section("Details") {
                if let url = viewModel.sprite.url, let linkURL = URL(string: url) {
                    Button {
                        openURL(linkURL)
                    } label: {
                        HStack {
                            Text("URL")
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(url)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Image(systemName: "arrow.up.right")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tint(.primary)
                    .contextMenu {
                        Button {
                            UIApplication.shared.open(linkURL)
                        } label: {
                            Label("Open in Safari", systemImage: "safari")
                        }
                        Button {
                            UIPasteboard.general.string = url
                        } label: {
                            Label("Copy URL", systemImage: "doc.on.doc")
                        }
                    }
                }

                Toggle("Public URL", isOn: Binding(
                    get: { viewModel.sprite.urlSettings?.auth == "public" },
                    set: { _ in
                        Task { await viewModel.togglePublicAccess(apiClient: apiClient) }
                    }
                ))
                .disabled(viewModel.isUpdatingAuth || !viewModel.hasLoaded)

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
