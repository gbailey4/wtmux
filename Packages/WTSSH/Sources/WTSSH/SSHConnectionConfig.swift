import Foundation

/// Configuration for establishing an SSH connection.
public struct SSHConnectionConfig: Sendable, Hashable {
    public let host: String
    public let port: Int
    public let username: String
    public let authMethod: SSHAuthMethod

    /// Unique key for connection pooling (one connection per host+port+user).
    var poolKey: String {
        "\(username)@\(host):\(port)"
    }

    public init(host: String, port: Int = 22, username: String, authMethod: SSHAuthMethod) {
        self.host = host
        self.port = port
        self.username = username
        self.authMethod = authMethod
    }

    /// Creates a config using the default SSH key discovery (checks ~/.ssh/ for common key files).
    public init(host: String, port: Int = 22, username: String, keyPath: String? = nil, passphrase: String? = nil) {
        self.host = host
        self.port = port
        self.username = username

        if let keyPath {
            self.authMethod = .keyFile(path: keyPath, passphrase: passphrase)
        } else {
            // Auto-discover default key
            let defaultKeyPath = Self.findDefaultKeyPath() ?? "~/.ssh/id_ed25519"
            self.authMethod = .keyFile(path: defaultKeyPath, passphrase: passphrase)
        }
    }

    /// Searches `~/.ssh/` for common key file names.
    public static func findDefaultKeyPath() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "\(home)/.ssh/id_ed25519",
            "\(home)/.ssh/id_ecdsa",
            "\(home)/.ssh/id_rsa",
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0) }
    }
}

extension SSHAuthMethod: Hashable {
    public static func == (lhs: SSHAuthMethod, rhs: SSHAuthMethod) -> Bool {
        switch (lhs, rhs) {
        case (.keyFile(let lPath, _), .keyFile(let rPath, _)):
            return lPath == rPath
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .keyFile(let path, _):
            hasher.combine("keyFile")
            hasher.combine(path)
        }
    }
}
