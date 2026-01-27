import Foundation
import Testing
import CryptoKit

@testable import IRC

@Suite("WebPush Tests")
struct WebPushTests {

    @Test("Decrypting push")
    func decrypt() throws {
        let bodyStr = """
            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
            """
        let bodyData = Data(base64Encoded: bodyStr)!

        let privateKeyRaw = "VOwgQnpKqYoUJlu46ZoXVENkYfZjcbminrd3zWJw9gI="
        let privateKeyData = Data.fromAnyBase64(privateKeyRaw)!
        let privateKey = try P256.KeyAgreement.PrivateKey(rawRepresentation: privateKeyData)

        let authKey = Data.fromAnyBase64("pAs-2SudzJINENeFcSM4qg")!

        let decrypted = try WebPush.decrypt(
            body: bodyData,
            auth: authKey,
            privateKey: privateKey
        )

        let text = String(data: decrypted, encoding: .utf8)
        #expect(text == "@time=2026-01-26T23:47:50.604Z :nathan!~u@irj9c9y2tikz2.irc PRIVMSG #wild :hi iruvir-kelvel")
    }
}
