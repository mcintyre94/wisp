import SwiftUI

struct CheckpointsView: View {
    @Environment(SpritesAPIClient.self) private var apiClient
    @Bindable var viewModel: CheckpointsViewModel

    var body: some View {
        Group {
            if viewModel.checkpoints.isEmpty && !viewModel.isLoading {
                ContentUnavailableView(
                    "No Checkpoints",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Create a checkpoint to save the current state")
                )
            } else {
                List {
                    ForEach(viewModel.checkpoints) { checkpoint in
                        checkpointRow(checkpoint)
                    }
                }
            }
        }
        .overlay(alignment: .top) {
            if viewModel.isLoading && viewModel.checkpoints.isEmpty {
                ProgressView()
            }
            if viewModel.isLoading && !viewModel.checkpoints.isEmpty {
                ProgressView()
                    .scaleEffect(0.7)
                    .padding(.top, 4)
            }
            if viewModel.isRestoring {
                ZStack {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Restoring \(viewModel.restoringCheckpointId ?? "")...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .allowsHitTesting(!viewModel.isRestoring)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    viewModel.showCreateSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .task {
            await viewModel.loadCheckpoints(apiClient: apiClient)
        }
        .refreshable {
            await viewModel.loadCheckpoints(apiClient: apiClient)
        }
        .sheet(isPresented: $viewModel.showCreateSheet) {
            CreateCheckpointSheet(
                isCreating: viewModel.isCreating,
                onCreate: { comment in
                    Task {
                        await viewModel.createCheckpoint(apiClient: apiClient, comment: comment)
                    }
                }
            )
        }
        .alert("Restore Checkpoint?", isPresented: .init(
            get: { viewModel.checkpointToRestore != nil },
            set: { if !$0 { viewModel.checkpointToRestore = nil } }
        )) {
            Button("Restore", role: .destructive) {
                if let checkpoint = viewModel.checkpointToRestore {
                    Task { await viewModel.restoreCheckpoint(checkpoint: checkpoint, apiClient: apiClient) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will restore the Sprite to this checkpoint's state. Any changes since will be lost.")
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
        .alert("Checkpoint Restored", isPresented: .init(
            get: { viewModel.restoredCheckpointId != nil },
            set: { if !$0 { viewModel.restoredCheckpointId = nil } }
        )) {
            Button("OK") {}
        } message: {
            if let id = viewModel.restoredCheckpointId {
                Text("Restored to checkpoint \(id)")
            }
        }
    }

    private func checkpointRow(_ checkpoint: Checkpoint) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(checkpoint.id)
                    .font(.body)
                    .fontWeight(.medium)

                if let comment = checkpoint.comment, !comment.isEmpty {
                    Text(comment)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 12) {
                    if let createTime = checkpoint.createTime {
                        Text(createTime.relativeFormatted)
                    }
                    if checkpoint.isAuto == true {
                        Text("Auto")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color(.systemGray5), in: Capsule())
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                viewModel.checkpointToRestore = checkpoint
            } label: {
                Text("Restore")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
}
