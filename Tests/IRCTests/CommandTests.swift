import XCTest

@testable import IRC

final class CommandTests: XCTestCase {

    // MARK: - Connection Registration

    func testPassCommand() {
        let cmd = Command.pass("secret123")
        XCTAssertEqual(cmd.encode(), "PASS secret123")
    }

    func testNickCommand() {
        let cmd = Command.nick("TestBot")
        XCTAssertEqual(cmd.encode(), "NICK TestBot")
    }

    func testUserCommand() {
        let cmd = Command.user(username: "testuser", mode: 0, realname: "Test User")
        XCTAssertEqual(cmd.encode(), "USER testuser 0 * :Test User")
    }

    func testUserCommandWithMode() {
        let cmd = Command.user(username: "testuser", mode: 8, realname: "Test User")
        XCTAssertEqual(cmd.encode(), "USER testuser 8 * :Test User")
    }

    func testQuitWithoutMessage() {
        let cmd = Command.quit()
        XCTAssertEqual(cmd.encode(), "QUIT")
    }

    func testQuitWithMessage() {
        let cmd = Command.quit("Goodbye!")
        XCTAssertEqual(cmd.encode(), "QUIT :Goodbye!")
    }

    // MARK: - CAP Negotiation

    func testCapLS() {
        let cmd = Command.cap("LS", ["302"])
        XCTAssertEqual(cmd.encode(), "CAP LS :302")
    }

    func testCapREQ() {
        let cmd = Command.cap("REQ", ["sasl", "multi-prefix"])
        XCTAssertEqual(cmd.encode(), "CAP REQ :sasl multi-prefix")
    }

    func testCapWithoutArgs() {
        let cmd = Command.cap("LIST")
        XCTAssertEqual(cmd.encode(), "CAP LIST")
    }

    func testCapEnd() {
        let cmd = Command.capEnd
        XCTAssertEqual(cmd.encode(), "CAP END")
    }

    // MARK: - SASL Authentication

    func testAuthenticateCommand() {
        let cmd = Command.authenticate("PLAIN")
        XCTAssertEqual(cmd.encode(), "AUTHENTICATE PLAIN")
    }

    func testAuthenticateBase64() {
        let cmd = Command.authenticate("dGVzdAB0ZXN0AHBhc3N3b3Jk")
        XCTAssertEqual(cmd.encode(), "AUTHENTICATE dGVzdAB0ZXN0AHBhc3N3b3Jk")
    }

    func testAuthPlainHelper() {
        let cmd = Command.authPlain(username: "testuser", password: "testpass")
        let encoded = cmd.encode()

        XCTAssertTrue(encoded.hasPrefix("AUTHENTICATE "))

        // Verify base64 encoding
        let base64Part = encoded.dropFirst("AUTHENTICATE ".count)
        if let decoded = Data(base64Encoded: String(base64Part)),
            let decodedString = String(data: decoded, encoding: .utf8)
        {
            XCTAssertEqual(decodedString, "\0testuser\0testpass")
        } else {
            XCTFail("Failed to decode SASL PLAIN")
        }
    }

    // MARK: - Channel Operations

    func testJoinChannel() {
        let cmd = Command.join("#test")
        XCTAssertEqual(cmd.encode(), "JOIN #test")
    }

    func testJoinChannelWithKey() {
        let cmd = Command.join("#private", key: "secret")
        XCTAssertEqual(cmd.encode(), "JOIN #private secret")
    }

    func testPartChannel() {
        let cmd = Command.part("#test")
        XCTAssertEqual(cmd.encode(), "PART #test")
    }

    func testPartChannelWithReason() {
        let cmd = Command.part("#test", reason: "Going away")
        XCTAssertEqual(cmd.encode(), "PART #test :Going away")
    }

    func testTopicGet() {
        let cmd = Command.topic("#test")
        XCTAssertEqual(cmd.encode(), "TOPIC #test")
    }

    func testTopicSet() {
        let cmd = Command.topic("#test", newTopic: "New channel topic")
        XCTAssertEqual(cmd.encode(), "TOPIC #test :New channel topic")
    }

    func testNamesChannel() {
        let cmd = Command.names("#test")
        XCTAssertEqual(cmd.encode(), "NAMES #test")
    }

    func testListAll() {
        let cmd = Command.list()
        XCTAssertEqual(cmd.encode(), "LIST")
    }

    func testListSpecific() {
        let cmd = Command.list("#test")
        XCTAssertEqual(cmd.encode(), "LIST #test")
    }

    func testInvite() {
        let cmd = Command.invite(nick: "friend", channel: "#private")
        XCTAssertEqual(cmd.encode(), "INVITE friend #private")
    }

    func testKickWithoutReason() {
        let cmd = Command.kick(channel: "#test", nick: "baduser")
        XCTAssertEqual(cmd.encode(), "KICK #test baduser")
    }

    func testKickWithReason() {
        let cmd = Command.kick(channel: "#test", nick: "baduser", reason: "Spam")
        XCTAssertEqual(cmd.encode(), "KICK #test baduser :Spam")
    }

    // MARK: - Messaging

    func testPrivmsg() {
        let cmd = Command.privmsg("#channel", "Hello, world!")
        XCTAssertEqual(cmd.encode(), "PRIVMSG #channel :Hello, world!")
    }

    func testPrivmsgPrivate() {
        let cmd = Command.privmsg("user", "Private message")
        XCTAssertEqual(cmd.encode(), "PRIVMSG user :Private message")
    }

    func testNotice() {
        let cmd = Command.notice("#channel", "Notice message")
        XCTAssertEqual(cmd.encode(), "NOTICE #channel :Notice message")
    }

    func testPrivmsgWithSpecialCharacters() {
        let cmd = Command.privmsg("#test", "Message with émojis 🎉 and unicode ñ")
        XCTAssertEqual(cmd.encode(), "PRIVMSG #test :Message with émojis 🎉 and unicode ñ")
    }

    // MARK: - Modes

    func testModeGet() {
        let cmd = Command.mode(target: "#channel")
        XCTAssertEqual(cmd.encode(), "MODE #channel")
    }

    func testModeSet() {
        let cmd = Command.mode(target: "#channel", modes: "+m")
        XCTAssertEqual(cmd.encode(), "MODE #channel +m")
    }

    func testModeSetWithArgs() {
        let cmd = Command.mode(target: "#channel", modes: "+o nick")
        XCTAssertEqual(cmd.encode(), "MODE #channel +o nick")
    }

    func testUserMode() {
        let cmd = Command.mode(target: "MyNick", modes: "+i")
        XCTAssertEqual(cmd.encode(), "MODE MyNick +i")
    }

    // MARK: - User Queries

    func testWhois() {
        let cmd = Command.whois("targetuser")
        XCTAssertEqual(cmd.encode(), "WHOIS targetuser")
    }

    func testWhowas() {
        let cmd = Command.whowas("olduser")
        XCTAssertEqual(cmd.encode(), "WHOWAS olduser")
    }

    func testWhowasWithCount() {
        let cmd = Command.whowas("olduser", count: 5)
        XCTAssertEqual(cmd.encode(), "WHOWAS olduser 5")
    }

    func testWho() {
        let cmd = Command.who("#channel")
        XCTAssertEqual(cmd.encode(), "WHO #channel")
    }

    func testWhoOpOnly() {
        let cmd = Command.who("#channel", opOnly: true)
        XCTAssertEqual(cmd.encode(), "WHO #channel o")
    }

    func testIson() {
        let cmd = Command.ison(["user1", "user2", "user3"])
        XCTAssertEqual(cmd.encode(), "ISON user1 user2 user3")
    }

    func testUserhostSingle() {
        let cmd = Command.userhost(["user1"])
        XCTAssertEqual(cmd.encode(), "USERHOST user1")
    }

    func testUserhostMultiple() {
        let cmd = Command.userhost(["user1", "user2"])
        XCTAssertEqual(cmd.encode(), "USERHOST user1 user2")
    }

    // MARK: - Server Queries

    func testPing() {
        let cmd = Command.ping("server.name")
        XCTAssertEqual(cmd.encode(), "PING :server.name")
    }

    func testPong() {
        let cmd = Command.pong("server.name")
        XCTAssertEqual(cmd.encode(), "PONG :server.name")
    }

    func testMotd() {
        let cmd = Command.motd()
        XCTAssertEqual(cmd.encode(), "MOTD")
    }

    func testMotdServer() {
        let cmd = Command.motd("server.name")
        XCTAssertEqual(cmd.encode(), "MOTD server.name")
    }

    func testVersion() {
        let cmd = Command.version()
        XCTAssertEqual(cmd.encode(), "VERSION")
    }

    func testVersionServer() {
        let cmd = Command.version("server.name")
        XCTAssertEqual(cmd.encode(), "VERSION server.name")
    }

    func testTime() {
        let cmd = Command.time()
        XCTAssertEqual(cmd.encode(), "TIME")
    }

    func testTimeServer() {
        let cmd = Command.time("server.name")
        XCTAssertEqual(cmd.encode(), "TIME server.name")
    }

    func testAdmin() {
        let cmd = Command.admin()
        XCTAssertEqual(cmd.encode(), "ADMIN")
    }

    func testAdminServer() {
        let cmd = Command.admin("server.name")
        XCTAssertEqual(cmd.encode(), "ADMIN server.name")
    }

    func testInfo() {
        let cmd = Command.info()
        XCTAssertEqual(cmd.encode(), "INFO")
    }

    func testInfoServer() {
        let cmd = Command.info("server.name")
        XCTAssertEqual(cmd.encode(), "INFO server.name")
    }

    func testStats() {
        let cmd = Command.stats()
        XCTAssertEqual(cmd.encode(), "STATS")
    }

    func testStatsQuery() {
        let cmd = Command.stats(query: "u")
        XCTAssertEqual(cmd.encode(), "STATS u")
    }

    func testStatsQueryServer() {
        let cmd = Command.stats(query: "u", server: "server.name")
        XCTAssertEqual(cmd.encode(), "STATS u server.name")
    }

    // MARK: - User State

    func testAwaySet() {
        let cmd = Command.away("Be right back")
        XCTAssertEqual(cmd.encode(), "AWAY :Be right back")
    }

    func testAwayClear() {
        let cmd = Command.away()
        XCTAssertEqual(cmd.encode(), "AWAY")
    }

    // MARK: - Raw Command

    func testRawCommand() {
        let cmd = Command.raw("CUSTOM command with args :and trailing")
        XCTAssertEqual(cmd.encode(), "CUSTOM command with args :and trailing")
    }

    func testRawCommandPreservesFormatting() {
        let cmd = Command.raw("MODE #channel +b *!*@*.example.com")
        XCTAssertEqual(cmd.encode(), "MODE #channel +b *!*@*.example.com")
    }

    // MARK: - Edge Cases

    func testEmptyTrailingParameter() {
        let cmd = Command.privmsg("#channel", "")
        XCTAssertEqual(cmd.encode(), "PRIVMSG #channel :")
    }

    func testMessageWithColons() {
        let cmd = Command.privmsg("#channel", "Time is 12:30:45")
        XCTAssertEqual(cmd.encode(), "PRIVMSG #channel :Time is 12:30:45")
    }

    func testMessageWithNewlines() {
        let cmd = Command.privmsg("#channel", "Line 1\nLine 2")
        // IRC doesn't support multiline messages, but we encode as-is
        XCTAssertEqual(cmd.encode(), "PRIVMSG #channel :Line 1\nLine 2")
    }

    func testChannelNameVariations() {
        XCTAssertEqual(Command.join("#test").encode(), "JOIN #test")
        XCTAssertEqual(Command.join("&local").encode(), "JOIN &local")
        XCTAssertEqual(Command.join("!12345").encode(), "JOIN !12345")
        XCTAssertEqual(Command.join("+modeless").encode(), "JOIN +modeless")
    }

    func testNickWithSpecialCharacters() {
        let cmd = Command.nick("Test[Bot]")
        XCTAssertEqual(cmd.encode(), "NICK Test[Bot]")
    }

    func testLongMessage() {
        let longText = String(repeating: "a", count: 400)
        let cmd = Command.privmsg("#channel", longText)
        XCTAssertEqual(cmd.encode(), "PRIVMSG #channel :\(longText)")
    }
}
