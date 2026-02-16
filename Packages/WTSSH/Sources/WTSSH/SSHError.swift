import Foundation

/// Errors specific to SSH operations.
public enum SSHError: LocalizedError, Sendable {
    case connectionFailed(String)
    case authenticationFailed
    case channelFailed(String)
    case commandFailed(String)
    case encryptedKeyNotSupported
    case unsupportedKeyType(String)
    case invalidKeyFormat
    case noKeyFileFound
    case notConnected
    case shellSessionClosed

    public var errorDescription: String? {
        switch self {
        case .connectionFailed(let detail):
            return "SSH connection failed: \(detail)"
        case .authenticationFailed:
            return "SSH authentication failed"
        case .channelFailed(let detail):
            return "SSH channel error: \(detail)"
        case .commandFailed(let detail):
            return "SSH command failed: \(detail)"
        case .encryptedKeyNotSupported:
            return "Encrypted SSH keys are not yet supported"
        case .unsupportedKeyType(let type):
            return "Unsupported SSH key type: \(type)"
        case .invalidKeyFormat:
            return "Invalid SSH key format"
        case .noKeyFileFound:
            return "No SSH key file found in ~/.ssh/"
        case .notConnected:
            return "Not connected to SSH server"
        case .shellSessionClosed:
            return "SSH shell session was closed"
        }
    }
}
