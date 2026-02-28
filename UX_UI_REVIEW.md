# UX/UI Review & Suggestions: Wisp for iOS

Wisp is a technically impressive project that successfully translates a CLI-first tool (Claude Code) into a mobile-native experience. The use of **Live Activities**, **Glassmorphism**, and **Device Flow for GitHub Auth** shows a high level of engineering polish.

To elevate the app from a functional tool to a premium developer experience, I suggest the following improvements:

### 1. Visual Identity & "Glassmorphism" 
The app has a partially implemented glassmorphism theme (via `.glassEffect()`). Leaning into this could give Wisp a unique, high-end "Pro" feel.
*   **Expansion:** Use the glass effect for the dashboard cards, not just the tab picker and input bar.
*   **Depth:** Add subtle gradients to the background of the `DashboardView` or `SpriteDetailView` to make the glass elements "pop" more.
*   **Consistent Icons:** Ensure icons (like the Sprite status dots) have a consistent soft-glow or shaded look to match the glass aesthetic.

### 2. Dashboard Modernization
The current list-based dashboard is functional but feels very "System UI".
*   **Card-Based Layout:** Switch from a simple `List` to a `LazyVGrid` or a custom `VStack` of cards. Each card could show a small "last activity" snippet or a preview of the linked GitHub repo.
*   **Stateful Badges:** Instead of just a colored dot, use pill-shaped badges with subtle pulsing animations for `running` Sprites.
*   **Quick Actions:** Add a "long press" menu on Sprite cards for common tasks: *New Checkpoint*, *Open URL*, or *New Chat*.

### 3. Chat Interface Refinement (The Core Experience)
The chat view is where users spend 90% of their time. Small polishes here have the highest impact.
*   **Markdown & Syntax Highlighting:** The current `.basic` theme is too limited for a developer tool. Integrating a robust syntax highlighter for code blocks is essential.
*   **Message Grouping:** Avoid "choppy" bubbles. If Claude sends multiple text blocks or tool results in a row, group them into a single visual container.
*   **Inline Tool Results:** For high-frequency, low-output tools (like `ls`, `pwd`, or small `read` calls), show the result *inline* inside the assistant bubble instead of requiring a tap-to-sheet.
*   **Code Diffs:** When Claude uses the `Edit` tool, render a `Unified Diff` view with green/red backgrounds rather than raw patch text.
*   **Granular Thinking:** Use the streaming data to show more than just "Thinking...". Display the specific tool being used, e.g., *"Searching files..."* or *"Installing npm packages..."*.

### 4. Onboarding & Auth Polish
Handling long API tokens on mobile is a major friction point.
*   **Token Import:** Add a "Paste from Clipboard" button that automatically cleans whitespace/newlines. 
*   **QR Code Support:** Consider a small CLI utility or a webpage that displays a QR code for the Sprites/Claude tokens, which Wisp can scan.
*   **Visual Progress:** The 3-step wizard is great; adding a progress bar or "step indicator" dots at the top would clarify the journey.

### 5. Advanced Workflow Features
*   **Interactive Terminal:** As noted in the spec, implementing the terminal is a key "Phase 3" feature. For mobile developers, having an emergency TTY for `git` conflicts or `docker` logs is a lifesaver.
*   **File Tree:** While the `Files` tab exists, a tree-view (collapsible folders) is often more intuitive than a flat drill-down for navigating codebases.
*   **Live Activity Visibility:** Ensure the Live Activity is clearly triggered during long-running tasks and provides a "Stop" button directly from the lock screen.

### Summary of Priority Actions:
1.  **High Priority:** Syntax highlighting in markdown and inline tool result previews.
2.  **Medium Priority:** Card-based dashboard layout and unified diff view for edits.
3.  **Low Priority:** QR code token import and expanded glassmorphism.
