import Foundation
import Testing

@testable import IRC

@Suite("Command Tests")
struct CommandTests {

    // MARK: - Connection Registration

    @Test("PASS command encoding")
    func passCommand() {
        let cmd = Command.pass("secret123")
        #expect(cmd.encode() == "PASS secret123")
    }

    @Test("NICK command encoding")
    func nickCommand() {
        let cmd = Command.nick("TestBot")
        #expect(cmd.encode() == "NICK TestBot")
    }

    @Test("USER command encoding")
    func userCommand() {
        let cmd = Command.user(username: "testuser", mode: 0, realname: "Test User")
        #expect(cmd.encode() == "USER testuser 0 * :Test User")
    }

    @Test("USER command with mode encoding")
    func userCommandWithMode() {
        let cmd = Command.user(username: "testuser", mode: 8, realname: "Test User")
        #expect(cmd.encode() == "USER testuser 8 * :Test User")
    }

    @Test("QUIT without message")
    func quitWithoutMessage() {
        let cmd = Command.quit()
        #expect(cmd.encode() == "QUIT")
    }

    @Test("QUIT with message")
    func quitWithMessage() {
        let cmd = Command.quit("Goodbye!")
        #expect(cmd.encode() == "QUIT :Goodbye!")
    }

    // MARK: - CAP Negotiation

    @Test("CAP LS encoding")
    func capLS() {
        let cmd = Command.cap("LS", ["302"])
        #expect(cmd.encode() == "CAP LS :302")
    }

    @Test("CAP REQ encoding")
    func capREQ() {
        let cmd = Command.cap("REQ", ["sasl", "multi-prefix"])
        #expect(cmd.encode() == "CAP REQ :sasl multi-prefix")
    }

    @Test("CAP without args")
    func capWithoutArgs() {
        let cmd = Command.cap("LIST")
        #expect(cmd.encode() == "CAP LIST")
    }

    @Test("CAP END encoding")
    func capEnd() {
        let cmd = Command.capEnd
        #expect(cmd.encode() == "CAP END")
    }

    // MARK: - SASL Authentication

    @Test("AUTHENTICATE command")
    func authenticateCommand() {
        let cmd = Command.authenticate("PLAIN")
        #expect(cmd.encode() == "AUTHENTICATE PLAIN")
    }

    @Test("AUTHENTICATE with base64")
    func authenticateBase64() {
        let cmd = Command.authenticate("dGVzdAB0ZXN0AHBhc3N3b3Jk")
        #expect(cmd.encode() == "AUTHENTICATE dGVzdAB0ZXN0AHBhc3N3b3Jk")
    }

    @Test("AUTH PLAIN helper")
    func authPlainHelper() {
        let cmd = Command.authPlain(username: "testuser", password: "testpass")
        let encoded = cmd.encode()

        #expect(encoded.hasPrefix("AUTHENTICATE "))

        // Verify base64 encoding
        let base64Part = encoded.dropFirst("AUTHENTICATE ".count)
        if let decoded = Data(base64Encoded: String(base64Part)),
            let decodedString = String(data: decoded, encoding: .utf8)
        {
            #expect(decodedString == "\0testuser\0testpass")
        } else {
            Issue.record("Failed to decode SASL PLAIN")
        }
    }

    // MARK: - Channel Operations

    @Test("JOIN channel")
    func joinChannel() {
        let cmd = Command.join("#test")
        #expect(cmd.encode() == "JOIN #test")
    }

    @Test("JOIN channel with key")
    func joinChannelWithKey() {
        let cmd = Command.join("#private", key: "secret")
        #expect(cmd.encode() == "JOIN #private secret")
    }

    @Test("PART channel")
    func partChannel() {
        let cmd = Command.part("#test")
        #expect(cmd.encode() == "PART #test")
    }

    @Test("PART channel with reason")
    func partChannelWithReason() {
        let cmd = Command.part("#test", reason: "Going away")
        #expect(cmd.encode() == "PART #test :Going away")
    }

    @Test("TOPIC get")
    func topicGet() {
        let cmd = Command.topic("#test")
        #expect(cmd.encode() == "TOPIC #test")
    }

    @Test("TOPIC set")
    func topicSet() {
        let cmd = Command.topic("#test", newTopic: "New channel topic")
        #expect(cmd.encode() == "TOPIC #test :New channel topic")
    }

    @Test("NAMES channel")
    func namesChannel() {
        let cmd = Command.names("#test")
        #expect(cmd.encode() == "NAMES #test")
    }

    @Test("LIST all channels")
    func listAll() {
        let cmd = Command.list()
        #expect(cmd.encode() == "LIST")
    }

    @Test("LIST specific channel")
    func listSpecific() {
        let cmd = Command.list("#test")
        #expect(cmd.encode() == "LIST #test")
    }

    @Test("INVITE user to channel")
    func invite() {
        let cmd = Command.invite(nick: "friend", channel: "#private")
        #expect(cmd.encode() == "INVITE friend #private")
    }

    @Test("KICK without reason")
    func kickWithoutReason() {
        let cmd = Command.kick(channel: "#test", nick: "baduser")
        #expect(cmd.encode() == "KICK #test baduser")
    }

    @Test("KICK with reason")
    func kickWithReason() {
        let cmd = Command.kick(channel: "#test", nick: "baduser", reason: "Spam")
        #expect(cmd.encode() == "KICK #test baduser :Spam")
    }

    // MARK: - Messaging

    @Test("PRIVMSG to channel")
    func privmsg() {
        let cmd = Command.privmsg("#channel", "Hello, world!")
        #expect(cmd.encode() == "PRIVMSG #channel :Hello, world!")
    }

    @Test("PRIVMSG to user")
    func privmsgPrivate() {
        let cmd = Command.privmsg("user", "Private message")
        #expect(cmd.encode() == "PRIVMSG user :Private message")
    }

    @Test("NOTICE encoding")
    func notice() {
        let cmd = Command.notice("#channel", "Notice message")
        #expect(cmd.encode() == "NOTICE #channel :Notice message")
    }

    @Test("PRIVMSG with special characters")
    func privmsgWithSpecialCharacters() {
        let cmd = Command.privmsg("#test", "Message with émojis 🎉 and unicode ñ")
        #expect(cmd.encode() == "PRIVMSG #test :Message with émojis 🎉 and unicode ñ")
    }

    // MARK: - Modes

    @Test("MODE get")
    func modeGet() {
        let cmd = Command.mode(target: "#channel")
        #expect(cmd.encode() == "MODE #channel")
    }

    @Test("MODE set")
    func modeSet() {
        let cmd = Command.mode(target: "#channel", modes: "+m")
        #expect(cmd.encode() == "MODE #channel +m")
    }

    @Test("MODE set with args")
    func modeSetWithArgs() {
        let cmd = Command.mode(target: "#channel", modes: "+o nick")
        #expect(cmd.encode() == "MODE #channel +o nick")
    }

    @Test("User MODE")
    func userMode() {
        let cmd = Command.mode(target: "MyNick", modes: "+i")
        #expect(cmd.encode() == "MODE MyNick +i")
    }

    // MARK: - User Queries

    @Test("WHOIS query")
    func whois() {
        let cmd = Command.whois("targetuser")
        #expect(cmd.encode() == "WHOIS targetuser")
    }

    @Test("WHOWAS query")
    func whowas() {
        let cmd = Command.whowas("olduser")
        #expect(cmd.encode() == "WHOWAS olduser")
    }

    @Test("WHOWAS with count")
    func whowasWithCount() {
        let cmd = Command.whowas("olduser", count: 5)
        #expect(cmd.encode() == "WHOWAS olduser 5")
    }

    @Test("WHO query")
    func who() {
        let cmd = Command.who("#channel")
        #expect(cmd.encode() == "WHO #channel")
    }

    @Test("WHO with operator only filter")
    func whoOpOnly() {
        let cmd = Command.who("#channel", opOnly: true)
        #expect(cmd.encode() == "WHO #channel o")
    }

    @Test("ISON query")
    func ison() {
        let cmd = Command.ison(["user1", "user2", "user3"])
        #expect(cmd.encode() == "ISON user1 user2 user3")
    }

    @Test("USERHOST single user")
    func userhostSingle() {
        let cmd = Command.userhost(["user1"])
        #expect(cmd.encode() == "USERHOST user1")
    }

    @Test("USERHOST multiple users")
    func userhostMultiple() {
        let cmd = Command.userhost(["user1", "user2"])
        #expect(cmd.encode() == "USERHOST user1 user2")
    }

    // MARK: - Server Queries

    @Test("PING command")
    func ping() {
        let cmd = Command.ping("server.name")
        #expect(cmd.encode() == "PING :server.name")
    }

    @Test("PONG command")
    func pong() {
        let cmd = Command.pong("server.name")
        #expect(cmd.encode() == "PONG :server.name")
    }

    @Test("MOTD default")
    func motd() {
        let cmd = Command.motd()
        #expect(cmd.encode() == "MOTD")
    }

    @Test("MOTD for server")
    func motdServer() {
        let cmd = Command.motd("server.name")
        #expect(cmd.encode() == "MOTD server.name")
    }

    @Test("VERSION default")
    func version() {
        let cmd = Command.version()
        #expect(cmd.encode() == "VERSION")
    }

    @Test("VERSION for server")
    func versionServer() {
        let cmd = Command.version("server.name")
        #expect(cmd.encode() == "VERSION server.name")
    }

    @Test("TIME default")
    func time() {
        let cmd = Command.time()
        #expect(cmd.encode() == "TIME")
    }

    @Test("TIME for server")
    func timeServer() {
        let cmd = Command.time("server.name")
        #expect(cmd.encode() == "TIME server.name")
    }

    @Test("ADMIN default")
    func admin() {
        let cmd = Command.admin()
        #expect(cmd.encode() == "ADMIN")
    }

    @Test("ADMIN for server")
    func adminServer() {
        let cmd = Command.admin("server.name")
        #expect(cmd.encode() == "ADMIN server.name")
    }

    @Test("INFO default")
    func info() {
        let cmd = Command.info()
        #expect(cmd.encode() == "INFO")
    }

    @Test("INFO for server")
    func infoServer() {
        let cmd = Command.info("server.name")
        #expect(cmd.encode() == "INFO server.name")
    }

    @Test("STATS default")
    func stats() {
        let cmd = Command.stats()
        #expect(cmd.encode() == "STATS")
    }

    @Test("STATS with query")
    func statsQuery() {
        let cmd = Command.stats(query: "u")
        #expect(cmd.encode() == "STATS u")
    }

    @Test("STATS with query and server")
    func statsQueryServer() {
        let cmd = Command.stats(query: "u", server: "server.name")
        #expect(cmd.encode() == "STATS u server.name")
    }

    // MARK: - User State

    @Test("AWAY set message")
    func awaySet() {
        let cmd = Command.away("Be right back")
        #expect(cmd.encode() == "AWAY :Be right back")
    }

    @Test("AWAY clear")
    func awayClear() {
        let cmd = Command.away()
        #expect(cmd.encode() == "AWAY")
    }

    // MARK: - Raw Command

    @Test("Raw command encoding")
    func rawCommand() {
        let cmd = Command.raw("CUSTOM command with args :and trailing")
        #expect(cmd.encode() == "CUSTOM command with args :and trailing")
    }

    @Test("Raw command preserves formatting")
    func rawCommandPreservesFormatting() {
        let cmd = Command.raw("MODE #channel +b *!*@*.example.com")
        #expect(cmd.encode() == "MODE #channel +b *!*@*.example.com")
    }

    // MARK: - Edge Cases

    @Test("Empty trailing parameter")
    func emptyTrailingParameter() {
        let cmd = Command.privmsg("#channel", "")
        #expect(cmd.encode() == "PRIVMSG #channel :")
    }

    @Test("Message with colons")
    func messageWithColons() {
        let cmd = Command.privmsg("#channel", "Time is 12:30:45")
        #expect(cmd.encode() == "PRIVMSG #channel :Time is 12:30:45")
    }

    @Test("Message with newlines")
    func messageWithNewlines() {
        let cmd = Command.privmsg("#channel", "Line 1\nLine 2")
        // IRC doesn't support multiline messages, but we encode as-is
        #expect(cmd.encode() == "PRIVMSG #channel :Line 1\nLine 2")
    }

    @Test("Channel name variations")
    func channelNameVariations() {
        #expect(Command.join("#test").encode() == "JOIN #test")
        #expect(Command.join("&local").encode() == "JOIN &local")
        #expect(Command.join("!12345").encode() == "JOIN !12345")
        #expect(Command.join("+modeless").encode() == "JOIN +modeless")
    }

    @Test("Nick with special characters")
    func nickWithSpecialCharacters() {
        let cmd = Command.nick("Test[Bot]")
        #expect(cmd.encode() == "NICK Test[Bot]")
    }

    @Test("Long message encoding")
    func longMessage() {
        let longText = String(repeating: "a", count: 400)
        let cmd = Command.privmsg("#channel", longText)
        #expect(cmd.encode() == "PRIVMSG #channel :\(longText)")
    }
}
