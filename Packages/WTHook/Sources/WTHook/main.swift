import Foundation

// MARK: - App Identity

/// Reads the notification prefix from the parent app bundle's Info.plist.
/// The hook binary lives at App.app/Contents/MacOS/wtmux-hook, so Info.plist
/// is at App.app/Contents/Info.plist — two levels up from the executable.
func notificationPrefix() -> String {
    let execPath = ProcessInfo.processInfo.arguments[0]
    let contentsURL = URL(fileURLWithPath: execPath)
        .deletingLastPathComponent()  // MacOS/
        .deletingLastPathComponent()  // Contents/
    let plistURL = contentsURL.appendingPathComponent("Info.plist")
    if let data = try? Data(contentsOf: plistURL),
       let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
       let prefix = dict["WTMuxNotificationPrefix"] as? String {
        return prefix
    }
    return "com.grahampark.wtmux"
}

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

var userInfo: [String: String] = [
    "status": status.rawValue,
    "cwd": event.cwd,
    "sessionId": event.session_id,
]
if let columnId = ProcessInfo.processInfo.environment["WTMUX_COLUMN_ID"] {
    userInfo["columnId"] = columnId
}

DistributedNotificationCenter.default().postNotificationName(
    NSNotification.Name("\(notificationPrefix()).claudeStatus"),
    object: nil,
    userInfo: userInfo,
    deliverImmediately: true
)
