# Loop Feature Design

Client-side recurring prompt execution for babysitting PRs and collaborator interactions.

## Overview

Loops let users run a Claude prompt on a sprite at regular intervals, with results delivered as local notifications and stored as browsable chat transcripts. Created from within a chat (inheriting sprite + working directory), managed from the dashboard.

## Data Model

### Loop (SwiftData)

| Field | Type | Notes |
|-------|------|-------|
| id | UUID | |
| spriteName | String | Target sprite |
| workingDirectory | String | cd target before Claude exec |
| prompt | String | User's prompt text |
| interval | TimeInterval | 300, 600, 900, 1800, or 3600 |
| state | LoopState | .active, .paused, .stopped |
| createdAt | Date | |
| expiresAt | Date | createdAt + selected duration |
| lastRunAt | Date? | When last iteration completed |
| iterations | [LoopIteration] | Reverse-chronological results |

### LoopIteration (SwiftData)

| Field | Type | Notes |
|-------|------|-------|
| id | UUID | |
| startedAt | Date | |
| completedAt | Date? | |
| messages | [ChatMessage] | Reuses existing model (prompt + response) |
| status | IterationStatus | .running, .completed, .failed(String), .skipped |
| notificationSummary | String? | First ~120 chars of assistant text |

### Key decisions

- No Claude `session_id` carried across iterations. Each is a fresh `claude -p` call (no `--resume`). Stateless, avoids session corruption across long intervals.
- Duration presets: 1 day, 3 days, 1 week, 1 month. Default: 1 week.
- Loop expires automatically at `expiresAt`. Moves to `.stopped`, posts final notification.

## Lifecycle

### Creation

1. User long-presses Send button in chat
2. Sheet appears with:
   - Prompt text (pre-filled from chat input, editable)
   - "Check every:" segmented control -- 5m, 10m, 15m, 30m, 1h
   - "Run for:" segmented control -- 1 day, 3 days, 1 week, 1 month
   - "Start Loop" button
   - Sprite name shown as context label
3. Loop saved to SwiftData, chat input cleared, first iteration runs immediately
4. Confirmation toast: "Loop started -- checking every {interval}"

### Foreground execution

- `LoopManager` singleton (injected via SwiftUI environment) holds a `Timer` per active loop
- On tick: check sprite status -> wake if cold -> exec `claude -p` via WebSocket -> parse NDJSON -> store `LoopIteration` -> fire local notification
- Reuses `SpritesAPIClient` (same WebSocket exec path as chat)
- If previous iteration still running when next tick fires, skip

### Background execution

- On app backgrounding, `LoopManager` registers `BGAppRefreshTask` for each active loop
- iOS calls back at its discretion (best-effort timing, may be hours between runs)
- On callback: run one iteration, schedule next `BGAppRefreshTask`, post local notification
- On app foregrounding: cancel BGTasks, resume in-app timers

### Sprite waking

- Always wake the sprite if cold/warm. Each iteration is self-contained.
- Cold start adds ~30s+ latency; acceptable for a background monitoring task.

### Expiry

- Loop stops automatically when `Date.now >= expiresAt`
- Final notification: "Loop ended: {prompt summary}"
- State moves to `.stopped`

## UI Components

### 1. Chat: Long-press Send sheet

- Prompt text field (pre-filled, editable)
- "Check every:" segmented -- 5m | 10m | 15m | 30m | 1h
- "Run for:" segmented -- 1 day | 3 days | 1 week | 1 month
- "Start Loop" button
- Context label showing sprite name

### 2. Dashboard: Loops section

- Section in dashboard list below sprites
- Each row: prompt (truncated), sprite name, interval, time remaining ("Ends in 3 days"), status dot (green=active, yellow=paused, gray=stopped/expired)
- Swipe actions: Pause/Resume, Delete
- Context menu: same actions (for Mac accessibility)
- Tap -> Loop detail view

### 3. Loop Detail view

- Header: full prompt text, sprite name, interval, status, expires/ended date
- Pause/Resume and Delete buttons
- Scrollable list of iterations (reverse chronological)
- Each iteration expandable: mini chat transcript using existing chat bubble components
- Failed iterations show error message

### 4. Local notifications

- Posted after each completed iteration
- Title: "Loop: {sprite name}"
- Body: first ~120 chars of assistant response text
- Tap opens loop detail view scrolled to that iteration
- Requires requesting notification permission (UNUserNotificationCenter)

## Technical Requirements

### New files

- `Wisp/Models/Loop.swift` -- SwiftData models (Loop, LoopIteration, LoopState, IterationStatus)
- `Wisp/Services/LoopManager.swift` -- Singleton managing timers, BGTasks, iteration execution
- `Wisp/Services/NotificationService.swift` -- UNUserNotificationCenter wrapper
- `Wisp/Views/Dashboard/LoopsSectionView.swift` -- Dashboard loops list
- `Wisp/Views/Loop/LoopDetailView.swift` -- Loop detail with iteration history
- `Wisp/Views/Loop/CreateLoopSheet.swift` -- Long-press send sheet
- `Wisp/Views/Loop/LoopRowView.swift` -- Dashboard row component

### Modified files

- `ChatView.swift` -- Add long-press gesture to send button
- `DashboardView.swift` -- Add loops section
- `WispApp.swift` -- Register BGTask identifiers, inject LoopManager, request notification permissions
- `Info.plist` -- Add `BGTaskSchedulerPermittedIdentifiers`
- Project entitlements -- Background modes: `fetch`

### Dependencies

- No new dependencies. Uses framework APIs: `BackgroundTasks`, `UserNotifications`

## Out of scope

- Push notifications (APNs infrastructure)
- Loop creation from dashboard (always created from chat context)
- Custom intervals beyond presets
- Session continuity across iterations (--resume)
- Attachments on loop prompts
