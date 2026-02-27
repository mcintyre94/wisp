import Foundation

enum ClaudeQuestionTool {
    static let version = "3"

    // Full Python MCP server source — human-readable
    static let serverScript = """
    #!/usr/bin/env python3
    \"\"\"Wisp MCP server providing WispAsk for Claude Code headless sessions.\"\"\"

    import json
    import os
    import sys
    import time

    SESSION_ID = os.environ.get("WISP_SESSION_ID", "default")
    QUESTION_FILE = f"/tmp/.wisp_ask_pending_{SESSION_ID}.json"
    RESPONSE_FILE = f"/tmp/.wisp_ask_response_{SESSION_ID}.json"

    TIMEOUT = 300  # 5 minutes


    def read_message():
        line = sys.stdin.readline()
        if not line:
            return None
        line = line.strip()
        if not line:
            return None
        return json.loads(line)


    def send_message(obj):
        data = json.dumps(obj)
        sys.stdout.write(data + chr(10))
        sys.stdout.flush()


    TOOL_DEF = {
        "name": "WispAsk",
        "description": (
            "Ask the Wisp app user a clarifying question and wait for their response before "
            "proceeding. Use when you need a decision or preference from the user. "
            "Prefer this over making assumptions."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "question": {
                    "type": "string",
                    "description": "The question to ask the user",
                },
                "options": {
                    "type": "array",
                    "description": "Optional list of choices for the user to select from",
                    "items": {
                        "type": "object",
                        "properties": {
                            "label": {"type": "string"},
                            "description": {"type": "string"},
                        },
                        "required": ["label"],
                    },
                },
            },
            "required": ["question"],
        },
    }


    def handle_ask_user_question(args, msg_id):
        # Clean up stale response file
        try:
            os.remove(RESPONSE_FILE)
        except OSError:
            pass

        # Write question for the app to pick up
        with open(QUESTION_FILE, "w") as f:
            json.dump(args, f)

        # Poll for response
        deadline = time.time() + TIMEOUT
        answer = "User did not respond. Use your best judgment and proceed."
        while time.time() < deadline:
            if os.path.exists(RESPONSE_FILE):
                try:
                    with open(RESPONSE_FILE) as f:
                        resp = json.load(f)
                    answer = resp.get("answer", answer)
                    os.remove(RESPONSE_FILE)
                    break  # only break on successful parse; retry if file is still being written
                except (OSError, json.JSONDecodeError):
                    pass
            time.sleep(0.2)

        # Clean up question file
        try:
            os.remove(QUESTION_FILE)
        except OSError:
            pass

        send_message({
            "jsonrpc": "2.0",
            "id": msg_id,
            "result": {"content": [{"type": "text", "text": answer}]},
        })


    def main():
        while True:
            msg = read_message()
            if msg is None:
                break

            method = msg.get("method", "")
            msg_id = msg.get("id")

            if method == "initialize":
                send_message({
                    "jsonrpc": "2.0",
                    "id": msg_id,
                    "result": {
                        "protocolVersion": "2025-11-25",
                        "capabilities": {"tools": {}},
                        "serverInfo": {"name": "wisp-ask-user", "version": "1.0.0"},
                    },
                })
            elif method == "notifications/initialized":
                pass  # No response needed
            elif method == "tools/list":
                send_message({
                    "jsonrpc": "2.0",
                    "id": msg_id,
                    "result": {"tools": [TOOL_DEF]},
                })
            elif method == "tools/call":
                params = msg.get("params", {})
                if params.get("name") == "WispAsk":
                    handle_ask_user_question(params.get("arguments", {}), msg_id)
            # Ignore notifications (no id) and unknown methods


    if __name__ == "__main__":
        main()
    """

    // Shell command to read current installed version (empty string if not installed)
    static let checkVersionCommand = "cat ~/.wisp/claude-question/version 2>/dev/null || echo ''"

    // Shell command to make server.py executable after upload
    static let chmodCommand = "chmod +x ~/.wisp/claude-question/server.py"

    // File paths on the Sprite (absolute)
    static let serverPyPath = "/home/sprite/.wisp/claude-question/server.py"
    static let versionPath = "/home/sprite/.wisp/claude-question/version"

    // Per-session helpers — each chat uses its own files so concurrent sessions don't conflict
    static func mcpConfigJSON(for sessionId: String) -> String {
        #"{"mcpServers":{"askUser":{"command":"python3","args":["/home/sprite/.wisp/claude-question/server.py"],"env":{"WISP_SESSION_ID":""# + sessionId + #""}}}}"#
    }

    static func mcpConfigFilePath(for sessionId: String) -> String {
        "/tmp/.wisp_mcp_\(sessionId).json"
    }

    static func responseFilePath(for sessionId: String) -> String {
        "/tmp/.wisp_ask_response_\(sessionId).json"
    }
}
