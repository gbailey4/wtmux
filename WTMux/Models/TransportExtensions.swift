import WTCore
import WTTransport
import WTSSH

extension Project {
    /// Creates the appropriate transport for this project — SSH for remote projects, local otherwise.
    func makeTransport(connectionManager: SSHConnectionManager) -> CommandTransport {
        if isRemote, let host = sshHost, let user = sshUser {
            let config = SSHConnectionConfig(
                host: host,
                port: sshPort ?? 22,
                username: user,
                keyPath: sshKeyPath
            )
            return SSHTransport(connectionManager: connectionManager, config: config)
        }
        return LocalTransport()
    }

    /// Creates an `SSHConnectionConfig` for this project, or nil if not remote.
    func sshConfig() -> SSHConnectionConfig? {
        guard isRemote, let host = sshHost, let user = sshUser else { return nil }
        return SSHConnectionConfig(
            host: host,
            port: sshPort ?? 22,
            username: user,
            keyPath: sshKeyPath
        )
    }
}
