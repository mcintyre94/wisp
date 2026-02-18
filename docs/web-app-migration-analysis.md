# Wisp: Web App Migration Analysis

## Current State

Wisp is a native iOS app (~3,700 lines of production Swift across 35 files) with one third-party dependency (MarkdownUI). It implements a chat interface for running Claude Code on remote Sprites via WebSocket exec with binary-framed NDJSON streaming. The app has session persistence (SwiftData), secure token storage (Keychain), and resilient reconnection logic (reattach + scrollback replay).

---

## Benefits of Rebuilding as a Web App

### 1. Cross-Platform Reach

The most significant benefit. A web app runs on iOS, Android, desktop (Mac, Windows, Linux), and tablets — all from a single codebase. This eliminates the need to build separate native apps for each platform. Wisp's core value (a chat UI for Claude Code on Sprites) doesn't require platform-specific hardware access, making it a strong candidate for the web.

### 2. No App Store Friction

- No App Store review delays or rejections
- No TestFlight distribution needed for beta users
- Deploy updates instantly — users always get the latest version
- No minimum iOS version constraints (currently iOS 17+)
- No Apple Developer Program membership required ($99/year)

### 3. Easier Distribution and Onboarding

Users can access Wisp via URL with zero installation. This is particularly valuable for a developer tool — the target audience is already browser-native. Share a link to start using it immediately.

### 4. Desktop-First Experience

Wisp is a developer tool for managing Claude Code sessions. Many users will want this on their desktop, not just their phone. A web app naturally provides a desktop layout with more screen real estate for:
- Side-by-side sprite management and chat
- Wider code blocks and tool output cards
- Keyboard shortcuts for power users
- Multi-window/multi-tab workflows

### 5. Simpler Development Toolchain

- No Xcode dependency (macOS-only, large, slow builds)
- Broader pool of contributors (web developers >> iOS developers)
- Faster iteration cycle (hot reload vs. Xcode build/deploy)
- Easier CI/CD (no simulator provisioning, no code signing)
- Better debugging tools (browser DevTools, network inspector)

### 6. Manageable Codebase Size

At ~3,700 lines of production code with a clean MVVM architecture, this is a tractable rewrite. The app has a well-defined feature set (auth, dashboard, chat, checkpoints) that maps cleanly to web equivalents. This isn't a sprawling app where rewrite risk is high.

### 7. Shared Auth with Sprites Web UI

If Sprites already has a web dashboard, a web-based Wisp could share authentication flows and potentially integrate directly, reducing friction.

---

## Tradeoffs and Costs

### 1. WebSocket Binary Protocol Handling

**Risk: Low-Medium**

The most technically complex part of Wisp is the binary WebSocket protocol (stream ID byte prefix) and NDJSON parsing. The browser WebSocket API handles binary frames via `ArrayBuffer`/`Uint8Array`, so the binary protocol is portable. The NDJSON parser is only 45 lines of Swift — straightforward to reimplement. The main gap is that browser WebSocket APIs offer less control over connection lifecycle than `URLSessionWebSocketTask` (no background execution, no OS-level keep-alive).

### 2. Reattach/Reconnection Logic

**Risk: Medium**

The app's resilience model (persist exec session ID, reattach on disconnect, replay scrollback, merge messages) is sophisticated — 585 lines in `ChatViewModel` alone. This logic is platform-independent and will port to the web, but it's the area most likely to introduce subtle bugs during rewrite. Browser tab suspension, network changes, and sleep/wake cycles behave differently than iOS app lifecycle events.

### 3. Token Storage Security Downgrade

**Risk: Medium**

iOS Keychain provides hardware-backed encryption with biometric unlock gating. The web has no equivalent:
- `localStorage`/`sessionStorage` — plaintext, accessible to any JS on the domain, vulnerable to XSS
- `httpOnly` cookies — better (not accessible to JS), but requires a backend to set them
- IndexedDB — same XSS exposure as localStorage

For a developer tool with API tokens, this is a meaningful downgrade. Mitigation options:
- Use `httpOnly` cookies via a thin backend proxy
- Use short-lived tokens with OAuth refresh flows
- Accept the risk — many developer tools (e.g., Vercel dashboard, Railway, Render) store tokens in browser storage and rely on standard web security practices (CSP, HTTPS, XSS prevention)

### 4. No Offline / Background Capability

**Risk: Low (for this app)**

Wisp requires network connectivity to function (it's talking to remote Sprites). Offline support isn't meaningful here. However, if a Claude Code session is running and the user closes the browser tab, the connection drops. On iOS, the exec session continues server-side and can be reattached. On web, the same reattach logic works — but users may be more likely to accidentally close a tab than to kill an iOS app.

### 5. Markdown Rendering Replacement

**Risk: Low**

MarkdownUI (the only third-party iOS dependency) would be replaced by a web markdown library. The web ecosystem has mature options (react-markdown, marked, markdown-it) with syntax highlighting (Shiki, Prism, highlight.js). This is strictly easier on the web.

### 6. Loss of Native iOS Feel

**Risk: Depends on audience**

The current app uses standard iOS patterns: NavigationStack, pull-to-refresh, swipe-to-delete, SF Symbols, system colors, safe area handling. A web app won't feel as native on iOS. However:
- The target audience is developers, who are generally comfortable with web UIs
- The core interaction is a chat interface, which works well on web
- PWA (Progressive Web App) support can provide app-like installation on mobile
- The desktop experience would actually be *better* as a web app than as an iOS-only app

### 7. State Management / Persistence Rewrite

**Risk: Low-Medium**

SwiftData models and `@Observable` view models need web equivalents:
- SwiftData → IndexedDB (via Dexie.js or idb) or localStorage for simple cases
- `@Observable` → React state/context, Zustand, Jotai, or signals (Solid/Preact)
- `SpriteSession` persistence (chat history, session IDs) maps cleanly to any key-value store

The data model is simple (one SwiftData entity with JSON-serialized messages). This is not a complex migration.

### 8. Full Rewrite Cost

**Risk: Medium**

Even at ~3,700 lines, a rewrite means:
- Re-testing all streaming edge cases (timeouts, reattach, stale sessions, lock cleanup)
- Re-implementing the binary WebSocket protocol handler
- Re-building the chat UI with tool cards, collapse/expand, auto-scroll
- Re-implementing GitHub device flow OAuth
- No code sharing between iOS and web versions

If you plan to maintain the iOS app alongside the web app, you now have two codebases. If you're replacing iOS entirely, there's a transition period where the old app exists but isn't getting updates.

### 9. Mobile Input Experience

**Risk: Low-Medium**

iOS provides native keyboard handling, safe area insets, and input accessory views that make chat input smooth on mobile. Web chat inputs on mobile can have quirks:
- Virtual keyboard resizing behavior varies across browsers
- `position: fixed` bottom bars can behave unexpectedly with virtual keyboards
- No native swipe-back gesture (though browser back works)

These are solvable problems, but require testing across mobile browsers.

---

## Technology Options for the Web App

| Concern | Options |
|---------|---------|
| **Framework** | Next.js (React), SvelteKit, Remix, plain React SPA |
| **State** | Zustand, Jotai, React Context, Svelte stores |
| **Persistence** | IndexedDB (Dexie), localStorage, or backend DB |
| **Markdown** | react-markdown + rehype-highlight, Shiki for syntax |
| **WebSocket** | Native browser WebSocket API (binary mode) |
| **Styling** | Tailwind CSS, CSS Modules, shadcn/ui |
| **Auth** | httpOnly cookies via proxy, or client-side token storage |
| **PWA** | Service worker + manifest for installable mobile experience |

---

## Recommendation Summary

| Factor | Verdict |
|--------|---------|
| Cross-platform reach | Strong benefit |
| Desktop experience | Strong benefit |
| Distribution/updates | Strong benefit |
| Development velocity | Moderate benefit |
| Binary WebSocket port | Low risk, straightforward |
| Token security | Acceptable with standard web practices |
| Chat UI quality | Comparable or better (richer markdown libs) |
| Mobile native feel | Minor downgrade, acceptable for dev tool |
| Rewrite effort | Moderate — manageable at current codebase size |
| Reconnection logic | Needs careful porting, most bug-prone area |

**The case for a web app is strong.** Wisp's core feature (a streaming chat UI) is a well-solved problem on the web. The app doesn't depend on iOS-specific hardware capabilities. The codebase is small enough that a rewrite is tractable rather than risky. The biggest wins are desktop support and frictionless distribution — both significant for a developer tool. The biggest cost is re-implementing and re-testing the WebSocket streaming and reconnection logic, which is the app's most complex subsystem.
