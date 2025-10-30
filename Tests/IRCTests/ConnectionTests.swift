import Foundation
import Testing

@testable import IRC

@Suite("Connection Tests")
struct ConnectionTests {

    // MARK: - Basic Handshake (No CAP, No SASL)

    @Test("Basic handshake without capabilities")
    func basicHandshake() async throws {
        let transport = MockTransport()
        let config = Client.Config(
            server: "irc.example.com",
            port: 6667,
            useTLS: false,
            nick: "TestBot",
            username: "testuser",
            realname: "Test User"
        )
        let client = Client(config: config, transport: transport)
        let clientConnectTask = Task { try await client.connect() }
        try await Task.sleep(for: .milliseconds(500))

        // Verify NICK and USER were sent
        let written = await transport.getWrittenLines()
        #expect(written.contains("NICK TestBot"))
        #expect(written.contains("USER testuser 0 * :Test User"))

        // Simulate server welcome message (001)
        await transport.queueRead(":server 001 TestBot :Welcome to the network")

        // Wait for registration
        try await Task.sleep(for: .milliseconds(500))

        // Verify state is registered
        let state = await client.getState()
        #expect(state == .registered)

        // Cleanup
        try await client.disconnect()
        clientConnectTask.cancel()
    }

    @Test("Handshake with server password")
    func handshakeWithPassword() async throws {
        let transport = MockTransport()
        let config = Client.Config(
            server: "irc.example.com",
            port: 6667,
            useTLS: false,
            nick: "TestBot",
            password: "serverpass123"
        )
        let client = Client(config: config, transport: transport)
        let clientConnectTask = Task {
            try await client.connect()
        }
        try await Task.sleep(for: .milliseconds(500))

        // Verify PASS was sent before NICK and USER
        let written = await transport.getWrittenLines()
        let passIndex = written.firstIndex(of: "PASS serverpass123")
        let nickIndex = written.firstIndex(of: "NICK TestBot")

        #expect(passIndex != nil)
        #expect(nickIndex != nil)
        if let passIdx = passIndex, let nickIdx = nickIndex {
            #expect(passIdx < nickIdx)
        }

        // Complete registration
        await transport.queueRead(":server 001 TestBot :Welcome")
        try await Task.sleep(for: .milliseconds(500))

        try await client.disconnect()
        clientConnectTask.cancel()
    }

    // MARK: - CAP Negotiation

    @Test("CAP negotiation without SASL")
    func capNegotiationBasic() async throws {
        let transport = MockTransport()
        let config = Client.Config(
            server: "irc.example.com",
            nick: "TestBot",
            requestedCaps: ["multi-prefix", "account-notify"]
        )
        let client = Client(config: config, transport: transport)
        let clientConnectTask = Task {
            try await client.connect()
        }
        try await Task.sleep(for: .milliseconds(500))

        // Verify CAP LS was sent
        let written = await transport.getWrittenLines()
        #expect(written.contains("CAP LS 302"))

        // Simulate server CAP LS response
        await transport.queueRead(
            ":server CAP * LS :multi-prefix extended-join account-notify account-tag"
        )
        try await Task.sleep(for: .milliseconds(500))

        // Verify CAP REQ was sent with requested caps that are available
        let writtenAfterLS = await transport.getWrittenLines()
        let capReq = writtenAfterLS.first { $0.hasPrefix("CAP REQ") }
        #expect(capReq != nil)
        #expect(capReq?.contains("multi-prefix") ?? false)
        #expect(capReq?.contains("account-notify") ?? false)

        // Simulate server CAP ACK
        await transport.queueRead(":server CAP * ACK :multi-prefix account-notify")
        try await Task.sleep(for: .milliseconds(500))

        // Verify NICK, USER, and CAP END were sent
        let finalWritten = await transport.getWrittenLines()
        #expect(finalWritten.contains("NICK TestBot"))
        #expect(finalWritten.contains { $0.hasPrefix("USER TestBot") })
        #expect(finalWritten.contains("CAP END"))

        // Complete registration
        await transport.queueRead(":server 001 TestBot :Welcome")
        try await Task.sleep(for: .milliseconds(500))

        let state = await client.getState()
        #expect(state == .registered)

        try await client.disconnect()
        clientConnectTask.cancel()
    }

    @Test("CAP negotiation with multiline response")
    func capNegotiationMultiline() async throws {
        let transport = MockTransport()
        let config = Client.Config(
            server: "irc.example.com",
            nick: "TestBot",
            requestedCaps: ["sasl"]
        )
        let client = Client(config: config, transport: transport)
        let clientConnectTask = Task {
            try await client.connect()
        }
        try await Task.sleep(nanoseconds: 50_000_000)

        // Simulate multiline CAP LS (using * as continuation indicator)
        await transport.queueRead(":server CAP * LS * :multi-prefix extended-join account-notify")
        await transport.queueRead(":server CAP * LS :account-tag message-tags sasl")
        try await Task.sleep(nanoseconds: 50_000_000)

        // Verify CAP REQ was sent after multiline completed
        let written = await transport.getWrittenLines()
        let capReq = written.first { $0.hasPrefix("CAP REQ") }
        #expect(capReq?.contains("sasl") ?? false)

        try await client.disconnect()
        clientConnectTask.cancel()
    }

    // MARK: - SASL Authentication

    @Test("SASL PLAIN authentication")
    func saslPlainAuth() async throws {
        let transport = MockTransport()
        let config = Client.Config(
            server: "irc.example.com",
            nick: "TestBot",
            sasl: .plain(username: "authuser", password: "authpass"),
            requestedCaps: ["sasl"]
        )
        let client = Client(config: config, transport: transport)
        let clientConnectTask = Task {
            try await client.connect()
        }
        try await Task.sleep(for: .milliseconds(500))

        // Verify CAP LS was sent (required for SASL)
        let written = await transport.getWrittenLines()
        #expect(written.contains("CAP LS 302"))

        // Simulate server supports SASL
        await transport.queueRead(":server CAP * LS :sasl multi-prefix account-notify")
        try await Task.sleep(for: .milliseconds(500))

        // Verify CAP REQ for sasl
        let afterLS = await transport.getWrittenLines()
        #expect(afterLS.contains { $0.contains("CAP REQ") && $0.contains("sasl") })

        // Simulate server ACK
        await transport.queueRead(":server CAP * ACK :sasl")
        try await Task.sleep(for: .milliseconds(500))

        // Verify AUTHENTICATE PLAIN was sent
        let afterACK = await transport.getWrittenLines()
        #expect(afterACK.contains("AUTHENTICATE PLAIN"))

        // Simulate server ready for credentials
        await transport.queueRead(":server AUTHENTICATE +")
        try await Task.sleep(for: .milliseconds(500))

        // Verify base64 credentials were sent
        let afterPlus = await transport.getWrittenLines()
        let authLine = afterPlus.first {
            $0.hasPrefix("AUTHENTICATE ") && $0 != "AUTHENTICATE PLAIN"
        }
        #expect(authLine != nil)

        // Verify base64 encoding is correct
        if let authLine = authLine {
            let base64Part = authLine.dropFirst("AUTHENTICATE ".count)
            if let decoded = Data(base64Encoded: String(base64Part)),
                let decodedString = String(data: decoded, encoding: .utf8)
            {
                #expect(decodedString == "\0authuser\0authpass")
            }
        }

        // Simulate SASL success
        await transport.queueRead(":server 903 * :SASL authentication successful")
        try await Task.sleep(for: .milliseconds(500))

        // Verify NICK, USER, and CAP END were sent after SASL success
        let afterSASL = await transport.getWrittenLines()
        #expect(afterSASL.contains("NICK TestBot"))
        #expect(afterSASL.contains("USER TestBot 0 * :TestBot"))
        #expect(afterSASL.contains("CAP END"))

        // Complete registration
        await transport.queueRead(":server 001 TestBot :Welcome")
        try await Task.sleep(for: .milliseconds(500))

        let state = await client.getState()
        #expect(state == .registered)

        try await client.disconnect()
        clientConnectTask.cancel()
    }

    @Test("SASL EXTERNAL authentication")
    func saslExternalAuth() async throws {
        let transport = MockTransport()
        let config = Client.Config(
            server: "irc.example.com",
            nick: "TestBot",
            sasl: .external,
            requestedCaps: ["sasl"]
        )
        let client = Client(config: config, transport: transport)
        let clientConnectTask = Task {
            try await client.connect()
        }
        try await Task.sleep(for: .milliseconds(500))

        // Simulate CAP LS and ACK
        await transport.queueRead(":server CAP * LS :sasl")
        try await Task.sleep(for: .milliseconds(500))
        await transport.queueRead(":server CAP * ACK :sasl")
        try await Task.sleep(for: .milliseconds(500))

        // Verify AUTHENTICATE EXTERNAL was sent
        let written = await transport.getWrittenLines()
        #expect(written.contains("AUTHENTICATE EXTERNAL"))
        #expect(written.contains("AUTHENTICATE +"))

        // Simulate SASL success
        await transport.queueRead(":server 903 * :SASL authentication successful")
        try await Task.sleep(for: .milliseconds(500))

        // Complete registration
        await transport.queueRead(":server 001 TestBot :Welcome")
        try await Task.sleep(for: .milliseconds(500))

        let state = await client.getState()
        #expect(state == .registered)

        try await client.disconnect()
        clientConnectTask.cancel()
    }

    @Test("SASL authentication failure")
    func saslAuthFailure() async throws {
        let transport = MockTransport()
        let config = Client.Config(
            server: "irc.example.com",
            nick: "TestBot",
            sasl: .plain(username: "baduser", password: "badpass"),
            requestedCaps: ["sasl"]
        )
        let client = Client(config: config, transport: transport)

        actor ErrorTracker {
            var errorReceived = false

            func setError() {
                errorReceived = true
            }

            func hasError() -> Bool {
                return errorReceived
            }
        }
        let errorTracker = ErrorTracker()
        let eventsTask = Task {
            for await event in await client.events {
                if case .error(let msg) = event, msg.contains("SASL") {
                    await errorTracker.setError()
                }
            }
        }

        let clientConnectTask = Task {
            try await client.connect()
        }
        try await Task.sleep(for: .milliseconds(500))

        // Simulate CAP negotiation
        await transport.queueRead(":server CAP * LS :sasl")
        try await Task.sleep(for: .milliseconds(500))
        await transport.queueRead(":server CAP * ACK :sasl")
        try await Task.sleep(for: .milliseconds(500))
        await transport.queueRead(":server AUTHENTICATE +")
        try await Task.sleep(for: .milliseconds(500))

        // Simulate SASL failure (904)
        await transport.queueRead(":server 904 * :SASL authentication failed")
        try await Task.sleep(for: .milliseconds(500))

        // Verify error event was emitted
        let hasError = await errorTracker.hasError()
        #expect(hasError)

        // Verify client still sent NICK/USER and CAP END to continue registration
        let written = await transport.getWrittenLines()
        #expect(written.contains("NICK TestBot"))
        #expect(written.contains("CAP END"))

        // Complete registration (server allows it)
        await transport.queueRead(":server 001 TestBot :Welcome")
        try await Task.sleep(for: .milliseconds(500))

        let state = await client.getState()
        #expect(state == .registered)

        try await client.disconnect()
        clientConnectTask.cancel()
        eventsTask.cancel()
    }

    // MARK: - Error Handling

    @Test("Nickname in use during registration")
    func nicknameInUse() async throws {
        let transport = MockTransport()
        let config = Client.Config(
            server: "irc.example.com",
            nick: "TakenNick"
        )
        let client = Client(config: config, transport: transport)
        let clientConnectTask = Task {
            try await client.connect()
        }
        try await Task.sleep(for: .milliseconds(500))

        // Verify initial NICK was sent
        let written = await transport.getWrittenLines()
        #expect(written.contains("NICK TakenNick"))

        // Simulate nick in use error (433)
        await transport.queueRead(":server 433 * TakenNick :Nickname is already in use")
        try await Task.sleep(for: .milliseconds(500))

        // Verify client tried alternate nick
        let afterError = await transport.getWrittenLines()
        #expect(afterError.contains("NICK TakenNick_"))

        // Complete registration with alternate nick
        await transport.queueRead(":server 001 TakenNick_ :Welcome")
        try await Task.sleep(for: .milliseconds(500))

        let state = await client.getState()
        #expect(state == .registered)

        let currentNick = await client.getCurrentNick()
        #expect(currentNick == "TakenNick_")

        try await client.disconnect()
        clientConnectTask.cancel()
    }

    @Test("CAP NAK - server rejects capabilities")
    func capNAK() async throws {
        let transport = MockTransport()
        let config = Client.Config(
            server: "irc.example.com",
            nick: "TestBot",
            requestedCaps: ["unsupported-cap"]
        )
        let client = Client(config: config, transport: transport)
        let clientConnectTask = Task {
            try await client.connect()
        }
        try await Task.sleep(for: .milliseconds(500))

        // Simulate CAP LS with no matching caps
        await transport.queueRead(":server CAP * LS :multi-prefix account-notify")
        try await Task.sleep(for: .milliseconds(500))

        // Simulate CAP NAK
        await transport.queueRead(":server CAP * NAK :unsupported-cap")
        try await Task.sleep(for: .milliseconds(500))

        // Verify client sent NICK/USER and CAP END anyway
        let afterNAK = await transport.getWrittenLines()
        #expect(afterNAK.contains("NICK TestBot"))
        #expect(afterNAK.contains("CAP END"))

        // Complete registration
        await transport.queueRead(":server 001 TestBot :Welcome")
        try await Task.sleep(for: .milliseconds(500))

        let state = await client.getState()
        #expect(state == .registered)

        try await client.disconnect()
        clientConnectTask.cancel()
    }

    // MARK: - Complete Handshake Flow

    @Test("Complete handshake with all features")
    func completeHandshake() async throws {
        let transport = MockTransport()
        let config = Client.Config(
            server: "irc.example.com",
            port: 6667,
            useTLS: false,
            nick: "TestBot",
            username: "testuser",
            realname: "Test User",
            password: "serverpass",
            sasl: .plain(username: "authuser", password: "authpass"),
            requestedCaps: ["sasl", "multi-prefix", "account-notify"]
        )
        let client = Client(config: config, transport: transport)
        let clientConnectTask = Task {
            try await client.connect()
        }
        try await Task.sleep(for: .milliseconds(500))

        // Verify initial messages
        var written = await transport.getWrittenLines()
        #expect(written.contains("CAP LS 302"))
        #expect(written.contains("PASS serverpass"))

        // Simulate CAP LS
        await transport.queueRead(":server CAP * LS :sasl multi-prefix account-notify extended-join")
        try await Task.sleep(for: .milliseconds(500))

        // Verify CAP REQ
        written = await transport.getWrittenLines()
        let capReq = written.first { $0.hasPrefix("CAP REQ") }
        #expect(capReq?.contains("sasl") ?? false)
        #expect(capReq?.contains("multi-prefix") ?? false)
        #expect(capReq?.contains("account-notify") ?? false)

        // Simulate CAP ACK
        await transport.queueRead(":server CAP * ACK :sasl multi-prefix account-notify")
        try await Task.sleep(for: .milliseconds(500))

        // Verify AUTHENTICATE PLAIN
        written = await transport.getWrittenLines()
        #expect(written.contains("AUTHENTICATE PLAIN"))

        // Simulate SASL flow
        await transport.queueRead(":server AUTHENTICATE +")
        try await Task.sleep(for: .milliseconds(500))

        // Verify credentials sent
        written = await transport.getWrittenLines()
        #expect(written.contains { $0.hasPrefix("AUTHENTICATE ") && $0 != "AUTHENTICATE PLAIN" })

        // Simulate SASL success
        await transport.queueRead(":server 903 * :SASL authentication successful")
        try await Task.sleep(for: .milliseconds(500))

        // Verify NICK, USER, CAP END sent after SASL
        written = await transport.getWrittenLines()
        #expect(written.contains("NICK TestBot"))
        #expect(written.contains { $0.hasPrefix("USER testuser") })
        #expect(written.contains("CAP END"))

        // Simulate registration complete
        await transport.queueRead(":server 001 TestBot :Welcome to the network")
        try await Task.sleep(for: .milliseconds(500))

        // Verify client is registered
        let state = await client.getState()
        #expect(state == .registered)

        try await client.disconnect()
        clientConnectTask.cancel()
    }

    // MARK: - Message Order Verification

    @Test("Verify PASS comes before NICK/USER")
    func passBeforeNickUser() async throws {
        let transport = MockTransport()
        let config = Client.Config(
            server: "irc.example.com",
            nick: "TestBot",
            password: "secret"
        )
        let client = Client(config: config, transport: transport)
        let clientConnectTask = Task {
            try await client.connect()
        }
        try await Task.sleep(for: .milliseconds(500))

        let written = await transport.getWrittenLines()

        let passIndex = written.firstIndex(of: "PASS secret")
        let nickIndex = written.firstIndex(of: "NICK TestBot")
        let userIndex = written.firstIndex { $0.hasPrefix("USER") }

        #expect(passIndex != nil)
        #expect(nickIndex != nil)
        #expect(userIndex != nil)

        if let passIdx = passIndex, let nickIdx = nickIndex, let userIdx = userIndex {
            #expect(passIdx < nickIdx)
            #expect(passIdx < userIdx)
        }

        try await client.disconnect()
        clientConnectTask.cancel()
    }
}
