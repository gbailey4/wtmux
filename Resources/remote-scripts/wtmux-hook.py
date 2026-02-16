#!/usr/bin/env python3
"""WTMux Claude Code hook script.

Reads hook event JSON from stdin, maps it to a Claude status, and writes
the result atomically to ~/.wtmux/claude-status.json.

Zero external dependencies. Requires Python 3.6+.
"""

__version__ = "1.0.0"

import json
import os
import sys
import time

# Tools that indicate "working" (writing code) rather than "thinking"
WRITE_TOOLS = {"Edit", "Write", "MultiEdit", "NotebookEdit", "Bash"}

STATUS_FILE = os.path.expanduser("~/.wtmux/claude-status.json")


def map_status(event):
    """Map a hook event to a Claude status string."""
    hook = event.get("hook_event_name", "")

    if hook == "SessionStart":
        return "idle"
    elif hook in ("UserPromptSubmit", "PostToolUse"):
        return "thinking"
    elif hook == "PreToolUse":
        tool = event.get("tool_name", "")
        if tool in WRITE_TOOLS:
            return "working"
        return "thinking"
    elif hook == "Stop":
        return "done"
    elif hook == "SessionEnd":
        return "sessionEnded"
    elif hook == "PermissionRequest":
        return "needsAttention"
    elif hook == "Notification":
        ntype = event.get("notification_type", "")
        if ntype in ("permission_prompt", "idle_prompt", "elicitation_dialog"):
            return "needsAttention"
        return "thinking"
    else:
        return "thinking"


def write_status(status, cwd, session_id):
    """Atomically write status to ~/.wtmux/claude-status.json."""
    data = {
        "status": status,
        "cwd": cwd,
        "sessionId": session_id,
        "timestamp": int(time.time()),
    }

    # Ensure directory exists
    status_dir = os.path.dirname(STATUS_FILE)
    os.makedirs(status_dir, exist_ok=True)

    # Write to temp file then atomic rename
    tmp_path = STATUS_FILE + ".tmp"
    with open(tmp_path, "w") as f:
        json.dump(data, f)
    os.replace(tmp_path, STATUS_FILE)


def main():
    try:
        raw = sys.stdin.read()
        event = json.loads(raw)
    except (json.JSONDecodeError, ValueError):
        sys.exit(1)

    status = map_status(event)
    cwd = event.get("cwd", "")
    session_id = event.get("session_id", "")

    write_status(status, cwd, session_id)


if __name__ == "__main__":
    main()
