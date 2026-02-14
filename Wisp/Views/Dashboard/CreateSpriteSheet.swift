import SwiftUI
import SwiftData

struct CreateSpriteSheet: View {
    @Environment(SpritesAPIClient.self) private var apiClient
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var isCreating = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Sprite name", text: $name)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } footer: {
                    Text("Lowercase letters, numbers, and hyphens only")
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("New Sprite")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task { await createSprite() }
                    }
                    .disabled(name.isEmpty || isCreating)
                }
            }
            .disabled(isCreating)
        }
    }

    private func createSprite() async {
        isCreating = true
        errorMessage = nil

        do {
            _ = try await apiClient.createSprite(name: name)
            // Clear any stale session from a previous sprite with the same name
            let spriteName = name
            let descriptor = FetchDescriptor<SpriteSession>(
                predicate: #Predicate { $0.spriteName == spriteName }
            )
            if let staleSession = try? modelContext.fetch(descriptor).first {
                modelContext.delete(staleSession)
                try? modelContext.save()
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }

        isCreating = false
    }
}
