import Foundation
import Testing
import CryptoKit

@testable import IRC

@Suite("WebPush Tests")
struct WebPushTests {

    // MARK: - Test Data

    /// Known-good encrypted body for testing
    static let testBodyStr = "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"
    static let testPrivateKeyBase64 = "ZL4cXdRXfEuPWaGplV4tMQ8WaNKS9h9c+mprDPsICXg="
    static let testAuthBase64url = "HwHfrNDX6XXrVvJ9c9BVIg"
    static let expectedDecryptedMessage = "PING webpush"

    // MARK: - Key Generation Tests

    @Test("Generate keys produces valid structure")
    func generateKeysProducesValidStructure() throws {
        let keys = try WebPush.generateKeys()

        // p256dh should be a non-empty base64url string
        #expect(!keys.p256dh.isEmpty)

        // auth should be a non-empty base64url string
        #expect(!keys.auth.isEmpty)

        // privateKeyRaw should be 32 bytes for P-256
        #expect(keys.privateKeyRaw.count == 32)
    }

    @Test("Generate keys produces valid p256dh public key")
    func generateKeysProducesValidP256dh() throws {
        let keys = try WebPush.generateKeys()

        // Decode p256dh from base64url
        let p256dhData = Data.fromAnyBase64(keys.p256dh)
        #expect(p256dhData != nil)

        // Should be 65 bytes (uncompressed EC point: 0x04 || X || Y)
        #expect(p256dhData?.count == 65)

        // First byte should be 0x04 (uncompressed point indicator)
        #expect(p256dhData?.first == 0x04)

        // Should be importable as a public key
        let publicKey = try? P256.KeyAgreement.PublicKey(x963Representation: p256dhData!)
        #expect(publicKey != nil)
    }

    @Test("Generate keys produces valid auth secret")
    func generateKeysProducesValidAuth() throws {
        let keys = try WebPush.generateKeys()

        // Decode auth from base64url
        let authData = Data.fromAnyBase64(keys.auth)
        #expect(authData != nil)

        // Default should be 16 bytes
        #expect(authData?.count == 16)
    }

    @Test("Generate keys with custom auth bytes")
    func generateKeysWithCustomAuthBytes() throws {
        let keys = try WebPush.generateKeys(authBytes: 32)

        let authData = Data.fromAnyBase64(keys.auth)
        #expect(authData?.count == 32)
    }

    @Test("Generate keys produces usable private key")
    func generateKeysProducesUsablePrivateKey() throws {
        let keys = try WebPush.generateKeys()

        // Should be able to reconstruct the private key
        let privateKey = try? P256.KeyAgreement.PrivateKey(rawRepresentation: keys.privateKeyRaw)
        #expect(privateKey != nil)

        // The reconstructed public key should match p256dh
        let p256dhData = Data.fromAnyBase64(keys.p256dh)!
        #expect(privateKey?.publicKey.x963Representation == p256dhData)
    }

    @Test("Generate keys produces unique keys each time")
    func generateKeysProducesUniqueKeys() throws {
        let keys1 = try WebPush.generateKeys()
        let keys2 = try WebPush.generateKeys()

        // Keys should be different
        #expect(keys1.p256dh != keys2.p256dh)
        #expect(keys1.auth != keys2.auth)
        #expect(keys1.privateKeyRaw != keys2.privateKeyRaw)
    }

    // MARK: - Decryption Tests

    @Test("Decrypt push with Data parameters")
    func decryptWithDataParameters() throws {
        let bodyData = Data(base64Encoded: Self.testBodyStr)!
        let privateKeyData = Data.fromAnyBase64(Self.testPrivateKeyBase64)!
        let privateKey = try P256.KeyAgreement.PrivateKey(rawRepresentation: privateKeyData)
        let authKey = Data.fromAnyBase64(Self.testAuthBase64url)!

        let decrypted = try WebPush.decrypt(
            body: bodyData,
            auth: authKey,
            privateKey: privateKey
        )

        let text = String(data: decrypted, encoding: .utf8)
        #expect(text == Self.expectedDecryptedMessage)
    }

    @Test("Decrypt push with String parameters")
    func decryptWithStringParameters() throws {
        let bodyData = Data(base64Encoded: Self.testBodyStr)!

        let decrypted = try WebPush.decrypt(
            body: bodyData,
            auth: Self.testAuthBase64url,
            privateKey: Self.testPrivateKeyBase64
        )

        let text = String(data: decrypted, encoding: .utf8)
        #expect(text == Self.expectedDecryptedMessage)
    }

    // MARK: - Error Tests

    @Test("Decrypt throws bodyTooShort for empty body")
    func decryptThrowsBodyTooShortForEmptyBody() throws {
        let emptyBody = Data()
        let authKey = Data.fromAnyBase64(Self.testAuthBase64url)!
        let privateKeyData = Data.fromAnyBase64(Self.testPrivateKeyBase64)!
        let privateKey = try P256.KeyAgreement.PrivateKey(rawRepresentation: privateKeyData)

        #expect(throws: WebPush.Error.self) {
            _ = try WebPush.decrypt(body: emptyBody, auth: authKey, privateKey: privateKey)
        }
    }

    @Test("Decrypt throws bodyTooShort for body under 21 bytes")
    func decryptThrowsBodyTooShortForShortBody() throws {
        // Body needs at least 21 bytes (16 salt + 4 rs + 1 idlen)
        let shortBody = Data(repeating: 0, count: 20)
        let authKey = Data.fromAnyBase64(Self.testAuthBase64url)!
        let privateKeyData = Data.fromAnyBase64(Self.testPrivateKeyBase64)!
        let privateKey = try P256.KeyAgreement.PrivateKey(rawRepresentation: privateKeyData)

        #expect(throws: WebPush.Error.self) {
            _ = try WebPush.decrypt(body: shortBody, auth: authKey, privateKey: privateKey)
        }
    }

    @Test("Decrypt throws invalidKeyIDLength for zero idlen")
    func decryptThrowsInvalidKeyIDLengthForZeroIdlen() throws {
        // Create a body with valid header but idlen = 0
        var body = Data(repeating: 0, count: 21)
        body[20] = 0  // idlen = 0

        let authKey = Data.fromAnyBase64(Self.testAuthBase64url)!
        let privateKeyData = Data.fromAnyBase64(Self.testPrivateKeyBase64)!
        let privateKey = try P256.KeyAgreement.PrivateKey(rawRepresentation: privateKeyData)

        #expect(throws: WebPush.Error.self) {
            _ = try WebPush.decrypt(body: body, auth: authKey, privateKey: privateKey)
        }
    }

    @Test("Decrypt throws invalidKeyIDLength when body too short for idlen")
    func decryptThrowsInvalidKeyIDLengthWhenBodyTooShort() throws {
        // Create body with idlen claiming more bytes than available
        var body = Data(repeating: 0, count: 22)
        body[20] = 65  // idlen = 65 (requires 65 more bytes, but only 1 available)

        let authKey = Data.fromAnyBase64(Self.testAuthBase64url)!
        let privateKeyData = Data.fromAnyBase64(Self.testPrivateKeyBase64)!
        let privateKey = try P256.KeyAgreement.PrivateKey(rawRepresentation: privateKeyData)

        #expect(throws: WebPush.Error.self) {
            _ = try WebPush.decrypt(body: body, auth: authKey, privateKey: privateKey)
        }
    }

    @Test("Decrypt throws invalidSenderPublicKey for wrong key size")
    func decryptThrowsInvalidSenderPublicKeyForWrongSize() throws {
        // Create body with idlen = 32 (not 65)
        var body = Data(repeating: 0, count: 21 + 32 + 16)  // header + keyid + minimal ciphertext
        body[20] = 32  // idlen = 32 (wrong, should be 65)

        let authKey = Data.fromAnyBase64(Self.testAuthBase64url)!
        let privateKeyData = Data.fromAnyBase64(Self.testPrivateKeyBase64)!
        let privateKey = try P256.KeyAgreement.PrivateKey(rawRepresentation: privateKeyData)

        #expect(throws: WebPush.Error.self) {
            _ = try WebPush.decrypt(body: body, auth: authKey, privateKey: privateKey)
        }
    }

    @Test("Decrypt throws invalidSenderPublicKey for wrong first byte")
    func decryptThrowsInvalidSenderPublicKeyForWrongFirstByte() throws {
        // Create body with 65-byte key but wrong first byte
        var body = Data(repeating: 0, count: 21 + 65 + 16)
        body[20] = 65  // idlen = 65
        body[21] = 0x02  // Wrong first byte (should be 0x04)

        let authKey = Data.fromAnyBase64(Self.testAuthBase64url)!
        let privateKeyData = Data.fromAnyBase64(Self.testPrivateKeyBase64)!
        let privateKey = try P256.KeyAgreement.PrivateKey(rawRepresentation: privateKeyData)

        #expect(throws: WebPush.Error.self) {
            _ = try WebPush.decrypt(body: body, auth: authKey, privateKey: privateKey)
        }
    }

    @Test("Decrypt throws invalidBase64url for invalid auth string")
    func decryptThrowsInvalidBase64urlForInvalidAuth() throws {
        let bodyData = Data(base64Encoded: Self.testBodyStr)!

        #expect(throws: WebPush.Error.self) {
            _ = try WebPush.decrypt(
                body: bodyData,
                auth: "!!!invalid!!!",
                privateKey: Self.testPrivateKeyBase64
            )
        }
    }

    @Test("Decrypt throws invalidBase64url for invalid privateKey string")
    func decryptThrowsInvalidBase64urlForInvalidPrivateKey() throws {
        let bodyData = Data(base64Encoded: Self.testBodyStr)!

        #expect(throws: WebPush.Error.self) {
            _ = try WebPush.decrypt(
                body: bodyData,
                auth: Self.testAuthBase64url,
                privateKey: "!!!invalid!!!"
            )
        }
    }

    @Test("Decrypt throws invalidPrivateKey for wrong size key data")
    func decryptThrowsInvalidPrivateKeyForWrongSize() throws {
        let bodyData = Data(base64Encoded: Self.testBodyStr)!
        // Create a 16-byte key instead of 32-byte
        let wrongSizeKey = Data(repeating: 0xAB, count: 16).base64EncodedString()

        #expect(throws: WebPush.Error.self) {
            _ = try WebPush.decrypt(
                body: bodyData,
                auth: Self.testAuthBase64url,
                privateKey: wrongSizeKey
            )
        }
    }

    @Test("Decrypt throws ciphertextTooShort when no ciphertext")
    func decryptThrowsCiphertextTooShortWhenNoCiphertext() throws {
        // Create a valid header with proper 65-byte public key but no ciphertext
        var body = Data(repeating: 0, count: 21 + 65)
        body[20] = 65  // idlen = 65
        body[21] = 0x04  // Correct first byte for uncompressed point

        // Fill with valid-looking (but random) public key bytes
        for i in 22..<86 {
            body[i] = UInt8(i % 256)
        }

        let authKey = Data.fromAnyBase64(Self.testAuthBase64url)!
        let privateKeyData = Data.fromAnyBase64(Self.testPrivateKeyBase64)!
        let privateKey = try P256.KeyAgreement.PrivateKey(rawRepresentation: privateKeyData)

        #expect(throws: WebPush.Error.self) {
            _ = try WebPush.decrypt(body: body, auth: authKey, privateKey: privateKey)
        }
    }

    // MARK: - Round-trip Tests

    @Test("Generated keys can be used for key agreement")
    func generatedKeysCanBeUsedForKeyAgreement() throws {
        let keys = try WebPush.generateKeys()

        // Create private key from raw representation
        let privateKey = try P256.KeyAgreement.PrivateKey(rawRepresentation: keys.privateKeyRaw)

        // Create another keypair to simulate sender
        let senderPrivateKey = P256.KeyAgreement.PrivateKey()

        // Both sides should be able to derive shared secret
        let receiverSharedSecret = try privateKey.sharedSecretFromKeyAgreement(with: senderPrivateKey.publicKey)
        let senderSharedSecret = try senderPrivateKey.sharedSecretFromKeyAgreement(with: privateKey.publicKey)

        // Shared secrets should match
        let receiverSecretData = receiverSharedSecret.withUnsafeBytes { Data($0) }
        let senderSecretData = senderSharedSecret.withUnsafeBytes { Data($0) }
        #expect(receiverSecretData == senderSecretData)
    }
}
