import Foundation
import NIOCore
import NIOSSH

/// Authentication method for SSH connections.
public enum SSHAuthMethod: Sendable {
    /// Public key authentication using a key file on disk.
    case keyFile(path: String, passphrase: String? = nil)
}

/// Bridges `SSHAuthMethod` to NIOSSH's `NIOSSHClientUserAuthenticationDelegate`.
final class KeyFileAuthDelegate: NIOSSHClientUserAuthenticationDelegate {
    private let username: String
    private let keyPath: String
    private let passphrase: String?
    private var attemptedKey = false

    init(username: String, keyPath: String, passphrase: String?) {
        self.username = username
        self.keyPath = keyPath
        self.passphrase = passphrase
    }

    func nextAuthenticationType(
        availableMethods: NIOSSHAvailableUserAuthenticationMethods,
        nextChallengePromise: EventLoopPromise<NIOSSHUserAuthenticationOffer?>
    ) {
        guard !attemptedKey else {
            nextChallengePromise.succeed(nil)
            return
        }
        attemptedKey = true

        guard availableMethods.contains(.publicKey) else {
            nextChallengePromise.succeed(nil)
            return
        }

        do {
            let key = try loadPrivateKey(path: keyPath, passphrase: passphrase)
            nextChallengePromise.succeed(.init(
                username: username,
                serviceName: "",
                offer: .privateKey(.init(privateKey: key))
            ))
        } catch {
            nextChallengePromise.fail(error)
        }
    }

    private func loadPrivateKey(path: String, passphrase: String?) throws -> NIOSSHPrivateKey {
        let expandedPath = (path as NSString).expandingTildeInPath
        let keyData = try String(contentsOfFile: expandedPath, encoding: .utf8)

        // Try Ed25519 first, then ECDSA P256, then RSA
        // NIOSSH parses PEM-encoded keys

        if let passphrase, !passphrase.isEmpty {
            // Encrypted key — try each type with passphrase
            if let key = try? NIOSSHPrivateKey(ed25519Key: .init(rawRepresentation: Self.decodeKey(pem: keyData))) {
                return key
            }
            // For encrypted keys, we need to parse the PEM envelope ourselves
            // Fall through to unencrypted parsing as NIOSSH doesn't support encrypted PEM directly
            throw SSHError.encryptedKeyNotSupported
        }

        // Unencrypted key — detect type from PEM header
        if keyData.contains("OPENSSH PRIVATE KEY") {
            return try parseOpenSSHKey(keyData)
        }

        // Legacy PEM formats
        if keyData.contains("RSA PRIVATE KEY") {
            // NIOSSH doesn't support RSA PEM directly — would need conversion
            throw SSHError.unsupportedKeyType("RSA (legacy PEM format)")
        }

        if keyData.contains("EC PRIVATE KEY") {
            throw SSHError.unsupportedKeyType("ECDSA (legacy PEM format)")
        }

        throw SSHError.unsupportedKeyType("unknown")
    }

    /// Parses an OpenSSH-format private key (the modern `-----BEGIN OPENSSH PRIVATE KEY-----` format).
    private func parseOpenSSHKey(_ pem: String) throws -> NIOSSHPrivateKey {
        // Extract base64 payload
        let lines = pem.components(separatedBy: .newlines)
            .filter { !$0.hasPrefix("-----") && !$0.isEmpty }
        let base64 = lines.joined()
        guard let data = Data(base64Encoded: base64) else {
            throw SSHError.invalidKeyFormat
        }

        // OpenSSH key format: "openssh-key-v1\0" magic, then fields
        let magic = "openssh-key-v1\0"
        guard data.count > magic.utf8.count,
              String(data: data[0..<magic.utf8.count], encoding: .utf8) == magic else {
            throw SSHError.invalidKeyFormat
        }

        // Parse the binary format to extract key type
        var offset = magic.utf8.count

        func readUInt32() throws -> UInt32 {
            guard offset + 4 <= data.count else { throw SSHError.invalidKeyFormat }
            let value = data[offset..<offset+4].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).bigEndian }
            offset += 4
            return value
        }

        func readString() throws -> Data {
            let length = try Int(readUInt32())
            guard offset + length <= data.count else { throw SSHError.invalidKeyFormat }
            let value = data[offset..<offset+length]
            offset += length
            return value
        }

        // ciphername, kdfname, kdfoptions
        let cipherName = try String(data: readString(), encoding: .utf8) ?? ""
        _ = try readString() // kdfname
        _ = try readString() // kdfoptions

        if cipherName != "none" {
            throw SSHError.encryptedKeyNotSupported
        }

        // number of keys
        let numKeys = try readUInt32()
        guard numKeys == 1 else {
            throw SSHError.unsupportedKeyType("multi-key file")
        }

        // public key blob (skip)
        _ = try readString()

        // private key section
        let privateSection = try readString()
        var privOffset = 0

        func privReadUInt32() throws -> UInt32 {
            guard privOffset + 4 <= privateSection.count else { throw SSHError.invalidKeyFormat }
            let value = privateSection[privateSection.startIndex + privOffset ..< privateSection.startIndex + privOffset + 4]
                .withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).bigEndian }
            privOffset += 4
            return value
        }

        func privReadString() throws -> Data {
            let length = try Int(privReadUInt32())
            guard privOffset + length <= privateSection.count else { throw SSHError.invalidKeyFormat }
            let value = privateSection[privateSection.startIndex + privOffset ..< privateSection.startIndex + privOffset + length]
            privOffset += length
            return value
        }

        // checkint1, checkint2
        let check1 = try privReadUInt32()
        let check2 = try privReadUInt32()
        guard check1 == check2 else {
            throw SSHError.invalidKeyFormat
        }

        // key type string
        let keyTypeData = try privReadString()
        guard let keyType = String(data: keyTypeData, encoding: .utf8) else {
            throw SSHError.invalidKeyFormat
        }

        switch keyType {
        case "ssh-ed25519":
            // Ed25519: pubkey (32 bytes), then privkey (64 bytes = seed + pubkey)
            _ = try privReadString() // public key
            let privKeyData = try privReadString() // 64 bytes
            guard privKeyData.count == 64 else {
                throw SSHError.invalidKeyFormat
            }
            let seed = privKeyData[privKeyData.startIndex..<privKeyData.startIndex + 32]
            let ed25519Key = try Curve25519.Signing.PrivateKey(rawRepresentation: seed)
            return NIOSSHPrivateKey(ed25519Key: ed25519Key)

        case "ecdsa-sha2-nistp256":
            // ECDSA P256: curve name, public point, private scalar
            _ = try privReadString() // curve identifier
            _ = try privReadString() // public key point
            let privateScalar = try privReadString()
            let p256Key = try P256.Signing.PrivateKey(rawRepresentation: privateScalar)
            return NIOSSHPrivateKey(p256Key: p256Key)

        default:
            throw SSHError.unsupportedKeyType(keyType)
        }
    }

    private static func decodeKey(pem: String) -> Data {
        let lines = pem.components(separatedBy: .newlines)
            .filter { !$0.hasPrefix("-----") && !$0.isEmpty }
        return Data(base64Encoded: lines.joined()) ?? Data()
    }
}

import Crypto
