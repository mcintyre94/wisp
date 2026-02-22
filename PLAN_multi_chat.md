# Plan: Multiple Chats Per Sprite

## Overview

Each chat is an independent Claude Code session backed by a unique named sprite service. Users can create new chats and switch between them within the Chat tab of a sprite. Only the active chat streams; inactive chats are dormant until selected.

## UI Design

**Chat switcher** lives in the navigation bar as a tappable title/chevron that presents a sheet listing chats. A `+` toolbar button creates a new chat.

```
┌─────────────────────────────────────┐
│  < Back   Chat 2 ˅         [+]  ⓘ  │
│─────────────────────────────────────│
│ [Chat 1]  last message preview      │
│ [Chat 2 ●] last message preview    │  ← ● = active/streaming
│ [Chat 3]  last message preview      │
│ [+ New Chat]                        │
└─────────────────────────────────────┘
```

- Nav bar title shows current chat name + chevron (e.g. "Chat 2 ˅")
- Tapping title presents a sheet with a list of chats + delete swipe actions
- Each row shows chat name and last message preview
- `+` toolbar button creates a new chat (always available, not disabled during streaming)
- Chats have an optional user-provided name; fallback display name is "Chat 1", "Chat 2", etc.
- Long-press or swipe on a chat row in the switcher offers a "Rename" action
- Deleting a chat stops its service and removes its persisted state

## Data Model Changes

### New: `SpriteChat` SwiftData model

Replace `SpriteSession` (which was 1-per-sprite) with `SpriteChat` (many-per-sprite):

```swift
@Model
final class SpriteChat {
    var id: UUID                        // stable identity
    var spriteName: String              // which sprite this belongs to
    var chatNumber: Int                 // assigned at creation, never reused
    var customName: String?             // optional user-provided name
    var currentServiceName: String?     // last-used service name; nil until first send
    var claudeSessionId: String?        // for --resume
    var workingDirectory: String
    var createdAt: Date
    var lastUsed: Date
    var messagesData: Data?
    var draftInputText: String?

    // Display name: customName if set, otherwise "Chat \(chatNumber)"
    var displayName: String { customName ?? "Chat \(chatNumber)" }
}
```

- `SpriteSession` is replaced by `SpriteChat`
- Migration: on first launch, convert existing `SpriteSession` records to `SpriteChat` with `chatNumber = 1`, `currentServiceName = nil`, copying over other fields
- **Service names are random, not deterministic.** `ChatViewModel` already generates `"claude-\(UUID().uuidString.prefix(8).lowercased())"` on each `executeClaudeCommand` call. `currentServiceName` in `SpriteChat` tracks whatever name was last used, so reconnect logic can find the running service after a chat switch.

### `ChatViewModel` changes

- Takes a `SpriteChat` (or just its `id`) instead of bare `spriteName`
- Initialises `serviceName` from `chat.currentServiceName` if present, otherwise generates a fresh random name
- Whenever `serviceName` is updated inside `executeClaudeCommand`, write the new value back to `SpriteChat.currentServiceName` and persist
- `sessionId` and `workingDirectory` loaded from/saved to `SpriteChat`

## New: `SpriteChatManager` (or integrated into `SpriteDetailViewModel`)

A new `@Observable` class owned by `SpriteDetailView` that manages the list of chats for a sprite:

```swift
@Observable
@MainActor
final class SpriteChatManager {
    let spriteName: String
    var chats: [SpriteChat] = []
    var activeChatId: UUID?

    // Derived
    var activeChat: SpriteChat? { chats.first { $0.id == activeChatId } }

    func loadChats(modelContext: ModelContext)
    func createChat(modelContext: ModelContext) -> SpriteChat
    func deleteChat(_ chat: SpriteChat, apiClient: SpritesAPIClient, modelContext: ModelContext) async
    func selectChat(_ chat: SpriteChat)
}
```

## `SpriteDetailView` changes

```swift
struct SpriteDetailView: View {
    @State private var chatManager: SpriteChatManager
    @State private var chatViewModel: ChatViewModel?      // nil until chats loaded
    @State private var checkpointsViewModel: CheckpointsViewModel
    @State private var showChatSwitcher = false

    // chatViewModel is recreated whenever activeChatId changes
}
```

- `chatManager` owns the list; `chatViewModel` is instantiated for whichever chat is active
- Switching chats: interrupt active stream → swap `chatViewModel` → `loadSession` on new one
- Nav bar title button: `Button("\(activeChat.name) ˅") { showChatSwitcher = true }`

## New View: `ChatSwitcherSheet`

```swift
struct ChatSwitcherSheet: View {
    @Binding var isPresented: Bool
    let chatManager: SpriteChatManager
    let apiClient: SpritesAPIClient
    let modelContext: ModelContext

    var body: some View {
        NavigationStack {
            List {
                ForEach(chatManager.chats) { chat in
                    ChatSwitcherRow(chat: chat, isActive: chat.id == chatManager.activeChatId)
                        .onTapGesture { chatManager.selectChat(chat); isPresented = false }
                        .swipeActions { Button("Delete", role: .destructive) { ... } }
                }
                Button("New Chat") { chatManager.createChat(...); isPresented = false }
            }
            .navigationTitle("Chats")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { isPresented = false } } }
        }
    }
}
```

## `ChatViewModel` switching logic

When the user selects a different chat:
1. Call `activeViewModel.interrupt()` on the current one (cancels the local stream task — note: `interrupt()` no longer takes `apiClient`; it just cancels the task and leaves the service running on the sprite)
2. Persist current draft
3. Instantiate new `ChatViewModel(chat: newChat)`
4. Call `loadSession` on it (loads persisted messages + draft)
5. Update `SpriteDetailView`'s `chatViewModel` binding

The inactive chat's service keeps running on the sprite. When re-selected, the `resumeAfterBackground` path reconnects via `reconnectToServiceLogs`. Note that this now **reuses the existing last assistant message** (clears its content and replays the full log into it) rather than appending a new message — which avoids duplicates on reconnect.

## Files to Create/Modify

| File | Change |
|---|---|
| `Models/Local/SpriteChat.swift` | **New** — SwiftData model replacing SpriteSession |
| `Models/Local/SpriteSession.swift` | **Remove** (or keep temporarily during migration) |
| `ViewModels/SpriteChatManager.swift` | **New** — manages chat list for one sprite |
| `ViewModels/ChatViewModel.swift` | Accept `SpriteChat` instead of bare spriteName; dynamic serviceName |
| `Views/SpriteDetail/SpriteDetailView.swift` | Add `chatManager`, wire up switcher sheet, update nav bar title |
| `Views/SpriteDetail/Chat/ChatSwitcherSheet.swift` | **New** — list + switch + delete chats |
| `Views/SpriteDetail/Chat/ChatSwitcherRow.swift` | **New** — single row in switcher list |
| `WispApp.swift` or schema container | Update SwiftData schema to include `SpriteChat`, remove `SpriteSession` |
| `WispTests/` | Update existing tests; add tests for `SpriteChatManager` |

## Migration

On first launch after update:
- Fetch all existing `SpriteSession` records
- For each, create a `SpriteChat` with `chatNumber=1`, `currentServiceName=nil` (the service name will be regenerated on the next send), copying over `claudeSessionId`, `workingDirectory`, `messagesData`, `draftInputText`
- Delete the `SpriteSession` records
- Can be a lightweight `ModelMigrationPlan` or handled at app startup
- `WispTests/ChatViewModelTests.swift` and `WispTests/ChatViewModelHelpersTests.swift` (added on `main`) currently include `SpriteSession` in the test `ModelContainer` schema — update these to use `SpriteChat` once the model is replaced

## Decisions

1. **Chat naming:** Auto-numbered fallback ("Chat 1", "Chat 2"), with optional user-provided custom name via rename action.
2. **Inactive service behavior:** Leave service running; reconnect using existing `resumeAfterBackground` logic on switch.
3. **Max chats per sprite:** Unbounded.
