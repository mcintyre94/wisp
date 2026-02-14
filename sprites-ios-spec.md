# Wisp — Product Spec

## Overview

A native iOS app for managing and interacting with [Fly.io Sprites](https://sprites.dev) — stateful sandbox environments backed by Firecracker VMs with persistent filesystems, checkpoint/restore, and HTTP access.

Wisp gives developers a chat-based interface to run Claude Code on remote Sprites from their phone: type a prompt, watch Claude work, manage checkpoints, browse files, and push to GitHub — all without a terminal emulator.

---

## Target API

**Base URL:** `https://api.sprites.dev`
**API Version:** `v0.0.1-rc30`
**Auth:** Bearer token (created at sprites.dev/account or via CLI `sprite org auth`)
**API Reference:** [sprites.dev/api](https://sprites.dev/api) · [Full docs](https://docs.sprites.dev/api/v001-rc30/)

The API is REST + WebSocket:
- REST for CRUD operations (sprites, checkpoints, files, network policy, services)
- WebSocket for exec (the primary interaction channel for Claude Code)

---

## Core Interaction Model

The key insight: Claude Code's `--print` mode (`-p`) outputs clean, structured JSON rather than terminal escape codes. Combined with Sprites' exec API, this means Wisp can offer a **chat interface** rather than a terminal emulator — which is exactly what phones are good at.

**The loop:**
1. User types a prompt in a chat input
2. Wisp execs `claude -p --verbose --output-format stream-json --dangerously-skip-permissions "the prompt"` on the Sprite via WebSocket
3. NDJSON events stream back — Wisp renders assistant text as chat bubbles, tool use as collapsible action cards
4. Wisp captures the `session_id` from the result event
5. User types another prompt — Wisp adds `--resume {session_id}` to maintain conversational context
6. Full continuity across messages, just like a messaging app

**The exec command pattern:**
```bash
# First message
claude -p --verbose --output-format stream-json --dangerously-skip-permissions "user's prompt"

# Follow-up messages (same session)
claude -p --verbose --output-format stream-json --dangerously-skip-permissions --resume SESSION_ID "next prompt"
```

**Why this works on Sprites:** Sprites run Claude Code in YOLO mode (`--dangerously-skip-permissions`) because the VM itself is the security boundary. No approve/reject flow means the interaction is purely: prompt → Claude works → result. Perfect for mobile.

**Stream event types Wisp needs to handle:**

| Event type | What it contains | How to render |
|------------|-----------------|---------------|
| `system` (init) | `session_id`, model, tools, cwd | Store session_id; show model in status bar |
| `assistant` (text) | Claude's conversational text | Chat bubble with markdown rendering |
| `assistant` (tool_use) | Tool name + input (e.g. `Bash` with command, `Write` with file path + content) | Collapsible action card: "Ran `ls -la`" or "Created `server.js`" |
| `user` (tool_result) | Tool output: stdout/stderr for Bash, file metadata for Read/Write | Expandable result inside the action card |
| `result` | `session_id`, `duration_ms`, `num_turns`, success/error | Conversation footer; persist session_id for resume |

**Validated flow** (tested on a live Sprite, Feb 2026):
- Auth via `CLAUDE_CODE_OAUTH_TOKEN` env var ✓
- Streaming NDJSON via `--verbose --output-format stream-json` ✓ (`--verbose` is required with `stream-json`)
- Tool execution (Write, Read, Bash) with structured event data ✓
- Session resume via `--resume SESSION_ID` with full context continuity ✓
- All via `sprite exec` — no terminal emulator needed ✓

---

## Core Features

### 1. Authentication & Onboarding

**Sprites Token**
- Manual token entry (paste from sprites.dev/account)
- Secure storage in iOS Keychain
- Support for multiple tokens — each token is scoped to a single org (the org slug is embedded in the token string, e.g. `my-org/1290577/...`), so users with multiple orgs store one token per org and switch between them
- Token validation on entry (call `GET /v1/sprites` and check for 200)

**Claude Code Token**
- User runs `claude setup-token` on their local machine (where they have a browser)
- This generates a long-lived OAuth token (`sk-ant-oat01-...`, ~1 year validity)
- User pastes it into Wisp; stored in Keychain
- Wisp injects it as `CLAUDE_CODE_OAUTH_TOKEN` env var on every `sprite exec` call
- Uses the user's existing Claude Pro/Max subscription — no separate API billing

**Session**
- Persist auth across app launches
- Show current org in nav header
- Allow switching between multiple saved tokens/orgs

**Onboarding flow:**
1. Enter Sprites API token
2. Enter Claude Code token (with instructions: "Run `claude setup-token` in your terminal and paste the result")
3. Optionally connect GitHub (OAuth device flow)

---

### 2. Sprites Dashboard (Home)

The primary screen — a list of all Sprites in the current organisation.

**Data source:** `GET /v1/sprites` (supports pagination via `continuation_token`)

**Each Sprite card shows:**
- Name
- Status badge: `running` (green), `warm` (amber), `cold` (blue)
- Sprite URL (tappable → opens in-app browser or copies)
- Created/updated timestamps
- URL auth mode (`public` / `sprite`)

**Actions from the list:**
- Pull-to-refresh
- Create new Sprite (sheet with name, URL auth setting, and optional GitHub repo to clone from)
- Swipe-to-delete with confirmation
- Tap → Sprite detail view
- Filter/search by name prefix

**Create Sprite:**
`POST /v1/sprites` with `{ "name": "...", "url_settings": { "auth": "sprite" | "public" } }`

Create sheet fields:
- Sprite name (required)
- URL auth setting (default: `sprite`)
- **Start from GitHub repo** (optional) — if GitHub is connected:
  - Search/browse your own repos, or paste any public `owner/repo`
  - After Sprite creation, Wisp execs `git clone https://.../{owner}/{repo}.git /home/sprite/{repo}` to pull the repo into the Sprite
  - The Sprite is immediately ready to work on that codebase

If GitHub is connected, Wisp also automatically configures git credentials on every new Sprite (writes `~/.git-credentials`, sets `user.name` and `user.email`). This means any Sprite can push to your repos without per-Sprite GitHub setup.

**Delete Sprite:**
`DELETE /v1/sprites/{name}` — destructive, requires confirmation dialog ("This will permanently delete all files, packages, and checkpoints. This cannot be undone.")

---

### 3. Sprite Detail View

A tabbed or segmented view for a single Sprite with these sections:

#### 3a. Overview Tab
- Full Sprite metadata (id, name, status, org, URL, timestamps)
- Quick action buttons: Open URL (Safari/in-app), Copy URL
- Update URL auth setting: `PUT /v1/sprites/{name}` with `url_settings`
- "Push to GitHub" quick action (if repo is linked) — prompts for commit message, execs commit+push

#### 3b. Chat Tab (Primary Feature)
The main interaction surface — a chat interface for Claude Code powered by `claude -p` over Sprites exec.

**Launch Screen**

When there's no active conversation, show a launch screen:

- **"Start coding"** — large primary button with text input. Submits the first prompt.
- Show the current working directory (`/home/sprite/project` or `/home/sprite/{repo-name}`)
- Optionally show recent sessions that can be resumed

**Chat View**

A scrolling conversation view, similar to a messaging app:

- **User messages** — right-aligned chat bubbles showing the prompt
- **Assistant text** — left-aligned chat bubbles with full markdown rendering (code blocks with syntax highlighting, bold, lists, etc.)
- **Tool use cards** — collapsible inline cards showing what Claude did:
  - `Bash` → "Ran `command`" with expandable stdout/stderr
  - `Write` → "Created `filepath`" with expandable file content preview
  - `Edit` → "Edited `filepath`" with diff/patch preview
  - `Read` → "Read `filepath`" with expandable content
  - `Glob`/`Grep` → "Searched files" with results
  - `WebFetch`/`WebSearch` → "Searched the web" with results
- **Text input** at the bottom with send button
- **Interrupt button** (replaces send while Claude is working) — kills the exec session immediately, no confirmation (same as Esc in interactive Claude Code). Shows a brief toast: *"Stopped after {N} turns"*. Work already done (files written, commands run) is preserved, and the conversation session remains resumable.

**Working Directory**

Wisp always works in a **project subdirectory**, never in `/home/sprite` itself. This keeps the home directory clean (dotfiles, config), makes `git init` natural, and gives Claude Code a focused project root with its own `CLAUDE.md`.

Convention:
- **New Sprite, no repo:** Wisp creates and `cd`s into `/home/sprite/project`
- **Cloned from GitHub:** `cd` into `/home/sprite/{repo-name}` (where `git clone` puts it)
- **Linked repo later:** Whatever directory the user specifies during linking

Wisp runs `mkdir -p /home/sprite/project` as part of Sprite setup (before the first chat message) if no project directory exists yet. The Chat tab shows the current working directory and allows users to change it if needed.

The exec command always `cd`s first:
```bash
cd /home/sprite/project && claude -p --verbose --output-format stream-json ...
```

**Session Management**

- Store `session_id` per Sprite in Wisp's local database
- Each Sprite has one active conversation at a time
- "New conversation" action to start fresh (new session_id)
- Previous conversations could be browsable in future phases

**Exec Lifecycle**

Each message is a separate `sprite exec` call. This is simpler than maintaining a persistent WebSocket:

- User sends prompt → Wisp opens WebSocket exec → `claude -p` runs → streams events → process exits → WebSocket closes
- Between messages, no active connection — the Sprite can sleep if idle long enough
- If a prompt triggers a long-running Claude task, the WebSocket stays open for the duration
- If the app backgrounds during execution: use `beginBackgroundTask` for ~30 seconds of continued listening. If Claude finishes in that window, fire a local notification: *"Claude is done on {sprite-name} — tap to see the result."*

**Background Notifications**

- **Phase 2:** Schedule a local notification when the app backgrounds mid-execution. If the exec completes within the ~30 second `beginBackgroundTask` window, notify immediately.
- **Phase 4:** Relay service that holds the WebSocket server-side and sends APNS push for long-running tasks.

#### 3c. Checkpoints Tab
Snapshot and rollback the full Sprite environment.

**Endpoints:**
- `POST /v1/sprites/{name}/checkpoints` — create checkpoint (with optional comment)
- `GET /v1/sprites/{name}/checkpoints` — list all checkpoints
- `GET /v1/sprites/{name}/checkpoints/{id}` — get checkpoint details
- `POST /v1/sprites/{name}/checkpoints/{id}/restore` — restore to checkpoint

**UI:**
- Timeline/list of checkpoints (newest first)
- Each shows: ID, comment/label, timestamp, size info
- "Create Checkpoint" button at top with optional label input
- Restore action on each checkpoint with confirmation ("This will restart your Sprite and restore all files to this point. Running processes will stop.")
- Visual indicator of which checkpoint is "current" (if applicable)
- Creation shows progress (typically ~300ms, but stream status)

#### 3d. GitHub Tab
Link a Sprite to a GitHub repository so Claude Code can commit and push.

**Authentication (global, configured once in Settings):**

Uses the GitHub OAuth device flow — designed for input-constrained devices:
1. Wisp requests a device code from GitHub (`POST https://github.com/login/device/code`)
2. Shows the user a short code and a link to github.com/login/device
3. User opens the link on any browser, enters the code, authorises
4. Wisp polls for the access token and stores it in Keychain
5. Token scopes needed: `repo` (read/write repos), `user` (read user info for defaults)

**Link Repository flow:**

If GitHub is connected, git credentials are already on the Sprite (auto-configured on create). Linking a repo just sets up the remote:

1. Tap "Link Repository" on GitHub tab
2. Choose: **Create new repo** (name, public/private) or **Link existing** (search your repos or enter `owner/repo`)
3. Enter Sprite directory path (default: `/home/sprite/{repo-name}`)
4. Wisp execs setup commands on the Sprite via the exec API:
   - `cd {directory} && git init && git remote add origin https://github.com/{owner}/{repo}.git`
   - If linking to an existing repo with content: `git pull origin main`
5. Done — Claude Code can `git add`, `commit`, `push` naturally.

Note: If the Sprite was created with "Start from GitHub repo," it's already linked — the GitHub tab shows the repo status immediately.

**Quick Push action:**

A "Push to GitHub" button on the Sprite detail overview (3a) for routine pushes without opening the chat:
- Tap → prompts for a commit message
- Execs: `cd {linked_dir} && git add -A && git commit -m "{message}" && git push origin main`
- Shows success/failure with a summary of what changed (files added/modified/deleted)

**UI:**
- Shows linked repo name, owner, branch, and last push time
- Link/unlink repository
- Quick view of git status (clean / uncommitted changes)
- Push and pull buttons
- Link to open repo on github.com

**Notes:**
- Git credentials are auto-provisioned on Sprite creation (if GitHub is connected) and persist across checkpoint/restore
- Multiple Sprites can link to the same repo — they're just separate clones
- Creating new repos requires GitHub API: `POST /user/repos` with the token
- The `gh` CLI is pre-installed on Sprites, so Claude Code may use that directly too — the stored credentials work either way
- For Sprites created before GitHub was connected, the GitHub tab offers a one-time "Set up git credentials" action

#### 3e. Web View Tab
See what the Sprite is serving.

Each Sprite has a URL like `https://{name}-{random}.sprites.app`.

- In-app WKWebView for viewing what the Sprite is serving on port 8080
- Auto-inject Bearer auth header for authenticated Sprite URLs
- Refresh, share, and "Open in Safari" actions
- Display connection status (Sprite may need to wake from cold — show spinner for up to ~1s)

#### 3f. Terminal Tab (Phase 3 — Advanced)
For power users and tasks where the chat interface isn't enough (debugging, running interactive tools, checking logs).

**Interactive Session (WebSocket — full TTY)**
`WSS wss://api.sprites.dev/v1/sprites/{name}/exec?cmd={shell}&tty=true&ttyRows={r}&ttyCols={c}`

WebSocket message protocol:
- Client sends: `{ "type": "stdin", "data": "base64..." }`
- Server sends: `{ "type": "stdout", "data": "base64..." }`, `{ "type": "stderr", "data": "base64..." }`, `{ "type": "exit", "code": N }`
- Client can send: `{ "type": "resize", "rows": N, "cols": N }`

Implementation notes:
- Embed a terminal emulator view (e.g. [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm))
- Send resize events when device rotates or terminal view resizes
- Support landscape mode for wider terminal
- Set TERM=xterm-256color

**Keyboard Accessory Bar**

A strip above the iOS keyboard with keys optimised for Claude Code / shell use:

```
[ Esc ] [ / ] [ ^C ] [ ↑ ] [ ↓ ] [ ← ] [ → ] [ Tab ]
```

**Session Lifecycle**

Wisp doesn't try to keep terminal sessions alive across app closures — the default is clean shutdown to save on Sprite billing:
- **Close terminal** → explicitly kill the session via `DELETE /v1/sprites/{name}/exec/{session_id}`
- **App backgrounded** → schedule a local notification after 10 minutes: *"Your Sprite is still running — tap to return or end the session."*
- **Optionally auto-kill** after a configurable timeout (default: 30 minutes)

#### 3g. Files Tab
Browse and manage the Sprite's filesystem.

**Endpoints:**
- `GET /v1/sprites/{name}/fs/list?path=/` — directory listing
- `GET /v1/sprites/{name}/fs/read?path=/file.txt` — read file contents
- `PUT /v1/sprites/{name}/fs/write` — write file (body = raw bytes, query params for path, mode, mkdir)
- `DELETE /v1/sprites/{name}/fs/delete?path=/file.txt` — delete
- `POST /v1/sprites/{name}/fs/rename` — rename/move (`{ "source", "dest" }`)
- `POST /v1/sprites/{name}/fs/copy` — copy
- `PUT /v1/sprites/{name}/fs/chmod` — change permissions
- `PUT /v1/sprites/{name}/fs/chown` — change owner

**UI:**
- Hierarchical file browser with back navigation (breadcrumb trail)
- File type icons (folder, code file, text, image, binary)
- Tap file → view contents (syntax-highlighted for code, image preview for images, hex view for binary)
- Long-press for context menu: rename, copy, delete, download, share
- "+" button to create new file or upload from device (iOS document picker / camera roll)
- Show file metadata: permissions (octal), size, modification time
- Pull-to-refresh current directory

#### 3h. Services Tab
Manage persistent background services.

**Endpoints:**
- `GET /v1/sprites/{name}/services` — list services
- `POST /v1/sprites/{name}/services` — create service
- `GET /v1/sprites/{name}/services/{id}` — get service details
- `POST /v1/sprites/{name}/services/{id}/start` — start
- `POST /v1/sprites/{name}/services/{id}/stop` — stop
- `GET /v1/sprites/{name}/services/{id}/logs` — service logs

**UI:**
- List of services with status (running/stopped)
- Start/stop toggle
- Tap service → log viewer (streaming, monospace, auto-scroll)
- Create service form

#### 3i. Network Policy Tab
Control outbound network access.

**Endpoints:**
- `GET /v1/sprites/{name}/policy` — get current policy
- `POST /v1/sprites/{name}/policy` — update policy

**UI:**
- Current policy display (allowed domains list)
- Add/remove domains
- Toggle presets: "Allow all", "LLM-friendly defaults", "Custom"
- Changes applied immediately via API

---

## Technical Architecture

### Networking Layer

```
SpritesAPIClient
├── auth: TokenStore (Keychain-backed, stores Sprites token + Claude Code OAuth token)
├── rest: URLSession (JSON REST calls)
├── websocket: URLSessionWebSocketTask (exec for claude -p, terminal)
└── config: base URL, timeout, org

GitHubClient
├── auth: OAuth device flow token (Keychain-backed)
├── rest: URLSession (GitHub API for repo creation, user info)
└── setup: exec commands via SpritesAPIClient to configure git on Sprite
```

Key design decisions:
- Use Swift's native `URLSession` for REST and WebSocket — no third-party dependencies
- All REST responses are JSON — use `Codable` models throughout
- Claude Code chat: WebSocket exec streams NDJSON — parse line by line, decode each as a typed event
- Handle Sprite wake-up latency gracefully (cold Sprites may take up to 1s for first request)
- Inject `CLAUDE_CODE_OAUTH_TOKEN` as env var on every claude-related exec call via `--env` flag

### Models

```swift
struct Sprite: Codable, Identifiable {
    let id: String
    let name: String
    let status: SpriteStatus  // "running" | "warm" | "cold"
    let url: String
    let urlSettings: URLSettings
    let organization: String
    let createdAt: Date
    let updatedAt: Date
}

enum SpriteStatus: String, Codable {
    case running, warm, cold
}

struct Checkpoint: Codable, Identifiable {
    let id: String
    let comment: String?
    let createdAt: Date
}

struct FileEntry: Codable {
    let name: String
    let path: String
    let isDirectory: Bool
    let size: Int64?
    let mode: String?
    let modifiedAt: Date?
}

struct NetworkPolicy: Codable {
    let allowedDomains: [String]
}

struct Service: Codable, Identifiable {
    let id: String
    let name: String
    let status: String  // "running" | "stopped"
    let command: String
}

struct GitHubLink: Codable {
    let owner: String
    let repo: String
    let directory: String   // path on Sprite filesystem
    let branch: String      // default: "main"
}
```

### Claude Code Stream Events

These model the NDJSON events from `claude -p --verbose --output-format stream-json`:

```swift
// Each line of NDJSON is one of these
enum ClaudeStreamEvent: Decodable {
    case system(SystemEvent)
    case assistant(AssistantEvent)
    case user(ToolResultEvent)
    case result(ResultEvent)
}

struct SystemEvent: Decodable {
    let sessionId: String
    let cwd: String
    let model: String
    let tools: [String]
    let claudeCodeVersion: String
}

struct AssistantEvent: Decodable {
    let sessionId: String
    let message: AssistantMessage
}

struct AssistantMessage: Decodable {
    let content: [ContentBlock]
    let model: String
}

enum ContentBlock: Decodable {
    case text(String)
    case toolUse(ToolUse)
}

struct ToolUse: Decodable {
    let id: String
    let name: String   // "Bash", "Write", "Read", "Edit", "Glob", "Grep", etc.
    let input: [String: AnyCodable]  // varies by tool
}

// Tool results carry structured data depending on the tool:
//
// Bash:
//   tool_use_result.stdout, .stderr, .interrupted
//
// Write:
//   tool_use_result.type ("create"), .filePath, .content
//
// Read:
//   tool_use_result.type ("text"), .file.filePath, .file.content,
//   .file.numLines, .file.startLine, .file.totalLines
//
// Edit:
//   tool_use_result.type ("edit"), .filePath, .structuredPatch

struct ResultEvent: Decodable {
    let sessionId: String
    let isError: Bool
    let durationMs: Int
    let numTurns: Int
    let result: String
}
```

### Chat View Architecture

```
ChatViewModel
├── spriteClient: SpritesAPIClient
├── spriteName: String
├── sessionId: String?           // nil for first message, set after init event
├── workingDirectory: String     // defaults to linked repo dir or /home/sprite/project
├── messages: [ChatMessage]      // rendered in the chat view
├── isStreaming: Bool             // true while exec is in progress
│
├── sendMessage(prompt: String)
│   → opens WebSocket exec
│   → builds claude -p command with --resume if sessionId exists
│   → parses NDJSON events line-by-line, appends to messages[]
│   → captures sessionId from init event
│   → closes WebSocket when process exits
│
├── interrupt()
│   → kills the exec session to stop Claude mid-generation
│
└── newConversation()
    → clears sessionId, optionally archives current messages
```

### App Architecture

- **SwiftUI** with the Observation framework (`@Observable` view models)
- **iOS 17+** minimum — enables modern SwiftUI features (Observable, refined NavigationStack, improved WebSocket APIs)
- **Navigation:** `NavigationStack` with `NavigationPath` for drill-down
- **State management:** View models per feature area, shared `SpritesAPIClient` singleton
- **Chat rendering:** Custom `LazyVStack` with message bubbles, tool use cards, markdown rendering
- **Markdown:** swift-markdown or a lightweight renderer for Claude's responses
- **Keychain:** Lightweight wrapper for token storage (Sprites + Claude Code + GitHub)
- **Error handling:** Map API errors to user-facing alerts; handle 401 (expired token), 404 (Sprite not found), 5xx (service issues)
- **No third-party networking deps** — URLSession handles everything

---

## Screen Map

```
Launch
 └─ Auth (if no tokens)
     ├─ Sprites Token Entry → Validate → Save to Keychain
     ├─ Claude Code Token Entry ("Run claude setup-token locally and paste")
     └─ GitHub Connect (optional, OAuth device flow)

Main (NavigationStack)
 └─ Sprites List (Dashboard)
     ├─ Create Sprite (sheet: name, URL auth, optional GitHub repo to clone)
     ├─ Sprite Detail
     │   ├─ Overview (status, URL, quick push)
     │   ├─ Chat (Claude Code via -p)  ← primary feature
     │   │   ├─ Launch / New Conversation
     │   │   └─ Conversation View (streaming)
     │   ├─ Checkpoints
     │   │   ├─ List
     │   │   └─ Create (sheet)
     │   ├─ GitHub
     │   │   ├─ Link Repository (sheet)
     │   │   └─ Status / Push / Pull
     │   ├─ Web View (Sprite URL)
     │   ├─ Terminal (Phase 3, advanced)
     │   ├─ Files
     │   │   ├─ Directory Browser
     │   │   ├─ File Viewer
     │   │   └─ Upload/Create (sheet)
     │   ├─ Services
     │   │   ├─ List
     │   │   ├─ Logs Viewer
     │   │   └─ Create (sheet)
     │   └─ Network Policy
     └─ Settings
         ├─ Manage Tokens/Orgs (Sprites + Claude Code)
         ├─ GitHub Account (OAuth device flow)
         ├─ Default working directory preference
         ├─ Claude model preference (sonnet/opus/haiku)
         ├─ Max turns limit (default: unlimited)
         └─ Theme / appearance
```

---

## API Endpoint Summary

| Feature | Method | Endpoint |
|---------|--------|----------|
| List sprites | GET | `/v1/sprites` |
| Create sprite | POST | `/v1/sprites` |
| Get sprite | GET | `/v1/sprites/{name}` |
| Update sprite | PUT | `/v1/sprites/{name}` |
| Delete sprite | DELETE | `/v1/sprites/{name}` |
| Exec (WebSocket) | WSS | `/v1/sprites/{name}/exec?cmd=...` |
| Exec (REST) | POST | `/v1/sprites/{name}/exec?cmd=...` |
| List exec sessions | GET | `/v1/sprites/{name}/exec` |
| Kill exec session | DELETE | `/v1/sprites/{name}/exec/{session_id}` |
| List checkpoints | GET | `/v1/sprites/{name}/checkpoints` |
| Create checkpoint | POST | `/v1/sprites/{name}/checkpoints` |
| Get checkpoint | GET | `/v1/sprites/{name}/checkpoints/{id}` |
| Restore checkpoint | POST | `/v1/sprites/{name}/checkpoints/{id}/restore` |
| Read file | GET | `/v1/sprites/{name}/fs/read?path=...` |
| Write file | PUT | `/v1/sprites/{name}/fs/write?path=...` |
| List directory | GET | `/v1/sprites/{name}/fs/list?path=...` |
| Delete file | DELETE | `/v1/sprites/{name}/fs/delete?path=...` |
| Rename/move | POST | `/v1/sprites/{name}/fs/rename` |
| Copy | POST | `/v1/sprites/{name}/fs/copy` |
| Chmod | PUT | `/v1/sprites/{name}/fs/chmod` |
| Chown | PUT | `/v1/sprites/{name}/fs/chown` |
| Watch filesystem | WSS | `/v1/sprites/{name}/fs/watch` |
| Get network policy | GET | `/v1/sprites/{name}/policy` |
| Set network policy | POST | `/v1/sprites/{name}/policy` |
| TCP proxy | WSS | `/v1/sprites/{name}/proxy?port=...` |
| List services | GET | `/v1/sprites/{name}/services` |
| Create service | POST | `/v1/sprites/{name}/services` |
| Get service | GET | `/v1/sprites/{name}/services/{id}` |
| Start service | POST | `/v1/sprites/{name}/services/{id}/start` |
| Stop service | POST | `/v1/sprites/{name}/services/{id}/stop` |
| Service logs | GET | `/v1/sprites/{name}/services/{id}/logs` |

---

## Implementation Phases

### Phase 1 — Core (MVP)
- Token auth (Sprites + Claude Code) + Keychain storage
- Sprites list with create/delete
- Sprite detail overview
- **Chat interface** — the core feature:
  - `claude -p` via WebSocket exec with streaming NDJSON
  - Render assistant text, tool use cards (Bash, Write, Read, Edit)
  - Session continuity via `--resume`
  - Interrupt (kill exec)
- Checkpoint list, create, restore

### Phase 2 — Integration
- GitHub integration (OAuth device flow, link repo, push/pull, clone on create)
- File browser with read/view
- Sprite web view (WKWebView with auth)
- Background reply notification (30-second `beginBackgroundTask` window)
- Settings (model preference, max turns, working directory)

### Phase 3 — Full Feature
- Interactive terminal (SwiftTerm, keyboard accessory bar)
- File write/upload/delete/rename
- Services management + log viewer
- Network policy editor

### Phase 4 — Polish
- **Reply notification relay service** — server-side WebSocket-to-APNS bridge for long-running Claude tasks
- Configurable terminal background session timeout
- Widgets (Sprite status on home screen)
- Shortcuts/Siri integration ("Create a checkpoint on my-sprite")
- iPad support with split view (list + detail side-by-side)
- Conversation history browser (past sessions per Sprite)
- Haptic feedback on checkpoint create/restore
- Accessibility audit

---

## Key Technical Risks & Considerations

1. **NDJSON parsing reliability** — The chat UI depends entirely on correctly parsing the stream-json output from Claude Code. Each line is a complete JSON object, but we need to handle partial lines (if the WebSocket delivers data mid-line), malformed events, and unexpected event types gracefully.

2. **Accidental billing** — If Wisp crashes or the phone dies mid-exec, the `claude -p` process exits when the WebSocket drops, so the Sprite should naturally go idle. But we should verify this behaviour and add a check for orphaned exec sessions on app launch.

3. **Claude Code `--resume` reliability** — Sessions are stored at `~/.claude/sessions/` on the Sprite filesystem. They persist across Sprite sleep/wake and checkpoint/restore. If a session file gets corrupted or the conversation exceeds the context window, Wisp should handle the failure gracefully and offer to start a new conversation.

4. **Cold start latency** — Sprites can be cold and take ~1s to wake. The first exec call on a cold Sprite will feel slower. Show appropriate loading states ("Waking Sprite..." → "Starting Claude..." → streaming).

5. **Large file handling** — The filesystem API returns raw bytes for file reads. Need sensible limits for in-app viewing (e.g. cap at 1MB for text preview, offer download for larger files).

6. **Auth token scope** — Sprites tokens are org-scoped. Claude Code OAuth tokens are user-scoped. Users need to understand they're managing two separate auth credentials. The onboarding flow should make this clear.

7. **No official Swift SDK** — There are Go, JS, Python, and Elixir SDKs for Sprites but no Swift. The REST API is clean enough to wrap directly with URLSession + Codable. The Claude Code NDJSON stream format is well-documented by the test results above.

8. **Claude Code version drift** — The `stream-json` output format and available flags may change across Claude Code versions. The `init` event includes `claude_code_version`, so Wisp could detect incompatible versions and warn the user.
