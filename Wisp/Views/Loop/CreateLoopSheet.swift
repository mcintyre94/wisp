import SwiftUI
import SwiftData

struct CreateLoopSheet: View {
    let spriteName: String
    let workingDirectory: String
    @Binding var promptText: String
    let onCreateLoop: (String, LoopInterval, LoopDuration) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var interval: LoopInterval = .tenMinutes
    @State private var duration: LoopDuration = .oneWeek

    var body: some View {
        NavigationStack {
            Form {
                Section("Sprite") {
                    LabeledContent("Name", value: spriteName)
                }

                Section("Prompt") {
                    TextField("What to check...", text: $promptText, axis: .vertical)
                        .lineLimit(3...8)
                }

                Section("Check every") {
                    Picker("Interval", selection: $interval) {
                        ForEach(LoopInterval.allCases, id: \.self) { preset in
                            Text(preset.displayName).tag(preset)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Run for") {
                    Picker("Duration", selection: $duration) {
                        ForEach(LoopDuration.allCases, id: \.self) { preset in
                            Text(preset.displayName).tag(preset)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("Create Loop")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start Loop") {
                        let prompt = promptText.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !prompt.isEmpty else { return }
                        onCreateLoop(prompt, interval, duration)
                        dismiss()
                    }
                    .disabled(promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

#Preview {
    CreateLoopSheet(
        spriteName: "my-sprite",
        workingDirectory: "/home/sprite/project",
        promptText: .constant("Check PR #42 for new review comments"),
        onCreateLoop: { _, _, _ in }
    )
}
