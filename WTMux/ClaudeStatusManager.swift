import Foundation
import os.log

private let logger = Logger(subsystem: "com.grahampark.wtmux", category: "ClaudeStatus")

enum ClaudeCodeStatus: String, Comparable {
    case idle
    case done
    case thinking
    case working
    case needsAttention

    /// Priority ordering for aggregate status (higher = more urgent).
    private var priority: Int {
        switch self {
        case .idle: 0
        case .done: 1
        case .thinking: 2
        case .working: 3
        case .needsAttention: 4
        }
    }

    static func < (lhs: ClaudeCodeStatus, rhs: ClaudeCodeStatus) -> Bool {
        lhs.priority < rhs.priority
    }

    func toWindowStatus() -> WindowExecutionStatus {
        switch self {
        case .idle, .done: .idle
        case .thinking, .working: .thinking
        case .needsAttention: .inputNeeded
        }
    }
}

@MainActor @Observable
final class ClaudeStatusManager {
    private(set) var version: Int = 0

    /// Per-worktree-path aggregate status (used by sidebar).
    private var statusByPath: [String: ClaudeCodeStatus] = [:]
    /// Per-pane status: statusByPane[worktreePath][paneId] = status.
    private var statusByPane: [String: [String: ClaudeCodeStatus]] = [:]

    private var sessionsByPath: [String: String] = [:]
    var knownWorktreePaths: Set<String> = []

    private var clearTimers: [String: Timer] = [:]

    init() {
        DistributedNotificationCenter.default().addObserver(
            forName: AppIdentity.claudeStatusNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let status = notification.userInfo?["status"] as? String
            let cwd = notification.userInfo?["cwd"] as? String
            let sessionId = notification.userInfo?["sessionId"] as? String
            let paneId = notification.userInfo?["paneId"] as? String
            MainActor.assumeIsolated {
                self?.handleEvent(status: status, cwd: cwd, sessionId: sessionId, paneId: paneId)
            }
        }
    }

    /// Per-pane status. Returns the status for a specific pane displaying the given worktree.
    func status(forPane paneId: String, worktreePath path: String) -> ClaudeCodeStatus? {
        let _ = version
        return statusByPane[normalizePath(path)]?[paneId]
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

    private func handleEvent(status statusRaw: String?, cwd rawCwd: String?, sessionId: String?, paneId: String?) {
        guard let statusRaw, let rawCwd else {
            logger.warning("Received notification with missing status or cwd")
            return
        }

        let cwd = normalizePath(rawCwd)
        let sessionId = sessionId ?? ""

        logger.info("Received event: status=\(statusRaw) cwd=\(cwd) session=\(sessionId) pane=\(paneId ?? "nil")")

        guard let worktreePath = matchWorktreePath(for: cwd) else {
            logger.warning("No worktree match for cwd=\(cwd). Known paths: \(self.knownWorktreePaths.sorted())")
            return
        }

        let timerKey = paneId.map { "\(worktreePath):\($0)" } ?? worktreePath

        // Cancel any pending clear timer
        clearTimers[timerKey]?.invalidate()
        clearTimers.removeValue(forKey: timerKey)

        switch statusRaw {
        case "sessionEnded":
            if let paneId {
                statusByPane[worktreePath]?.removeValue(forKey: paneId)
                if statusByPane[worktreePath]?.isEmpty == true {
                    statusByPane.removeValue(forKey: worktreePath)
                }
            }
            // Recompute aggregate
            recomputeAggregate(for: worktreePath)
            sessionsByPath.removeValue(forKey: timerKey)

        case "done":
            if let paneId {
                statusByPane[worktreePath, default: [:]][paneId] = .done
            }
            recomputeAggregate(for: worktreePath, fallback: .done)
            sessionsByPath[timerKey] = sessionId

            // Transition to idle after 30 seconds
            let timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated {
                    if let paneId {
                        if self?.statusByPane[worktreePath]?[paneId] == .done {
                            self?.statusByPane[worktreePath]?[paneId] = .idle
                            self?.recomputeAggregate(for: worktreePath)
                            self?.version += 1
                        }
                    } else if self?.statusByPath[worktreePath] == .done {
                        self?.statusByPath[worktreePath] = .idle
                        self?.version += 1
                    }
                    self?.clearTimers.removeValue(forKey: timerKey)
                }
            }
            clearTimers[timerKey] = timer

        default:
            if let status = ClaudeCodeStatus(rawValue: statusRaw) {
                if let paneId {
                    statusByPane[worktreePath, default: [:]][paneId] = status
                }
                recomputeAggregate(for: worktreePath, fallback: status)
                sessionsByPath[timerKey] = sessionId
            }
        }

        version += 1
        logger.info("Status updated: worktree=\(worktreePath) pane=\(paneId ?? "aggregate") status=\(self.statusByPath[worktreePath]?.rawValue ?? "cleared")")
    }

    /// Recomputes the aggregate status for a worktree path from all pane statuses.
    private func recomputeAggregate(for worktreePath: String, fallback: ClaudeCodeStatus? = nil) {
        if let paneStatuses = statusByPane[worktreePath], !paneStatuses.isEmpty {
            statusByPath[worktreePath] = paneStatuses.values.max()
        } else if let fallback {
            statusByPath[worktreePath] = fallback
        } else {
            statusByPath.removeValue(forKey: worktreePath)
        }
    }

    private func matchWorktreePath(for cwd: String) -> String? {
        if knownWorktreePaths.contains(cwd) {
            return cwd
        }
        for path in knownWorktreePaths {
            if cwd.hasPrefix(path + "/") {
                return path
            }
        }
        return nil
    }
}
