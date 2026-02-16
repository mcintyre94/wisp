import SwiftUI

struct GitHubDeviceFlowView: View {
    let userCode: String
    let verificationURL: String
    let isPolling: Bool
    let error: String?
    let onCopyAndOpen: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text(userCode)
                .font(.system(.title, design: .monospaced, weight: .bold))
                .textSelection(.enabled)
                .padding()
                .frame(maxWidth: .infinity)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))

            Button {
                onCopyAndOpen()
            } label: {
                Label("Copy Code & Open GitHub", systemImage: "doc.on.doc")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            if isPolling {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Waiting for authorization...")
                        .foregroundStyle(.secondary)
                }
            }

            if let error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .font(.callout)
            }

            Button("Cancel", role: .cancel) {
                onCancel()
            }
            .foregroundStyle(.secondary)
        }
    }
}
