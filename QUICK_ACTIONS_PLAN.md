# Quick Actions Feature Plan

## Overview

Quick Actions is a lightweight interaction layer that sits alongside the main chat, grouping two features: **Side Chat** (ask Claude a question) and **Bash** (run a shell command). Both are ephemeral, single-shot, and don't interrupt the main chat session.

Replaces and supersedes the current side chat implementation on this branch.

---

## Entry Points

### 1. Sprite-level (context menu)
- Long-press / right-click on a Sprite in the dashboard or detail view
- No chat context — just the Sprite and its default working directory (`/home/sprite/project`)
- Service prefix: `wisp-quick-{UUID}` (separate from main chat services)

### 2. Chat-level (toolbar button)
- Toolbar button in the Chat view navigation bar
- Has full chat context: session ID, working directory (may be a worktree path)
- Same service prefix: `wisp-quick-{UUID}`

---

## Tabs

### Side Chat

**From Sprite (no session):**
```
claude -p --output-format stream-json \
  --disallowedTools "Bash,Write,Edit,MultiEdit,WebSearch,WebFetch" \
  --model MODEL \
  --max-turns 3 \
  'QUESTION'
```
- Read, Glob, Grep tools available — useful for asking about files without a full chat
- Fresh session, no prior context

**From Chat (with session):**
- Same command, adds `--resume SESSION_ID`
- Side chat Q&A is appended to main session history — benign, doesn't affect the current stream, and gives Claude useful context on future resumes

**Why `--disallowedTools` instead of `--tools ""`:**
Allowing read-only tools (Read, Glob, Grep) makes the feature meaningfully more useful, especially from the Sprite entry point where there's no prior session context. `--max-turns 3` bounds latency.

**UI:**
- Streaming markdown response (`.wisp` theme)
- `ThinkingShimmerView` while waiting for first tokens
- Single input bar, keyboard auto-focused on open
- Multiple questions supported per sheet session (each resumes same session ID)

---

### Bash

**From Sprite and Chat:**
- Runs command via exec on the Sprite
- Shows stdout + stderr in a terminal-styled output area (monospace, dark background)

**From Chat only:**
- "Insert into chat" button appears after command completes
- Formats output as ` $ command\n{output} ` in a code block, prepends to chat input field, dismisses sheet
- User adds context and sends normally

**Keyboard:**
- `.keyboardType(.asciiCapable)` — no emoji, cleaner for shell input
- `.autocorrectionDisabled()` + `.textInputAutocapitalization(.never)`
- Custom keyboard accessory bar with commonly painful-to-type characters: `` / - | > ~ ` $ & * . ``

**UI:**
- Monospace font on both input and output
- Dark background output area (terminal aesthetic)
- Streaming output as the command runs (if using service exec)

---

## Architecture

### New files
```
Wisp/
├── ViewModels/
│   ├── QuickActionsViewModel.swift   # Owns context (sprite, session, workingDir), coordinates tabs
│   └── BashQuickViewModel.swift      # Exec, output collection, "insert into chat" callback
└── Views/
    └── QuickActions/
        ├── QuickActionsView.swift    # Tab container sheet (Side Chat | Bash)
        ├── SideChatView.swift        # Refactored from current SideChatView
        └── BashQuickView.swift       # Bash tab UI, keyboard accessory bar
```

### Modified files
- `ChatView.swift` — swap `onSideChat` → `onQuickActions` toolbar button; present `QuickActionsView`
- `ChatInputBar.swift` — remove `onSideChat`, add `onQuickActions` (or remove entirely — toolbar button may be sufficient)
- `SpriteDetailView.swift` / dashboard — add Quick Actions to Sprite context menu
- `SideChatViewModel.swift` — update `--tools ""` → `--disallowedTools ...`, add `--max-turns 3`

### Removed
- `ChatInputBar.onSideChat` (replaced by toolbar button)
- Current `SideChatView` and its sheet wiring in `ChatView` (replaced by `QuickActionsView`)

---

## Service Cleanup
- Both tabs use `wisp-quick-{UUID}` service names
- Services deleted on completion or sheet dismiss (cancel in-flight tasks)
- Main chat services (`wisp-claude-{UUID}`) are unaffected

---

## Open Questions

1. **Bash exec mechanism** — `runExec()` (WebSocket, simpler, full output on completion) vs `streamService()` (streaming output as it runs). Streaming feels better UX-wise for longer commands; `runExec()` is simpler. Worth deciding before building.

2. **Bash command history** — remember recent commands within a session? Nice-to-have, skip for MVP.

3. **Tab default** — should the sheet remember which tab was last open, or always default to Side Chat?

4. **Side chat from Sprite with no Claude token** — show an error state or hide the side chat tab entirely?
