import XCTest

@testable import IRC

final class MessageTests: XCTestCase {

    // MARK: - Basic Parsing

    func testSimpleCommand() {
        let msg = Message.parse("PING")

        XCTAssertNil(msg.prefix)
        XCTAssertEqual(msg.command, "PING")
        XCTAssertTrue(msg.params.isEmpty)
    }

    func testCommandWithSingleParam() {
        let msg = Message.parse("PING :server.name")

        XCTAssertNil(msg.prefix)
        XCTAssertEqual(msg.command, "PING")
        XCTAssertEqual(msg.params, ["server.name"])
    }

    func testCommandWithMultipleParams() {
        let msg = Message.parse("NICK newnick 1 2 3")

        XCTAssertEqual(msg.command, "NICK")
        XCTAssertEqual(msg.params, ["newnick", "1", "2", "3"])
    }

    func testCommandWithTrailingParam() {
        let msg = Message.parse("PRIVMSG #channel :Hello world")

        XCTAssertEqual(msg.command, "PRIVMSG")
        XCTAssertEqual(msg.params.count, 2)
        XCTAssertEqual(msg.params[0], "#channel")
        XCTAssertEqual(msg.params[1], "Hello world")
        XCTAssertEqual(msg.text, "Hello world")
    }

    func testCommandWithMixedParams() {
        let msg = Message.parse("USER username 0 * :Real Name")

        XCTAssertEqual(msg.command, "USER")
        XCTAssertEqual(msg.params, ["username", "0", "*", "Real Name"])
        XCTAssertEqual(msg.text, "Real Name")
    }

    // MARK: - Prefix Parsing

    func testServerPrefix() {
        let msg = Message.parse(":server.name PING :token")

        XCTAssertEqual(msg.prefix, "server.name")
        XCTAssertEqual(msg.command, "PING")
        XCTAssertEqual(msg.params, ["token"])
        XCTAssertEqual(msg.nick, "server.name")
        XCTAssertNil(msg.user)
        XCTAssertNil(msg.host)
    }

    func testFullUserPrefix() {
        let msg = Message.parse(":nick!user@host.com PRIVMSG #channel :Hello")

        XCTAssertEqual(msg.prefix, "nick!user@host.com")
        XCTAssertEqual(msg.nick, "nick")
        XCTAssertEqual(msg.user, "user")
        XCTAssertEqual(msg.host, "host.com")
        XCTAssertEqual(msg.command, "PRIVMSG")
    }

    func testUserPrefixWithoutHost() {
        let msg = Message.parse(":nick!user PRIVMSG #channel :Hello")

        XCTAssertEqual(msg.nick, "nick")
        XCTAssertEqual(msg.user, "user")
        XCTAssertNil(msg.host)
    }

    func testNickOnlyPrefix() {
        let msg = Message.parse(":nick QUIT :Goodbye")

        XCTAssertEqual(msg.nick, "nick")
        XCTAssertNil(msg.user)
        XCTAssertNil(msg.host)
    }

    // MARK: - Tag Parsing (IRCv3)

    func testSingleTag() {
        let msg = Message.parse("@time=2024-01-01T12:00:00.000Z PRIVMSG #channel :Hello")

        XCTAssertEqual(msg.tags["time"], "2024-01-01T12:00:00.000Z")
        XCTAssertEqual(msg.command, "PRIVMSG")
    }

    func testMultipleTags() {
        let msg = Message.parse(
            "@time=2024-01-01T12:00:00.000Z;account=user123;msgid=abc123 PRIVMSG #channel :Hi")

        XCTAssertEqual(msg.tags["time"], "2024-01-01T12:00:00.000Z")
        XCTAssertEqual(msg.tags["account"], "user123")
        XCTAssertEqual(msg.tags["msgid"], "abc123")
    }

    func testTagsWithPrefix() {
        let msg = Message.parse("@account=user :nick!user@host PRIVMSG #channel :Tagged message")

        XCTAssertEqual(msg.tags["account"], "user")
        XCTAssertEqual(msg.prefix, "nick!user@host")
        XCTAssertEqual(msg.nick, "nick")
        XCTAssertEqual(msg.command, "PRIVMSG")
    }

    func testEmptyTagValue() {
        let msg = Message.parse("@flag PRIVMSG #channel :Hi")

        XCTAssertEqual(msg.tags["flag"], "")
    }

    func testTagValueEscaping() {
        // IRCv3 tag escaping: \: -> ; \s -> space \\ -> \ \r -> CR \n -> LF
        let msg = Message.parse("@key=value\\:with\\ssemicolon\\sand\\sspace PRIVMSG #channel :Hi")

        XCTAssertEqual(msg.tags["key"], "value;with semicolon and space")
    }

    // MARK: - Numeric Replies

    func testNumericReply() {
        let msg = Message.parse(":server 001 nick :Welcome to the network")

        XCTAssertTrue(msg.isNumeric)
        XCTAssertEqual(msg.numericCode, 1)
        XCTAssertEqual(msg.numericName, "RPL_WELCOME")
        XCTAssertEqual(msg.command, "001")
    }

    func testThreeDigitNumeric() {
        let msg = Message.parse(":server 353 nick = #channel :user1 user2 user3")

        XCTAssertTrue(msg.isNumeric)
        XCTAssertEqual(msg.numericCode, 353)
        XCTAssertEqual(msg.numericName, "RPL_NAMREPLY")
    }

    func testErrorNumeric() {
        let msg = Message.parse(":server 433 * nick :Nickname is already in use")

        XCTAssertTrue(msg.isNumeric)
        XCTAssertEqual(msg.numericCode, 433)
        XCTAssertEqual(msg.numericName, "ERR_NICKNAMEINUSE")
    }

    // MARK: - Specific Commands

    func testPrivmsg() {
        let msg = Message.parse(":sender!user@host PRIVMSG #channel :Hello, world!")

        XCTAssertEqual(msg.command, "PRIVMSG")
        XCTAssertEqual(msg.nick, "sender")
        XCTAssertEqual(msg.target, "#channel")
        XCTAssertEqual(msg.text, "Hello, world!")
        XCTAssertEqual(msg.channel, "#channel")
    }

    func testPrivatePrivmsg() {
        let msg = Message.parse(":sender!user@host PRIVMSG recipient :Private message")

        XCTAssertEqual(msg.target, "recipient")
        XCTAssertNil(msg.channel)  // Not a channel
    }

    func testJoin() {
        let msg = Message.parse(":user!ident@host JOIN #channel")

        XCTAssertEqual(msg.command, "JOIN")
        XCTAssertEqual(msg.nick, "user")
        XCTAssertEqual(msg.channel, "#channel")
    }

    func testJoinWithAccount() {
        let msg = Message.parse(":user!ident@host JOIN #channel account :Real Name")

        XCTAssertEqual(msg.command, "JOIN")
        XCTAssertEqual(msg.params[0], "#channel")
        XCTAssertEqual(msg.params[1], "account")
        XCTAssertEqual(msg.params[2], "Real Name")
    }

    func testPart() {
        let msg = Message.parse(":user!ident@host PART #channel :Goodbye!")

        XCTAssertEqual(msg.command, "PART")
        XCTAssertEqual(msg.channel, "#channel")
        XCTAssertEqual(msg.text, "Goodbye!")
    }

    func testPartWithoutReason() {
        let msg = Message.parse(":user!ident@host PART #channel")

        XCTAssertEqual(msg.command, "PART")
        XCTAssertEqual(msg.channel, "#channel")
        XCTAssertEqual(msg.text, "#channel")  // text returns last param even if not trailing
    }

    func testQuit() {
        let msg = Message.parse(":user!ident@host QUIT :Quit message")

        XCTAssertEqual(msg.command, "QUIT")
        XCTAssertEqual(msg.nick, "user")
        XCTAssertEqual(msg.text, "Quit message")
    }

    func testKick() {
        let msg = Message.parse(":operator!user@host KICK #channel victim :Spam")

        XCTAssertEqual(msg.command, "KICK")
        XCTAssertEqual(msg.channel, "#channel")
        XCTAssertEqual(msg.params[0], "#channel")
        XCTAssertEqual(msg.params[1], "victim")
        XCTAssertEqual(msg.text, "Spam")
    }

    func testNick() {
        let msg = Message.parse(":oldnick!user@host NICK :newnick")

        XCTAssertEqual(msg.command, "NICK")
        XCTAssertEqual(msg.nick, "oldnick")
        XCTAssertEqual(msg.params[0], "newnick")
    }

    func testTopic() {
        let msg = Message.parse(":nick!user@host TOPIC #channel :New topic here")

        XCTAssertEqual(msg.command, "TOPIC")
        XCTAssertEqual(msg.channel, "#channel")
        XCTAssertEqual(msg.text, "New topic here")
    }

    func testMode() {
        let msg = Message.parse(":op!user@host MODE #channel +o nick")

        XCTAssertEqual(msg.command, "MODE")
        XCTAssertEqual(msg.channel, "#channel")
        XCTAssertEqual(msg.params, ["#channel", "+o", "nick"])
    }

    func testNotice() {
        let msg = Message.parse(":server NOTICE * :*** Looking up your hostname")

        XCTAssertEqual(msg.command, "NOTICE")
        XCTAssertEqual(msg.target, "*")
        XCTAssertEqual(msg.text, "*** Looking up your hostname")
    }

    // MARK: - Edge Cases

    func testEmptyMessage() {
        let msg = Message.parse("")

        XCTAssertEqual(msg.command, "")
        XCTAssertTrue(msg.params.isEmpty)
    }

    func testOnlySpaces() {
        let msg = Message.parse("   ")

        XCTAssertEqual(msg.command, "")
        XCTAssertTrue(msg.params.isEmpty)
    }

    func testTrailingCRLF() {
        let msg = Message.parse("PING :server\r\n")

        XCTAssertEqual(msg.command, "PING")
        XCTAssertEqual(msg.params, ["server"])
    }

    func testColonInMiddleParam() {
        // Colon only has special meaning if it's the first character of a param
        let msg = Message.parse("MODE #channel +k pass:word")

        XCTAssertEqual(msg.params, ["#channel", "+k", "pass:word"])
    }

    func testEmptyTrailingParam() {
        let msg = Message.parse("PRIVMSG #channel :")

        XCTAssertEqual(msg.params, ["#channel", ""])
        XCTAssertEqual(msg.text, "")
    }

    func testMultipleSpacesBetweenParams() {
        let msg = Message.parse("MODE    #channel    +o    nick")

        XCTAssertEqual(msg.params, ["#channel", "+o", "nick"])
    }

    func testUnicodeInMessage() {
        let msg = Message.parse(":user!host PRIVMSG #channel :Hello 👋 世界 🌍")

        XCTAssertEqual(msg.text, "Hello 👋 世界 🌍")
    }

    // MARK: - Real World Examples

    func testLibraChatWelcome() {
        let msg = Message.parse(
            ":calcium.libera.chat 001 testbot :Welcome to the Libera.Chat Internet Relay Chat Network testbot"
        )

        XCTAssertEqual(msg.command, "001")
        XCTAssertEqual(msg.numericCode, 1)
        XCTAssertTrue(msg.params[0] == "testbot")
        XCTAssertTrue(msg.text?.contains("Welcome") ?? false)
    }

    func testLibraChatMotd() {
        let msg = Message.parse(":calcium.libera.chat 372 testbot :- Welcome to Libera Chat")

        XCTAssertEqual(msg.numericCode, 372)
        XCTAssertEqual(msg.numericName, "RPL_MOTD")
    }

    func testLibraChatNames() {
        let msg = Message.parse(":calcium.libera.chat 353 testbot = #test :@op +voice user")

        XCTAssertEqual(msg.numericCode, 353)
        XCTAssertEqual(msg.params[2], "#test")
        XCTAssertEqual(msg.text, "@op +voice user")
    }

    func testCAPLS() {
        let msg = Message.parse(":server CAP * LS :multi-prefix sasl account-notify extended-join")

        XCTAssertEqual(msg.command, "CAP")
        XCTAssertEqual(msg.params[0], "*")
        XCTAssertEqual(msg.params[1], "LS")
        XCTAssertTrue(msg.text?.contains("sasl") ?? false)
    }

    func testCAPLSMultiline() {
        let msg = Message.parse(":server CAP * LS * :multi-prefix extended-join account-notify")

        XCTAssertEqual(msg.command, "CAP")
        XCTAssertEqual(msg.params[2], "*")  // Multiline indicator
    }

    func testSASLSuccess() {
        let msg = Message.parse(":server 903 nick :SASL authentication successful")

        XCTAssertEqual(msg.numericCode, 903)
        XCTAssertEqual(msg.numericName, "RPL_SASLSUCCESS")
    }

    func testWhoisUser() {
        let msg = Message.parse(":server 311 requester targetnick username host.com * :Real Name")

        XCTAssertEqual(msg.numericCode, 311)
        XCTAssertEqual(msg.numericName, "RPL_WHOISUSER")
        XCTAssertEqual(msg.params[1], "targetnick")
        XCTAssertEqual(msg.params[2], "username")
        XCTAssertEqual(msg.params[3], "host.com")
    }

    func testWhoisChannels() {
        let msg = Message.parse(":server 319 requester targetnick :@#channel1 +#channel2 #channel3")

        XCTAssertEqual(msg.numericCode, 319)
        XCTAssertEqual(msg.numericName, "RPL_WHOISCHANNELS")
        XCTAssertEqual(msg.text, "@#channel1 +#channel2 #channel3")
    }

    func testComplexTaggedMessage() {
        let msg = Message.parse(
            "@time=2024-01-15T10:30:00.000Z;msgid=abc123;account=testuser :nick!user@host.com PRIVMSG #channel :Hello, world!"
        )

        XCTAssertEqual(msg.tags["time"], "2024-01-15T10:30:00.000Z")
        XCTAssertEqual(msg.tags["msgid"], "abc123")
        XCTAssertEqual(msg.tags["account"], "testuser")
        XCTAssertEqual(msg.nick, "nick")
        XCTAssertEqual(msg.user, "user")
        XCTAssertEqual(msg.host, "host.com")
        XCTAssertEqual(msg.command, "PRIVMSG")
        XCTAssertEqual(msg.target, "#channel")
        XCTAssertEqual(msg.text, "Hello, world!")
    }

    // MARK: - Helper Properties

    func testTargetForChannel() {
        let msg = Message.parse("PRIVMSG #channel :text")
        XCTAssertEqual(msg.target, "#channel")
    }

    func testTargetForUser() {
        let msg = Message.parse("PRIVMSG user :text")
        XCTAssertEqual(msg.target, "user")
    }

    func testChannelIdentification() {
        let channelMsg = Message.parse("JOIN #channel")
        XCTAssertEqual(channelMsg.channel, "#channel")

        let ampChannel = Message.parse("JOIN &local")
        XCTAssertEqual(ampChannel.channel, "&local")
    }
}
