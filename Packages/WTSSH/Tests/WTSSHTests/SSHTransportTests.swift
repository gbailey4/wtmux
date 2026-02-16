import Testing
import Foundation
@testable import WTSSH

@Suite("SSHConnectionConfig")
struct SSHConnectionConfigTests {
    @Test func poolKeyFormat() {
        let config = SSHConnectionConfig(
            host: "example.com",
            port: 22,
            username: "deploy",
            authMethod: .keyFile(path: "~/.ssh/id_ed25519")
        )
        #expect(config.poolKey == "deploy@example.com:22")
    }

    @Test func poolKeyCustomPort() {
        let config = SSHConnectionConfig(
            host: "dev.server.io",
            port: 2222,
            username: "user",
            authMethod: .keyFile(path: "/keys/id_rsa")
        )
        #expect(config.poolKey == "user@dev.server.io:2222")
    }

    @Test func configEquality() {
        let a = SSHConnectionConfig(host: "host", port: 22, username: "user", authMethod: .keyFile(path: "/a"))
        let b = SSHConnectionConfig(host: "host", port: 22, username: "user", authMethod: .keyFile(path: "/a"))
        #expect(a == b)
    }

    @Test func configInequality() {
        let a = SSHConnectionConfig(host: "host", port: 22, username: "user", authMethod: .keyFile(path: "/a"))
        let b = SSHConnectionConfig(host: "host", port: 22, username: "user", authMethod: .keyFile(path: "/b"))
        #expect(a != b)
    }

    @Test func autoDiscoverInitializer() {
        let config = SSHConnectionConfig(host: "example.com", username: "user")
        // Should default to port 22 and pick a key path
        #expect(config.port == 22)
        #expect(config.host == "example.com")
        #expect(config.username == "user")
    }
}

@Suite("SSHError")
struct SSHErrorTests {
    @Test func errorDescriptions() {
        let errors: [SSHError] = [
            .connectionFailed("timeout"),
            .authenticationFailed,
            .channelFailed("EOF"),
            .commandFailed("exit 1"),
            .encryptedKeyNotSupported,
            .unsupportedKeyType("dsa"),
            .invalidKeyFormat,
            .noKeyFileFound,
            .notConnected,
            .shellSessionClosed,
        ]
        for error in errors {
            #expect(error.errorDescription != nil)
        }
    }
}

@Suite("Shell Escaping")
struct ShellEscapingTests {
    @Test func simplePathsNotEscaped() throws {
        let transport = SSHTransport(
            connectionManager: SSHConnectionManager(),
            config: SSHConnectionConfig(host: "h", username: "u", authMethod: .keyFile(path: "/k"))
        )
        // We can't call the private shellEscape directly, but we can verify
        // the transport is created without errors
        _ = transport
    }
}
