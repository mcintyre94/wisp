# Loop Feature Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add client-side recurring prompt execution ("loops") to Wisp, allowing users to babysit PRs and collaborator interactions from their phone.

**Architecture:** Loops are SwiftData-persisted objects created from the chat input bar (long-press Send). A `LoopManager` singleton runs iterations via in-app timers (foreground) and `BGAppRefreshTask` (background). Each iteration fires a fresh `claude -p` exec on the sprite, stores the transcript, and posts a local notification.

**Tech Stack:** SwiftUI, SwiftData, BackgroundTasks framework, UserNotifications framework, existing SpritesAPIClient/ClaudeStreamParser infrastructure.

---

## Task 1: Loop SwiftData Models

**Files:**
- Create: `Wisp/Models/Local/LoopModels.swift`
- Create: `WispTests/LoopModelTests.swift`

**Step 1: Write the failing test**

Create `WispTests/LoopModelTests.swift`:

```swift
import Testing
import Foundation
@testable import Wisp

@Suite("Loop Model Tests")
struct LoopModelTests {

    @Test func loopDefaults() {
        let loop = SpriteLoop(
            spriteName: "test-sprite",
            workingDirectory: "/home/sprite/project",
            prompt: "Check PR #42",
            interval: .tenMinutes
        )

        #expect(loop.state == .active)
        #expect(loop.spriteName == "test-sprite")
        #expect(loop.prompt == "Check PR #42")
        #expect(loop.interval == .tenMinutes)
        #expect(loop.iterations.isEmpty)
        #expect(loop.lastRunAt == nil)
    }

    @Test func loopDefaultDuration_oneWeek() {
        let loop = SpriteLoop(
            spriteName: "s",
            workingDirectory: "/home/sprite/project",
            prompt: "check",
            interval: .fiveMinutes
        )

        let expectedExpiry = loop.createdAt.addingTimeInterval(7 * 24 * 3600)
        let diff = abs(loop.expiresAt.timeIntervalSince(expectedExpiry))
        #expect(diff < 1.0)
    }

    @Test func loopDurationPresets() {
        #expect(LoopDuration.oneDay.timeInterval == 86400)
        #expect(LoopDuration.threeDays.timeInterval == 259200)
        #expect(LoopDuration.oneWeek.timeInterval == 604800)
        #expect(LoopDuration.oneMonth.timeInterval == 2592000)
    }

    @Test func loopIntervalPresets() {
        #expect(LoopInterval.fiveMinutes.seconds == 300)
        #expect(LoopInterval.tenMinutes.seconds == 600)
        #expect(LoopInterval.fifteenMinutes.seconds == 900)
        #expect(LoopInterval.thirtyMinutes.seconds == 1800)
        #expect(LoopInterval.oneHour.seconds == 3600)
    }

    @Test func loopIsExpired() {
        let loop = SpriteLoop(
            spriteName: "s",
            workingDirectory: "/w",
            prompt: "p",
            interval: .fiveMinutes,
            duration: .oneDay
        )
        #expect(!loop.isExpired)

        let expiredLoop = SpriteLoop(
            spriteName: "s",
            workingDirectory: "/w",
            prompt: "p",
            interval: .fiveMinutes,
            duration: .oneDay
        )
        // Manually backdate
        expiredLoop.createdAt = Date(timeIntervalSinceNow: -2 * 86400)
        expiredLoop.expiresAt = Date(timeIntervalSinceNow: -86400)
        #expect(expiredLoop.isExpired)
    }

    @Test func loopTimeRemainingDisplay() {
        let loop = SpriteLoop(
            spriteName: "s",
            workingDirectory: "/w",
            prompt: "p",
            interval: .fiveMinutes,
            duration: .oneWeek
        )
        let display = loop.timeRemainingDisplay
        #expect(display.contains("6") || display.contains("7"))
    }

    @Test func iterationStatus_defaultIsRunning() {
        let iteration = LoopIteration(prompt: "check PR")
        #expect(iteration.status == .running)
        #expect(iteration.completedAt == nil)
    }
}
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild -scheme Wisp -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test 2>&1 | tail -20`
Expected: FAIL — types don't exist yet

**Step 3: Write minimal implementation**

Create `Wisp/Models/Local/LoopModels.swift`:

```swift
import Foundation
import SwiftData

enum LoopState: String, Codable, Sendable {
    case active
    case paused
    case stopped
}

enum LoopInterval: Double, Codable, Sendable, CaseIterable {
    case fiveMinutes = 300
    case tenMinutes = 600
    case fifteenMinutes = 900
    case thirtyMinutes = 1800
    case oneHour = 3600

    var seconds: TimeInterval { rawValue }

    var displayName: String {
        switch self {
        case .fiveMinutes: "5m"
        case .tenMinutes: "10m"
        case .fifteenMinutes: "15m"
        case .thirtyMinutes: "30m"
        case .oneHour: "1h"
        }
    }
}

enum LoopDuration: Double, Codable, Sendable, CaseIterable {
    case oneDay = 86400
    case threeDays = 259200
    case oneWeek = 604800
    case oneMonth = 2592000

    var timeInterval: TimeInterval { rawValue }

    var displayName: String {
        switch self {
        case .oneDay: "1 Day"
        case .threeDays: "3 Days"
        case .oneWeek: "1 Week"
        case .oneMonth: "1 Month"
        }
    }
}

enum IterationStatus: Codable, Sendable, Equatable {
    case running
    case completed
    case failed(String)
    case skipped
}

@Model
final class SpriteLoop {
    var id: UUID
    var spriteName: String
    var workingDirectory: String
    var prompt: String
    var intervalRaw: Double
    var stateRaw: String
    var createdAt: Date
    var expiresAt: Date
    var lastRunAt: Date?
    var iterationsData: Data?

    var interval: LoopInterval {
        get { LoopInterval(rawValue: intervalRaw) ?? .tenMinutes }
        set { intervalRaw = newValue.rawValue }
    }

    var state: LoopState {
        get { LoopState(rawValue: stateRaw) ?? .active }
        set { stateRaw = newValue.rawValue }
    }

    var isExpired: Bool {
        Date() >= expiresAt
    }

    var timeRemainingDisplay: String {
        let remaining = expiresAt.timeIntervalSince(Date())
        if remaining <= 0 { return "Expired" }
        let days = Int(remaining / 86400)
        let hours = Int(remaining.truncatingRemainder(dividingBy: 86400) / 3600)
        if days > 0 { return "Ends in \(days)d \(hours)h" }
        if hours > 0 { return "Ends in \(hours)h" }
        let minutes = Int(remaining / 60)
        return "Ends in \(minutes)m"
    }

    var iterations: [LoopIteration] {
        get {
            guard let data = iterationsData else { return [] }
            return (try? JSONDecoder().decode([LoopIteration].self, from: data)) ?? []
        }
        set {
            iterationsData = try? JSONEncoder().encode(newValue)
        }
    }

    init(
        spriteName: String,
        workingDirectory: String,
        prompt: String,
        interval: LoopInterval,
        duration: LoopDuration = .oneWeek
    ) {
        self.id = UUID()
        self.spriteName = spriteName
        self.workingDirectory = workingDirectory
        self.prompt = prompt
        self.intervalRaw = interval.rawValue
        self.stateRaw = LoopState.active.rawValue
        self.createdAt = Date()
        self.expiresAt = Date().addingTimeInterval(duration.timeInterval)
    }
}

struct LoopIteration: Identifiable, Codable, Sendable {
    let id: UUID
    let startedAt: Date
    var completedAt: Date?
    var prompt: String
    var responseText: String?
    var status: IterationStatus
    var notificationSummary: String?

    init(prompt: String) {
        self.id = UUID()
        self.startedAt = Date()
        self.prompt = prompt
        self.status = .running
    }
}
```

**Step 4: Register SpriteLoop in the model container**

Modify `Wisp/App/WispApp.swift:35` — add `SpriteLoop.self` to the model container:

```swift
.modelContainer(for: [SpriteChat.self, SpriteSession.self, SpriteLoop.self])
```

**Step 5: Run tests to verify they pass**

Run: `xcodebuild -scheme Wisp -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test 2>&1 | tail -20`
Expected: PASS

**Step 6: Commit**

```bash
git add Wisp/Models/Local/LoopModels.swift WispTests/LoopModelTests.swift Wisp/App/WispApp.swift
git commit -m "Add SpriteLoop and LoopIteration SwiftData models"
```

---

## Task 2: NotificationService

**Files:**
- Create: `Wisp/Services/NotificationService.swift`
- Create: `WispTests/NotificationServiceTests.swift`

**Step 1: Write the failing test**

Create `WispTests/NotificationServiceTests.swift`:

```swift
import Testing
import Foundation
@testable import Wisp

@Suite("NotificationService Tests")
struct NotificationServiceTests {

    @Test func buildNotificationContent_setsFields() {
        let content = NotificationService.buildContent(
            title: "Loop: my-sprite",
            body: "PR #42 has 2 new comments",
            loopId: UUID().uuidString,
            iterationId: UUID().uuidString
        )

        #expect(content.title == "Loop: my-sprite")
        #expect(content.body == "PR #42 has 2 new comments")
        #expect(content.sound != nil)
    }

    @Test func truncatedSummary_shortText() {
        let text = "All checks passing"
        #expect(NotificationService.truncatedSummary(text, maxLength: 120) == text)
    }

    @Test func truncatedSummary_longText() {
        let text = String(repeating: "a", count: 200)
        let result = NotificationService.truncatedSummary(text, maxLength: 120)
        #expect(result.count == 123) // 120 + "..."
        #expect(result.hasSuffix("..."))
    }
}
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild -scheme Wisp -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test 2>&1 | tail -20`
Expected: FAIL

**Step 3: Write minimal implementation**

Create `Wisp/Services/NotificationService.swift`:

```swift
import Foundation
import UserNotifications

enum NotificationService {

    static func requestPermission() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    static func buildContent(
        title: String,
        body: String,
        loopId: String,
        iterationId: String
    ) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = [
            "loopId": loopId,
            "iterationId": iterationId,
        ]
        return content
    }

    static func postNotification(
        title: String,
        body: String,
        loopId: String,
        iterationId: String
    ) async {
        let content = buildContent(
            title: title,
            body: body,
            loopId: loopId,
            iterationId: iterationId
        )
        let request = UNNotificationRequest(
            identifier: iterationId,
            content: content,
            trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    static func truncatedSummary(_ text: String, maxLength: Int = 120) -> String {
        if text.count <= maxLength { return text }
        return String(text.prefix(maxLength)) + "..."
    }
}
```

**Step 4: Run tests to verify they pass**

Run: `xcodebuild -scheme Wisp -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test 2>&1 | tail -20`
Expected: PASS

**Step 5: Commit**

```bash
git add Wisp/Services/NotificationService.swift WispTests/NotificationServiceTests.swift
git commit -m "Add NotificationService for loop iteration notifications"
```

---

## Task 3: LoopManager Core (Timer-based Foreground Execution)

**Files:**
- Create: `Wisp/Services/LoopManager.swift`
- Create: `WispTests/LoopManagerTests.swift`

This is the biggest task. The LoopManager:
1. Holds a `Timer` per active loop
2. On each tick: wakes sprite if needed, runs `claude -p`, stores iteration, posts notification
3. Checks expiry and stops expired loops

**Step 1: Write the failing test**

Create `WispTests/LoopManagerTests.swift`:

```swift
import Testing
import Foundation
import SwiftData
@testable import Wisp

@Suite("LoopManager Tests")
@MainActor
struct LoopManagerTests {

    private func makeModelContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: SpriteLoop.self, SpriteChat.self, SpriteSession.self,
            configurations: config
        )
        return ModelContext(container)
    }

    @Test func startLoop_createsAndPersists() throws {
        let ctx = try makeModelContext()
        let manager = LoopManager()

        let loop = SpriteLoop(
            spriteName: "test-sprite",
            workingDirectory: "/home/sprite/project",
            prompt: "Check PR #42",
            interval: .tenMinutes
        )

        manager.register(loop: loop, modelContext: ctx)

        #expect(manager.activeLoopIds.contains(loop.id))
    }

    @Test func stopLoop_removesFromActive() throws {
        let ctx = try makeModelContext()
        let manager = LoopManager()

        let loop = SpriteLoop(
            spriteName: "test-sprite",
            workingDirectory: "/home/sprite/project",
            prompt: "Check PR",
            interval: .fiveMinutes
        )

        manager.register(loop: loop, modelContext: ctx)
        manager.stop(loopId: loop.id, modelContext: ctx)

        #expect(!manager.activeLoopIds.contains(loop.id))
    }

    @Test func pauseAndResume() throws {
        let ctx = try makeModelContext()
        let manager = LoopManager()

        let loop = SpriteLoop(
            spriteName: "s",
            workingDirectory: "/w",
            prompt: "p",
            interval: .fiveMinutes
        )
        ctx.insert(loop)
        try ctx.save()

        manager.register(loop: loop, modelContext: ctx)
        manager.pause(loopId: loop.id, modelContext: ctx)
        #expect(loop.state == .paused)
        #expect(!manager.activeLoopIds.contains(loop.id))

        manager.resume(loop: loop, modelContext: ctx)
        #expect(loop.state == .active)
        #expect(manager.activeLoopIds.contains(loop.id))
    }

    @Test func expiredLoop_stopsAutomatically() throws {
        let ctx = try makeModelContext()
        let manager = LoopManager()

        let loop = SpriteLoop(
            spriteName: "s",
            workingDirectory: "/w",
            prompt: "p",
            interval: .fiveMinutes,
            duration: .oneDay
        )
        loop.createdAt = Date(timeIntervalSinceNow: -2 * 86400)
        loop.expiresAt = Date(timeIntervalSinceNow: -86400)
        ctx.insert(loop)
        try ctx.save()

        manager.register(loop: loop, modelContext: ctx)

        // Should detect expiry and not register
        #expect(!manager.activeLoopIds.contains(loop.id))
        #expect(loop.state == .stopped)
    }
}
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild -scheme Wisp -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test 2>&1 | tail -20`
Expected: FAIL

**Step 3: Write implementation**

Create `Wisp/Services/LoopManager.swift`:

```swift
import Foundation
import SwiftData
import os

private let logger = Logger(subsystem: "com.wisp.app", category: "LoopManager")

@Observable
@MainActor
final class LoopManager {
    private var timers: [UUID: Timer] = [:]
    private var runningIterations: Set<UUID> = []

    var activeLoopIds: Set<UUID> {
        Set(timers.keys)
    }

    /// Register a loop and start its timer. Runs the first iteration immediately.
    func register(loop: SpriteLoop, modelContext: ModelContext) {
        guard loop.state == .active else { return }

        if loop.isExpired {
            loop.state = .stopped
            try? modelContext.save()
            return
        }

        let loopId = loop.id
        let interval = loop.interval.seconds

        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick(loopId: loopId, modelContext: modelContext)
            }
        }
        timers[loopId] = timer

        // Run first iteration immediately
        Task {
            await runIteration(loopId: loopId, modelContext: modelContext)
        }
    }

    func pause(loopId: UUID, modelContext: ModelContext) {
        timers[loopId]?.invalidate()
        timers.removeValue(forKey: loopId)

        let descriptor = FetchDescriptor<SpriteLoop>(
            predicate: #Predicate { $0.id == loopId }
        )
        if let loop = try? modelContext.fetch(descriptor).first {
            loop.state = .paused
            try? modelContext.save()
        }
    }

    func resume(loop: SpriteLoop, modelContext: ModelContext) {
        loop.state = .active
        try? modelContext.save()
        register(loop: loop, modelContext: modelContext)
    }

    func stop(loopId: UUID, modelContext: ModelContext) {
        timers[loopId]?.invalidate()
        timers.removeValue(forKey: loopId)

        let descriptor = FetchDescriptor<SpriteLoop>(
            predicate: #Predicate { $0.id == loopId }
        )
        if let loop = try? modelContext.fetch(descriptor).first {
            loop.state = .stopped
            try? modelContext.save()
        }
    }

    func stopAll() {
        for (_, timer) in timers {
            timer.invalidate()
        }
        timers.removeAll()
    }

    /// Restore active loops from SwiftData on app launch
    func restoreLoops(modelContext: ModelContext) {
        let activeRaw = LoopState.active.rawValue
        let descriptor = FetchDescriptor<SpriteLoop>(
            predicate: #Predicate { $0.stateRaw == activeRaw }
        )
        guard let loops = try? modelContext.fetch(descriptor) else { return }
        for loop in loops {
            register(loop: loop, modelContext: modelContext)
        }
    }

    // MARK: - Private

    private func tick(loopId: UUID, modelContext: ModelContext) {
        guard !runningIterations.contains(loopId) else {
            logger.info("Skipping tick for \(loopId) — previous iteration still running")
            return
        }

        Task {
            await runIteration(loopId: loopId, modelContext: modelContext)
        }
    }

    private func runIteration(loopId: UUID, modelContext: ModelContext) async {
        let descriptor = FetchDescriptor<SpriteLoop>(
            predicate: #Predicate { $0.id == loopId }
        )
        guard let loop = try? modelContext.fetch(descriptor).first else {
            stop(loopId: loopId, modelContext: modelContext)
            return
        }

        if loop.isExpired {
            loop.state = .stopped
            try? modelContext.save()
            timers[loopId]?.invalidate()
            timers.removeValue(forKey: loopId)

            await NotificationService.postNotification(
                title: "Loop ended",
                body: NotificationService.truncatedSummary(loop.prompt),
                loopId: loopId.uuidString,
                iterationId: UUID().uuidString
            )
            return
        }

        runningIterations.insert(loopId)
        defer { runningIterations.remove(loopId) }

        var iteration = LoopIteration(prompt: loop.prompt)

        logger.info("Running iteration for loop \(loopId) on sprite \(loop.spriteName)")

        // Execute claude -p on the sprite
        let result = await executeLoopPrompt(
            spriteName: loop.spriteName,
            workingDirectory: loop.workingDirectory,
            prompt: loop.prompt
        )

        switch result {
        case .success(let responseText):
            iteration.status = .completed
            iteration.responseText = responseText
            iteration.notificationSummary = NotificationService.truncatedSummary(responseText)
        case .failure(let error):
            iteration.status = .failed(error.localizedDescription)
        }

        iteration.completedAt = Date()
        loop.lastRunAt = Date()

        var iterations = loop.iterations
        iterations.insert(iteration, at: 0)
        loop.iterations = iterations
        try? modelContext.save()

        // Post notification
        let title = "Loop: \(loop.spriteName)"
        let body: String
        switch iteration.status {
        case .completed:
            body = iteration.notificationSummary ?? "Completed"
        case .failed(let error):
            body = "Failed: \(error)"
        default:
            body = "Completed"
        }

        await NotificationService.postNotification(
            title: title,
            body: body,
            loopId: loopId.uuidString,
            iterationId: iteration.id.uuidString
        )
    }

    /// Execute a one-shot claude -p command on a sprite.
    /// This is a simplified version of ChatViewModel.executeClaudeCommand
    /// that doesn't need session resumption, worktrees, or MCP tools.
    private func executeLoopPrompt(
        spriteName: String,
        workingDirectory: String,
        prompt: String
    ) async -> Result<String, Error> {
        // TODO: Task 5 will implement this using SpritesAPIClient
        return .failure(NSError(domain: "LoopManager", code: -1, userInfo: [
            NSLocalizedDescriptionKey: "Not yet implemented",
        ]))
    }
}
```

**Step 4: Run tests to verify they pass**

Run: `xcodebuild -scheme Wisp -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test 2>&1 | tail -20`
Expected: PASS

**Step 5: Commit**

```bash
git add Wisp/Services/LoopManager.swift WispTests/LoopManagerTests.swift
git commit -m "Add LoopManager with timer-based foreground execution"
```

---

## Task 4: CreateLoopSheet UI

**Files:**
- Create: `Wisp/Views/Loop/CreateLoopSheet.swift`
- Modify: `Wisp/Views/SpriteDetail/Chat/ChatInputBar.swift`

**Step 1: Create the loop creation sheet**

Create `Wisp/Views/Loop/CreateLoopSheet.swift`:

```swift
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
```

**Step 2: Add long-press gesture to Send button in ChatInputBar**

Modify `Wisp/Views/SpriteDetail/Chat/ChatInputBar.swift`. Add a callback and long-press gesture to the send button. The send button (lines 76-85) needs to be wrapped:

Add a new callback parameter to the struct:

```swift
var onLongPressSend: (() -> Void)? = nil
```

Replace the send button (lines 76-85) with:

```swift
Button {
    isFocused.wrappedValue = false
    onSend()
} label: {
    Image(systemName: "arrow.up.circle.fill")
        .font(.title2)
}
.tint(isEmpty || hasQueuedMessage ? .gray : Color("AccentColor"))
.disabled(isEmpty || hasQueuedMessage)
.buttonStyle(.glass)
.onLongPressGesture {
    if !isEmpty && !hasQueuedMessage {
        onLongPressSend?()
    }
}
```

**Step 3: Wire up the sheet in ChatView**

Read `Wisp/Views/SpriteDetail/Chat/ChatView.swift` to find where `ChatInputBar` is used, then add:
- A `@State private var showCreateLoopSheet = false` property
- Pass `onLongPressSend: { showCreateLoopSheet = true }` to `ChatInputBar`
- A `.sheet(isPresented: $showCreateLoopSheet)` modifier presenting `CreateLoopSheet`
- The `onCreateLoop` callback creates a `SpriteLoop`, inserts it into the model context, and registers it with `LoopManager`

This requires reading `ChatView.swift` to find the exact insertion points. The `LoopManager` needs to be added to the environment (see Task 6).

**Step 4: Build and verify the UI appears**

Run: `xcodebuild -scheme Wisp -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

**Step 5: Commit**

```bash
git add Wisp/Views/Loop/CreateLoopSheet.swift Wisp/Views/SpriteDetail/Chat/ChatInputBar.swift Wisp/Views/SpriteDetail/Chat/ChatView.swift
git commit -m "Add CreateLoopSheet with long-press send gesture"
```

---

## Task 5: Loop Execution Engine (Wire LoopManager to SpritesAPIClient)

**Files:**
- Modify: `Wisp/Services/LoopManager.swift`

This replaces the TODO stub in `executeLoopPrompt` with real sprite exec logic. The key difference from `ChatViewModel.executeClaudeCommand` is that this is a simplified one-shot execution: no session resumption, no worktrees, no MCP tools, no reconnect logic. It just needs to:
1. Wake the sprite if needed
2. Run `claude -p` via the service API
3. Collect the full response text
4. Return it

**Step 1: Add apiClient dependency to LoopManager**

The `LoopManager` needs access to `SpritesAPIClient`. Add it as a property and pass it through:

```swift
var apiClient: SpritesAPIClient?
```

Update `executeLoopPrompt` to use `apiClient`:

```swift
private func executeLoopPrompt(
    spriteName: String,
    workingDirectory: String,
    prompt: String
) async -> Result<String, Error> {
    guard let apiClient else {
        return .failure(NSError(domain: "LoopManager", code: -1, userInfo: [
            NSLocalizedDescriptionKey: "No API client configured",
        ]))
    }

    // Wake sprite if needed
    do {
        let sprite = try await apiClient.getSprite(name: spriteName)
        if sprite.status != .running {
            try await apiClient.wakeSprite(name: spriteName)
            // Wait for sprite to be running
            for _ in 0..<30 {
                try await Task.sleep(for: .seconds(2))
                let updated = try await apiClient.getSprite(name: spriteName)
                if updated.status == .running { break }
            }
        }
    } catch {
        return .failure(error)
    }

    guard let claudeToken = apiClient.claudeToken else {
        return .failure(NSError(domain: "LoopManager", code: -2, userInfo: [
            NSLocalizedDescriptionKey: "No Claude token configured",
        ]))
    }

    let escapedPrompt = prompt.replacingOccurrences(of: "'", with: "'\\''")

    let commandParts = [
        "export CLAUDE_CODE_OAUTH_TOKEN='\(claudeToken)'",
        "mkdir -p \(workingDirectory)",
        "cd \(workingDirectory)",
        "claude -p --verbose --output-format stream-json --dangerously-skip-permissions '\(escapedPrompt)'",
    ]
    let fullCommand = commandParts.joined(separator: " && ")

    let serviceName = "wisp-loop-\(UUID().uuidString.prefix(8).lowercased())"
    let config = ServiceRequest(
        cmd: "bash",
        args: ["-c", fullCommand],
        needs: nil,
        httpPort: nil
    )

    let stream = apiClient.streamService(
        spriteName: spriteName,
        serviceName: serviceName,
        config: config
    )

    // Collect response text from NDJSON events
    var responseText = ""
    let parser = ClaudeStreamParser()

    do {
        for try await event in stream {
            guard case .stdout(let data) = event else { continue }
            let parsed = parser.feed(data)
            for claudeEvent in parsed {
                if case .assistant(let message) = claudeEvent {
                    for block in message.content {
                        if case .text(let text) = block {
                            responseText += text
                        }
                    }
                }
            }
        }
    } catch {
        if responseText.isEmpty {
            return .failure(error)
        }
    }

    // Clean up service
    try? await apiClient.deleteService(spriteName: spriteName, serviceName: serviceName)

    return .success(responseText.isEmpty ? "(No response)" : responseText)
}
```

> **Note to implementer:** The exact types for `ServiceLogEvent` and `ClaudeStreamParser` need to be verified against the actual codebase. Read `Wisp/Services/ClaudeStreamParser.swift` and `Wisp/Models/API/ServiceTypes.swift` to confirm the event enum cases and parser API. The above is a sketch — adapt to match the real types.

**Step 2: Build and verify**

Run: `xcodebuild -scheme Wisp -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add Wisp/Services/LoopManager.swift
git commit -m "Wire LoopManager execution to SpritesAPIClient"
```

---

## Task 6: Dashboard Loops Section & Loop Detail View

**Files:**
- Create: `Wisp/Views/Loop/LoopRowView.swift`
- Create: `Wisp/Views/Loop/LoopsSectionView.swift`
- Create: `Wisp/Views/Loop/LoopDetailView.swift`
- Modify: `Wisp/Views/Dashboard/DashboardView.swift`

**Step 1: Create LoopRowView**

Create `Wisp/Views/Loop/LoopRowView.swift`:

```swift
import SwiftUI

struct LoopRowView: View {
    let loop: SpriteLoop

    var body: some View {
        HStack {
            Image(systemName: "circle.fill")
                .font(.system(size: 8))
                .foregroundStyle(statusColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(loop.prompt)
                    .font(.body)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(loop.spriteName)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("Every \(loop.interval.displayName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(loop.timeRemainingDisplay)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
    }

    private var statusColor: Color {
        switch loop.state {
        case .active: .green
        case .paused: .orange
        case .stopped: .gray
        }
    }
}

#Preview {
    List {
        LoopRowView(loop: SpriteLoop(
            spriteName: "my-sprite",
            workingDirectory: "/home/sprite/project",
            prompt: "Check PR #42 for new review comments and CI status",
            interval: .tenMinutes
        ))
    }
}
```

**Step 2: Create LoopDetailView**

Create `Wisp/Views/Loop/LoopDetailView.swift`:

```swift
import SwiftUI
import SwiftData

struct LoopDetailView: View {
    @Bindable var loop: SpriteLoop
    @Environment(LoopManager.self) private var loopManager
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        List {
            Section("Configuration") {
                LabeledContent("Sprite", value: loop.spriteName)
                LabeledContent("Interval", value: "Every \(loop.interval.displayName)")
                LabeledContent("Status", value: loop.state.rawValue.capitalized)
                LabeledContent("Expires", value: loop.timeRemainingDisplay)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Prompt")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(loop.prompt)
                        .font(.body)
                }
            }

            Section {
                if loop.state == .active {
                    Button("Pause Loop") {
                        loopManager.pause(loopId: loop.id, modelContext: modelContext)
                    }
                } else if loop.state == .paused {
                    Button("Resume Loop") {
                        loopManager.resume(loop: loop, modelContext: modelContext)
                    }
                }

                Button("Delete Loop", role: .destructive) {
                    loopManager.stop(loopId: loop.id, modelContext: modelContext)
                    modelContext.delete(loop)
                    try? modelContext.save()
                }
            }

            Section("Iterations (\(loop.iterations.count))") {
                if loop.iterations.isEmpty {
                    Text("No iterations yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(loop.iterations) { iteration in
                        IterationRowView(iteration: iteration)
                    }
                }
            }
        }
        .navigationTitle("Loop Details")
    }
}

struct IterationRowView: View {
    let iteration: LoopIteration
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                if let response = iteration.responseText {
                    Text(response)
                        .font(.body)
                        .textSelection(.enabled)
                } else if case .failed(let error) = iteration.status {
                    Text(error)
                        .font(.body)
                        .foregroundStyle(.red)
                }
            }
            .padding(.vertical, 4)
        } label: {
            HStack {
                Image(systemName: statusIcon)
                    .foregroundStyle(statusColor)
                    .font(.caption)

                Text(iteration.startedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.subheadline)

                Spacer()

                if let summary = iteration.notificationSummary {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(maxWidth: 150, alignment: .trailing)
                }
            }
        }
    }

    private var statusIcon: String {
        switch iteration.status {
        case .running: "arrow.clockwise"
        case .completed: "checkmark.circle"
        case .failed: "xmark.circle"
        case .skipped: "forward"
        }
    }

    private var statusColor: Color {
        switch iteration.status {
        case .running: .blue
        case .completed: .green
        case .failed: .red
        case .skipped: .gray
        }
    }
}

#Preview {
    NavigationStack {
        LoopDetailView(loop: SpriteLoop(
            spriteName: "my-sprite",
            workingDirectory: "/home/sprite/project",
            prompt: "Check PR #42 for new review comments and CI status",
            interval: .tenMinutes
        ))
        .environment(LoopManager())
    }
}
```

**Step 3: Add Loops section to DashboardView**

Modify `Wisp/Views/Dashboard/DashboardView.swift`. Add a `@Query` for active loops and a section in the List. The key changes:

Add imports and query at the top of the struct:

```swift
@Query(sort: \SpriteLoop.createdAt, order: .reverse) private var loops: [SpriteLoop]
@Environment(LoopManager.self) private var loopManager
```

Add a loops section inside the `List(selection:)` block, after the `ForEach(sortedSprites)` block (after line 88):

```swift
if !loops.isEmpty {
    Section("Loops") {
        ForEach(loops) { loop in
            NavigationLink(value: loop.id) {
                LoopRowView(loop: loop)
            }
            .swipeActions(edge: .trailing) {
                Button("Delete", role: .destructive) {
                    loopManager.stop(loopId: loop.id, modelContext: modelContext)
                    modelContext.delete(loop)
                    try? modelContext.save()
                }
            }
            .swipeActions(edge: .leading) {
                if loop.state == .active {
                    Button("Pause") {
                        loopManager.pause(loopId: loop.id, modelContext: modelContext)
                    }
                    .tint(.orange)
                } else if loop.state == .paused {
                    Button("Resume") {
                        loopManager.resume(loop: loop, modelContext: modelContext)
                    }
                    .tint(.green)
                }
            }
            .contextMenu {
                if loop.state == .active {
                    Button {
                        loopManager.pause(loopId: loop.id, modelContext: modelContext)
                    } label: {
                        Label("Pause", systemImage: "pause.circle")
                    }
                } else if loop.state == .paused {
                    Button {
                        loopManager.resume(loop: loop, modelContext: modelContext)
                    } label: {
                        Label("Resume", systemImage: "play.circle")
                    }
                }
                Button(role: .destructive) {
                    loopManager.stop(loopId: loop.id, modelContext: modelContext)
                    modelContext.delete(loop)
                    try? modelContext.save()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }
}
```

Add a `navigationDestination` for loop detail (near the existing detail column or navigation modifiers):

```swift
.navigationDestination(for: UUID.self) { loopId in
    if let loop = loops.first(where: { $0.id == loopId }) {
        LoopDetailView(loop: loop)
    }
}
```

You'll also need `@Environment(\.modelContext) private var modelContext` if not already present.

**Step 4: Build and verify**

Run: `xcodebuild -scheme Wisp -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

**Step 5: Commit**

```bash
git add Wisp/Views/Loop/ Wisp/Views/Dashboard/DashboardView.swift
git commit -m "Add loops section to dashboard with detail view"
```

---

## Task 7: App Integration (Environment Injection, Notification Permission, Loop Restoration)

**Files:**
- Modify: `Wisp/App/WispApp.swift`

**Step 1: Inject LoopManager and request notification permission**

Modify `Wisp/App/WispApp.swift`:

Add a `@State` property:

```swift
@State private var loopManager = LoopManager()
```

In the `body`, add `.environment(loopManager)` to `RootView()`:

```swift
RootView()
    .environment(apiClient)
    .environment(browserCoordinator)
    .environment(loopManager)
```

Add an `.onAppear` or `.task` to request notification permission and wire apiClient:

```swift
.task {
    loopManager.apiClient = apiClient
    await NotificationService.requestPermission()
}
```

For loop restoration on app launch, add after the permission request:

```swift
.onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
    // Restore loops could go here if needed
}
```

> **Note:** Loop restoration from SwiftData requires a `ModelContext`. The implementer should check how `RootView` provides a model context and call `loopManager.restoreLoops(modelContext:)` at the appropriate point — likely in `RootView` or `DashboardView`'s `.task` modifier where the model context is available.

**Step 2: Build and verify**

Run: `xcodebuild -scheme Wisp -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

**Step 3: Run full test suite**

Run: `xcodebuild -scheme Wisp -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test 2>&1 | tail -30`
Expected: All tests PASS

**Step 4: Commit**

```bash
git add Wisp/App/WispApp.swift
git commit -m "Inject LoopManager into environment and request notification permission"
```

---

## Task 8: Background Task Support (BGAppRefreshTask)

**Files:**
- Modify: `Wisp/Services/LoopManager.swift`
- Modify: `Wisp/App/WispApp.swift`
- Modify: `Wisp.xcodeproj` or target settings (add Background Modes capability)

**Step 1: Add Background Modes capability**

In Xcode project settings, add the "Background Modes" capability and enable "Background fetch". This adds the `UIBackgroundModes` key with `fetch` to `Info.plist`.

Alternatively, ensure the app's entitlements include background fetch.

**Step 2: Register BGTask identifier in WispApp**

Add to `WispApp.init()`:

```swift
BGTaskScheduler.shared.register(
    forTaskWithIdentifier: "com.wisp.app.loop-refresh",
    using: nil
) { task in
    guard let refreshTask = task as? BGAppRefreshTask else { return }
    Task { @MainActor in
        // This will be called by iOS when it grants background time
        // The LoopManager handles the actual execution
    }
}
```

**Step 3: Add background scheduling to LoopManager**

Add methods to `LoopManager.swift`:

```swift
import BackgroundTasks

// Add to LoopManager:

static let bgTaskIdentifier = "com.wisp.app.loop-refresh"

func scheduleBackgroundRefresh() {
    let request = BGAppRefreshTaskRequest(identifier: Self.bgTaskIdentifier)
    // Find the soonest next tick across all active loops
    let soonest = timers.keys.compactMap { loopId -> TimeInterval? in
        // Use the loop's interval as the earliest date
        return nil // Will be refined during implementation
    }.min() ?? 600

    request.earliestBeginDate = Date(timeIntervalSinceNow: soonest)

    do {
        try BGTaskScheduler.shared.submit(request)
    } catch {
        logger.error("Failed to schedule background refresh: \(error)")
    }
}

func handleBackgroundRefresh(task: BGAppRefreshTask, modelContext: ModelContext) {
    // Run one iteration for the most overdue loop
    task.expirationHandler = {
        task.setTaskCompleted(success: false)
    }

    Task {
        let activeRaw = LoopState.active.rawValue
        let descriptor = FetchDescriptor<SpriteLoop>(
            predicate: #Predicate { $0.stateRaw == activeRaw },
            sortBy: [SortDescriptor(\.lastRunAt)]
        )
        if let loop = try? modelContext.fetch(descriptor).first {
            await runIteration(loopId: loop.id, modelContext: modelContext)
        }

        // Schedule next refresh
        scheduleBackgroundRefresh()
        task.setTaskCompleted(success: true)
    }
}
```

**Step 4: Schedule on app background**

In `WispApp`, observe `scenePhase` changes:

```swift
@Environment(\.scenePhase) private var scenePhase

// In body, add:
.onChange(of: scenePhase) { _, newPhase in
    switch newPhase {
    case .background:
        loopManager.scheduleBackgroundRefresh()
    case .active:
        // Cancel BG tasks and restore foreground timers
        BGTaskScheduler.shared.cancelAllTaskRequests()
    default:
        break
    }
}
```

**Step 5: Build and verify**

Run: `xcodebuild -scheme Wisp -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

**Step 6: Commit**

```bash
git add Wisp/Services/LoopManager.swift Wisp/App/WispApp.swift
git commit -m "Add BGAppRefreshTask support for background loop execution"
```

---

## Task Summary

| Task | Description | Dependencies |
|------|-------------|--------------|
| 1 | SwiftData models (SpriteLoop, LoopIteration, enums) | None |
| 2 | NotificationService | None |
| 3 | LoopManager core (timers, register/pause/stop) | Task 1, 2 |
| 4 | CreateLoopSheet UI + long-press send | Task 1 |
| 5 | Loop execution engine (wire to SpritesAPIClient) | Task 3 |
| 6 | Dashboard loops section + detail view | Task 1, 3 |
| 7 | App integration (environment, permissions, restore) | Task 3, 6 |
| 8 | Background task support (BGAppRefreshTask) | Task 7 |

Tasks 1 and 2 can be done in parallel. Task 4 can be done in parallel with Task 3. Tasks 5-8 are sequential.
