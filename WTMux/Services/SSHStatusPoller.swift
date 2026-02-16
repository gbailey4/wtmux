import Foundation
import WTTransport
import os.log

private let logger = Logger(subsystem: "com.grahampark.wtmux", category: "SSHStatusPoller")

actor SSHStatusPoller {
    private struct PollEntry {
        let transport: CommandTransport
        var projectKeys: Set<String>
        var task: Task<Void, Never>?
        var lastTimestamp: Int = 0
    }

    /// Key: "user@host:port" — one poll loop per unique SSH endpoint.
    private var entries: [String: PollEntry] = [:]
    private var onStatusUpdate: (@MainActor @Sendable (String, String, String, String) -> Void)?

    /// Start polling for a project. `projectKey` is typically the project's repoPath.
    /// `onStatusUpdate` receives (status, cwd, sessionId, projectKey).
    func startPolling(
        transport: CommandTransport,
        projectKey: String,
        hostKey: String,
        onStatusUpdate: @escaping @MainActor @Sendable (String, String, String, String) -> Void
    ) {
        self.onStatusUpdate = onStatusUpdate

        if var existing = entries[hostKey] {
            var keys = existing.projectKeys
            keys.insert(projectKey)
            existing.projectKeys = keys
            entries[hostKey] = existing
            return
        }

        var entry = PollEntry(
            transport: transport,
            projectKeys: [projectKey]
        )
        let task = Task {
            await self.pollLoop(hostKey: hostKey)
        }
        entry.task = task
        entries[hostKey] = entry
    }

    func stopPolling(projectKey: String) {
        for (hostKey, var entry) in entries {
            var keys = entry.projectKeys
            keys.remove(projectKey)
            if keys.isEmpty {
                entry.task?.cancel()
                entries.removeValue(forKey: hostKey)
            } else {
                entry.projectKeys = keys
                entries[hostKey] = entry
            }
        }
    }

    func stopAll() {
        for (_, entry) in entries {
            entry.task?.cancel()
        }
        entries.removeAll()
    }

    // MARK: - Private

    private func pollLoop(hostKey: String) async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { break }

            guard let entry = entries[hostKey] else { break }
            let transport = entry.transport
            let projectKeys = entry.projectKeys

            do {
                let result = try await transport.execute(
                    "cat ~/.wtmux/claude-status.json 2>/dev/null",
                    in: nil
                )

                guard result.succeeded else { continue }
                let output = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !output.isEmpty else { continue }

                guard let data = output.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let status = json["status"] as? String,
                      let cwd = json["cwd"] as? String,
                      let sessionId = json["sessionId"] as? String,
                      let timestamp = json["timestamp"] as? Int else {
                    continue
                }

                // Skip if we've already processed this timestamp
                let lastTimestamp = entries[hostKey]?.lastTimestamp ?? 0
                guard timestamp > lastTimestamp else { continue }
                entries[hostKey]?.lastTimestamp = timestamp

                // Check for stale timestamps (> 120 seconds old and not idle/sessionEnded)
                let now = Int(Date().timeIntervalSince1970)
                let effectiveStatus: String
                if now - timestamp > 120 && status != "idle" && status != "sessionEnded" {
                    effectiveStatus = "idle"
                } else {
                    effectiveStatus = status
                }

                // Notify for all project keys on this host
                let callback = onStatusUpdate
                for key in projectKeys {
                    await callback?(effectiveStatus, cwd, sessionId, key)
                }
            } catch {
                logger.debug("Poll error for \(hostKey): \(error.localizedDescription)")
            }
        }
    }
}
