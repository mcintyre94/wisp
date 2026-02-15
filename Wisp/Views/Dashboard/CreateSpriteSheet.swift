import SwiftUI
import SwiftData

struct CreateSpriteSheet: View {
    @Environment(SpritesAPIClient.self) private var apiClient
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var isCreating = false
    @State private var hasMetMinLength = false
    @State private var errorMessage: String?
    @FocusState private var isNameFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Sprite name", text: $name)
                        .focused($isNameFocused)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onChange(of: name) { _, newValue in
                            let filtered = String(newValue.lowercased().filter { ($0 >= "a" && $0 <= "z") || ($0 >= "0" && $0 <= "9") || $0 == "-" })
                            let truncated = String(filtered.prefix(63))
                            if truncated != newValue {
                                name = truncated
                            }
                            if name.count >= 3 {
                                hasMetMinLength = true
                            }
                        }
                } footer: {
                    if !name.isEmpty, name.hasPrefix("-") || name.hasSuffix("-") {
                        Text("Name must start and end with a letter or number")
                            .foregroundStyle(.red)
                    } else if hasMetMinLength, name.count < 3 {
                        Text("Name must be at least 3 characters")
                            .foregroundStyle(.red)
                    } else {
                        Text("Lowercase letters, numbers, and hyphens only")
                            .foregroundStyle(.secondary)
                    }
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
                    .disabled(name.isEmpty || nameValidationError != nil || isCreating)
                }
            }
            .disabled(isCreating)
            .onAppear { isNameFocused = true }
        }
    }

    private var nameValidationError: String? {
        if name.count < 3 {
            return "Name must be at least 3 characters"
        }
        if name.hasPrefix("-") || name.hasSuffix("-") {
            return "Name must start and end with a letter or number"
        }
        return nil
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
