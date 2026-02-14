import Foundation

// MARK: - Models

enum ClaudeStatus: String {
    case idle
    case thinking
    case working
    case needsAttention
    case done
    case sessionEnded
}

struct HookEvent: Decodable {
    let session_id: String
    let cwd: String
    let hook_event_name: String
    let tool_name: String?
    let notification_type: String?
}

let writeTools: Set<String> = [
    "Edit", "Write", "MultiEdit", "NotebookEdit", "Bash",
]

// MARK: - Main

let data = FileHandle.standardInput.readDataToEndOfFile()

guard let event = try? JSONDecoder().decode(HookEvent.self, from: data) else {
    exit(1)
}

let status: ClaudeStatus

switch event.hook_event_name {
case "SessionStart":
    status = .idle
case "UserPromptSubmit", "PostToolUse":
    status = .thinking
case "PreToolUse":
    if let toolName = event.tool_name, writeTools.contains(toolName) {
        status = .working
    } else {
        status = .thinking
    }
case "Stop":
    status = .done
case "SessionEnd":
    status = .sessionEnded
case "PermissionRequest":
    status = .needsAttention
case "Notification":
    switch event.notification_type {
    case "permission_prompt", "idle_prompt", "elicitation_dialog":
        status = .needsAttention
    default:
        status = .thinking
    }
default:
    status = .thinking
}

let userInfo: [String: String] = [
    "status": status.rawValue,
    "cwd": event.cwd,
    "sessionId": event.session_id,
]

DistributedNotificationCenter.default().postNotificationName(
    NSNotification.Name("com.grahampark.wtmux.claudeStatus"),
    object: nil,
    userInfo: userInfo,
    deliverImmediately: true
)
