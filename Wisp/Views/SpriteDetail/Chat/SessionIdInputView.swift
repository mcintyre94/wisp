import SwiftUI

struct SessionIdInputView: View {
    let isLoading: Bool
    let error: String?
    let onSubmit: (String) -> Void

    @State private var input = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Resume by session ID")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                TextField("Session ID or resume command", text: $input)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($isFocused)
                    .onSubmit { submit() }

                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button(action: submit) {
                        Image(systemName: "arrow.right.circle.fill")
                            .foregroundStyle(input.isEmpty ? .tertiary : .tint)
                            .font(.title3)
                    }
                    .disabled(input.isEmpty)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 10))

            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(.top, 8)
    }

    private func submit() {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onSubmit(trimmed)
    }
}

#Preview {
    VStack(spacing: 20) {
        SessionIdInputView(isLoading: false, error: nil) { _ in }
        SessionIdInputView(isLoading: true, error: nil) { _ in }
        SessionIdInputView(isLoading: false, error: "Session not found on this Sprite") { _ in }
    }
    .padding()
}
