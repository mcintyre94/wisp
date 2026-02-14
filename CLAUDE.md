# Wisp

A native iOS app for managing and interacting with [Fly.io Sprites](https://sprites.dev) — stateful sandbox VMs with persistent filesystems, checkpoint/restore, and HTTP access. Wisp provides a chat-based interface to run Claude Code on remote Sprites from your phone.

## Tech Stack

- **Language:** Swift 6
- **UI:** SwiftUI, iOS 17+ minimum
- **State:** `@Observable` view models (Observation framework)
- **Navigation:** `NavigationStack` with `NavigationPath`
- **Persistence:** SwiftData for local state (sessions, linked repos, preferences)
- **Secrets:** iOS Keychain for tokens (Sprites API, Claude Code OAuth, GitHub)
- **Networking:** `URLSession` for REST, `URLSessionWebSocketTask` for WebSocket — no third-party networking dependencies
- **Markdown:** MarkdownUI (SPM) for rendering Claude responses with syntax highlighting
- **JSON:** Custom `JSONValue` enum for arbitrary JSON decoding (no AnyCodable dependency)
- **No third-party dependencies** except MarkdownUI (and SwiftTerm in Phase 3)

## Architecture

```
Wisp/
├── App/                    # App entry point, root navigation
├── Models/                 # SwiftData models + Codable API types
├── Services/               # API clients, Keychain, networking
│   ├── SpritesAPIClient    # REST + WebSocket for Sprites API
│   ├── GitHubClient        # GitHub OAuth device flow + API
│   ├── KeychainService     # Token storage wrapper
│   └── ClaudeStreamParser  # NDJSON binary stream parser
├── ViewModels/             # @Observable view models per feature
├── Views/                  # SwiftUI views organised by feature
│   ├── Auth/
│   ├── Dashboard/
│   ├── SpriteDetail/
│   │   ├── Overview/
│   │   ├── Chat/
│   │   └── Checkpoints/
│   └── Settings/
└── Utilities/              # Extensions, helpers, JSONValue
```

### Patterns

- One `@Observable` view model per feature screen
- Shared `SpritesAPIClient` singleton injected via SwiftUI environment
- View models own async tasks; views are purely declarative
- Use Swift concurrency (`async/await`, `AsyncThrowingStream`) throughout — no Combine
- Errors surfaced as user-facing alerts via a shared error handling pattern

## Sprites API

- **Base URL:** `https://api.sprites.dev`
- **Auth:** `Authorization: Bearer {sprites_token}` header on all requests
- **REST:** JSON request/response via `URLSession`
- **WebSocket exec:** `wss://api.sprites.dev/v1/sprites/{name}/exec?cmd=...&env=...`
  - `cmd` and `env` are repeatable query params
  - Non-TTY mode uses **binary protocol**: frames prefixed with stream ID byte (0=stdin, 1=stdout, 2=stderr, 3=exit, 4=stdin_eof)
  - Claude Code NDJSON arrives as raw bytes on stdout (stream ID 1); parse line-by-line

### Claude Code exec pattern

```bash
# First message — cd into project dir first
cd /home/sprite/project && claude -p --verbose --output-format stream-json --dangerously-skip-permissions "prompt"

# Follow-up messages — resume session
cd /home/sprite/project && claude -p --verbose --output-format stream-json --dangerously-skip-permissions --resume SESSION_ID "prompt"
```

Environment variables passed via `?env=CLAUDE_CODE_OAUTH_TOKEN=sk-ant-oat01-...`

### NDJSON stream events

Each stdout line is a JSON object with a `type` field:
- `system` — contains `session_id`, model, tools, cwd. Store session_id for `--resume`.
- `assistant` — contains `message.content[]` which is either text blocks or tool_use blocks
- `user` — tool results (stdout/stderr for Bash, file content for Read/Write, etc.)
- `result` — final event with `session_id`, `duration_ms`, `num_turns`, success/error

## Current Phase: Phase 1 (MVP)

Phase 1 scope — build only these features:
- Token auth (Sprites + Claude Code) with Keychain storage
- Sprites list (dashboard) with create/delete
- Sprite detail overview (metadata, status, URL)
- **Chat interface** (core feature):
  - `claude -p` via WebSocket exec with streaming NDJSON
  - Render assistant text as chat bubbles with markdown
  - Render tool use as collapsible action cards (Bash, Write, Read, Edit, Glob, Grep)
  - Session continuity via `--resume`
  - Interrupt (kill exec session)
- Checkpoint list, create, restore

**Not in Phase 1:** GitHub integration, file browser, web view, terminal, services, network policy, settings screen, background notifications.

## Conventions

- Use SF Symbols for icons throughout
- System colors and standard iOS chrome — no custom design system
- Sprite status colors: running = green, warm = amber/orange, cold = blue
- Chat bubbles: user messages right-aligned, assistant messages left-aligned
- Tool use cards are collapsible/expandable inline elements between chat bubbles
- Show loading states for Sprite wake-up ("Waking Sprite..." for cold starts, ~1s)
- Destructive actions (delete Sprite, restore checkpoint) always require confirmation dialogs
- Tokens are org-scoped; org slug is embedded in the token string (e.g. `my-org/1290577/...`)
- Working directory convention: `/home/sprite/project` for new Sprites, `/home/sprite/{repo}` for cloned repos
- Run `mkdir -p /home/sprite/project` on first chat message if no project dir exists

## Common Commands

```bash
# Build the project
xcodebuild -scheme Wisp -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16' build

# Run tests
xcodebuild -scheme Wisp -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16' test
```
