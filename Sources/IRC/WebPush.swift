import Foundation
import CryptoKit

public struct WebPush {

    public enum Error: Swift.Error {
        case bodyTooShort(Int)
        case invalidKeyIDLength(Int)
        case invalidSenderPublicKey
        case ciphertextTooShort
        case badPadding
        case unexpectedPublicKeyFormat
        case invalidBase64url(String)
        case invalidPrivateKey
    }

    public struct Keys {
        /// Base64url (no padding). 65-byte uncompressed EC point (0x04 || X || Y).
        public let p256dh: String

        /// Base64url (no padding). Usually 16 random bytes.
        public let auth: String

        /// Optional: Persist this if you need to decrypt incoming pushes later.
        /// This is the private key raw representation (32 bytes for P-256).
        public let privateKeyRaw: Data
    }

    /// Generates push keys needed to register for IRCv3 draft/webpush when executing the command:
    /// `WEBPUSH REGISTER <endpoint> p256dh=<publicKey>;auth=<auth>`
    public static func generateKeys(authBytes: Int = 16) throws -> Keys {
        // 1) Generate P-256 ECDH keypair
        let privateKey = P256.KeyAgreement.PrivateKey()

        // 2) Export public key as ANSI X9.63 (uncompressed 65 bytes: 0x04 + 32 + 32)
        let publicKeyX963 = privateKey.publicKey.x963Representation
        guard publicKeyX963.count == 65, publicKeyX963.first == 0x04 else {
            throw Error.unexpectedPublicKeyFormat
        }

        // 3) Base64url encode p256dh (NO padding)
        let p256dh = base64url(publicKeyX963)

        // 4) Generate auth secret (random bytes), base64url encode (NO padding)
        let authData = randomBytes(count: authBytes)
        let auth = base64url(authData)

        // 5) Persist private key raw bytes if needed (for decrypting pushes later)
        let privateKeyRaw = privateKey.rawRepresentation

        return .init(p256dh: p256dh, auth: auth, privateKeyRaw: privateKeyRaw)
    }

    /// Decrypts an RFC8291/RFC8188 `Content-Encoding: aes128gcm` body.
    ///
    /// - Parameters:
    ///   - body: Raw HTTP body bytes (starts with salt/rs/idlen/keyid...)
    ///   - auth: Your subscription `auth` secret (16 bytes, decoded from base64url)
    ///   - privateKey: Your subscription private key corresponding to `p256dh`
    /// - Returns: Decrypted payload bytes (padding removed)
    public static func decrypt(body: Data, auth: Data, privateKey: P256.KeyAgreement.PrivateKey) throws -> Data {
        // Header: salt(16) || rs(4) || idlen(1) || keyid(idlen) || ciphertext...
        guard body.count >= 16 + 4 + 1 else { throw Error.bodyTooShort(body.count) }

        let salt = body.subdata(in: 0..<16)
        let rsData = body.subdata(in: 16..<20)
        _ = rsData.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian } // mostly for debugging

        let idlen = Int(body[20])
        guard idlen > 0, body.count >= 21 + idlen else {
            throw Error.invalidKeyIDLength(idlen)
        }

        let asPubBytes = body.subdata(in: 21..<(21 + idlen))
        let ciphertextAndTag = body.subdata(in: (21 + idlen)..<body.count)

        // Sender public key is an uncompressed EC point (P-256 => 65 bytes starting with 0x04)
        // (Ergo should be sending 65 here.)
        guard asPubBytes.count == 65, asPubBytes.first == 0x04 else {
            throw Error.invalidSenderPublicKey
        }

        let asPublicKey: P256.KeyAgreement.PublicKey
        do {
            asPublicKey = try P256.KeyAgreement.PublicKey(x963Representation: asPubBytes)
        } catch {
            throw Error.invalidSenderPublicKey
        }

        // ECDH shared secret
        let sharedSecret = try privateKey.sharedSecretFromKeyAgreement(with: asPublicKey)
        let ecdhSecretData = sharedSecret.withUnsafeBytes { Data($0) } // 32 bytes for P-256

        // UA public key (x963) and AS public key (x963)
        let uaPubBytes = privateKey.publicKey.x963Representation

        // RFC8291 info: "WebPush: info" || 0x00 || ua_public || as_public
        var keyInfo = Data()
        keyInfo.append("WebPush: info".data(using: .utf8)!)
        keyInfo.append(0x00)
        keyInfo.append(uaPubBytes)
        keyInfo.append(asPubBytes)

        // IKM = HKDF-Extract(salt=authSecret, IKM=ecdhSecret) then HKDF-Expand(..., info=keyInfo, L=32)
        // CryptoKit's HKDF.deriveKey does Extract+Expand.
        let ikmKey = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: ecdhSecretData),
            salt: auth,
            info: keyInfo,
            outputByteCount: 32
        )
        let ikm = ikmKey.withUnsafeBytes { Data($0) }

        // PRK = HKDF-Extract(salt=saltFromBody, IKM=ikm) then expand to CEK and NONCE
        let cekKey = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: ikm),
            salt: salt,
            info: Data("Content-Encoding: aes128gcm\u{0}".utf8),
            outputByteCount: 16
        )
        let nonceKey = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: ikm),
            salt: salt,
            info: Data("Content-Encoding: nonce\u{0}".utf8),
            outputByteCount: 12
        )

        let cek = cekKey.withUnsafeBytes { Data($0) }
        let nonceData = nonceKey.withUnsafeBytes { Data($0) }

        // AES-GCM: ciphertextAndTag = ciphertext || tag(16)
        guard ciphertextAndTag.count >= 16 else {
            throw Error.ciphertextTooShort
        }
        let tag = ciphertextAndTag.suffix(16)
        let ciphertext = ciphertextAndTag.dropLast(16)

        let nonce = try AES.GCM.Nonce(data: nonceData)
        let sealedBox = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)
        let plaintext = try AES.GCM.open(sealedBox, using: SymmetricKey(data: cek))

        // Remove RFC8188 padding: strip trailing 0x00, then require delimiter 0x02 (final record)
        return try stripRFC8188Padding(plaintext)
    }

    /// Convenience method that decrypts using base64url-encoded string parameters.
    ///
    /// - Parameters:
    ///   - body: Raw HTTP body bytes (starts with salt/rs/idlen/keyid...)
    ///   - auth: Your subscription `auth` secret as a base64url string (no padding)
    ///   - privateKey: Your subscription private key raw bytes as a base64url string (no padding)
    /// - Returns: Decrypted payload bytes (padding removed)
    public static func decrypt(body: Data, auth: String, privateKey: String) throws -> Data {
        guard let authData = base64urlDecode(auth) else {
            throw Error.invalidBase64url("auth")
        }
        guard let privateKeyData = base64urlDecode(privateKey) else {
            throw Error.invalidBase64url("privateKey")
        }
        let key: P256.KeyAgreement.PrivateKey
        do {
            key = try P256.KeyAgreement.PrivateKey(rawRepresentation: privateKeyData)
        } catch {
            throw Error.invalidPrivateKey
        }
        return try decrypt(body: body, auth: authData, privateKey: key)
    }

    private static func stripRFC8188Padding(_ plaintext: Data) throws -> Data {
        if plaintext.isEmpty { return plaintext }

        var i = plaintext.count - 1
        while i >= 0 && plaintext[i] == 0x00 {
            if i == 0 { break }
            i -= 1
        }

        // Now plaintext[i] should be the padding delimiter.
        guard plaintext[i] == 0x02 else {
            throw Error.badPadding
        }

        // Content is everything before delimiter.
        return plaintext.prefix(i)
    }

    private static func randomBytes(count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed: \(status)")
        return Data(bytes)
    }

    /// RFC 4648 base64url without padding
    private static func base64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// Decodes RFC 4648 base64url (with or without padding)
    private static func base64urlDecode(_ string: String) -> Data? {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        // Add padding if needed
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        return Data(base64Encoded: base64)
    }

}
