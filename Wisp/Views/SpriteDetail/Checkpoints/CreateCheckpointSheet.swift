import SwiftUI

struct CreateCheckpointSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var comment = ""
    let isCreating: Bool
    let onCreate: (String?) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Comment (optional)", text: $comment)
                } footer: {
                    Text("Add an optional description for this checkpoint")
                }

                if isCreating {
                    Section {
                        HStack {
                            ProgressView()
                            Text("Creating checkpoint...")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("New Checkpoint")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        onCreate(comment.isEmpty ? nil : comment)
                        dismiss()
                    }
                    .disabled(isCreating)
                }
            }
            .disabled(isCreating)
        }
    }
}
