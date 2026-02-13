import Foundation
import os.log

private let logger = Logger(subsystem: "com.grahampark.wteasy", category: "ClaudeStatus")

enum ClaudeCodeStatus: String {
    case idle
    case thinking
    case working
    case needsAttention
    case done
}

@MainActor @Observable
final class ClaudeStatusManager {
    private(set) var version: Int = 0
    private var statusByPath: [String: ClaudeCodeStatus] = [:]
    private var sessionsByPath: [String: String] = [:]
    var knownWorktreePaths: Set<String> = []

    private var clearTimers: [String: Timer] = [:]

    init() {
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.grahampark.wteasy.claudeStatus"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            // Extract values here — userInfo crosses process boundary as [AnyHashable: Any]
            let status = notification.userInfo?["status"] as? String
            let cwd = notification.userInfo?["cwd"] as? String
            let sessionId = notification.userInfo?["sessionId"] as? String
            MainActor.assumeIsolated {
                self?.handleEvent(status: status, cwd: cwd, sessionId: sessionId)
            }
        }
    }

    func status(forWorktreePath path: String) -> ClaudeCodeStatus? {
        let _ = version
        return statusByPath[normalizePath(path)]
    }

    func registerWorktreePaths(_ paths: Set<String>) {
        knownWorktreePaths = Set(paths.map { normalizePath($0) })
        logger.info("Registered \(self.knownWorktreePaths.count) worktree paths: \(self.knownWorktreePaths.sorted())")
    }

    // MARK: - Private

    private func normalizePath(_ path: String) -> String {
        if path.hasSuffix("/") && path.count > 1 {
            return String(path.dropLast())
        }
        return path
    }

    private func handleEvent(status statusRaw: String?, cwd rawCwd: String?, sessionId: String?) {
        guard let statusRaw, let rawCwd else {
            logger.warning("Received notification with missing status or cwd")
            return
        }

        let cwd = normalizePath(rawCwd)
        let sessionId = sessionId ?? ""

        logger.info("Received event: status=\(statusRaw) cwd=\(cwd) session=\(sessionId)")

        guard let worktreePath = matchWorktreePath(for: cwd) else {
            logger.warning("No worktree match for cwd=\(cwd). Known paths: \(self.knownWorktreePaths.sorted())")
            return
        }

        // Cancel any pending clear timer for this path
        clearTimers[worktreePath]?.invalidate()
        clearTimers.removeValue(forKey: worktreePath)

        switch statusRaw {
        case "sessionEnded":
            statusByPath.removeValue(forKey: worktreePath)
            sessionsByPath.removeValue(forKey: worktreePath)
        case "done":
            statusByPath[worktreePath] = .done
            sessionsByPath[worktreePath] = sessionId
            // Transition to idle after 30 seconds
            let timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated {
                    if self?.statusByPath[worktreePath] == .done {
                        self?.statusByPath[worktreePath] = .idle
                        self?.version += 1
                    }
                    self?.clearTimers.removeValue(forKey: worktreePath)
                }
            }
            clearTimers[worktreePath] = timer
        default:
            if let status = ClaudeCodeStatus(rawValue: statusRaw) {
                statusByPath[worktreePath] = status
                sessionsByPath[worktreePath] = sessionId
            }
        }

        version += 1
        logger.info("Status updated: worktree=\(worktreePath) status=\(self.statusByPath[worktreePath]?.rawValue ?? "cleared")")
    }

    private func matchWorktreePath(for cwd: String) -> String? {
        // Exact match
        if knownWorktreePaths.contains(cwd) {
            return cwd
        }
        // Prefix match for subdirectories
        for path in knownWorktreePaths {
            if cwd.hasPrefix(path + "/") {
                return path
            }
        }
        return nil
    }
}
