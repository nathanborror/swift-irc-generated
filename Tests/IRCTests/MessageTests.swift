import Foundation
import Testing

@testable import IRC

@Suite("Message Tests")
struct MessageTests {

    // MARK: - Basic Parsing

    @Test("Simple command parsing")
    func simpleCommand() {
        let msg = Message.parse("PING")

        #expect(msg.prefix == nil)
        #expect(msg.command == "PING")
        #expect(msg.params.isEmpty)
    }

    @Test("Command with single parameter")
    func commandWithSingleParam() {
        let msg = Message.parse("PING :server.name")

        #expect(msg.prefix == nil)
        #expect(msg.command == "PING")
        #expect(msg.params == ["server.name"])
    }

    @Test("Command with multiple parameters")
    func commandWithMultipleParams() {
        let msg = Message.parse("NICK newnick 1 2 3")

        #expect(msg.command == "NICK")
        #expect(msg.params == ["newnick", "1", "2", "3"])
    }

    @Test("Command with trailing parameter")
    func commandWithTrailingParam() {
        let msg = Message.parse("PRIVMSG #channel :Hello world")

        #expect(msg.command == "PRIVMSG")
        #expect(msg.params.count == 2)
        #expect(msg.params[0] == "#channel")
        #expect(msg.params[1] == "Hello world")
        #expect(msg.text == "Hello world")
    }

    @Test("Command with mixed parameters")
    func commandWithMixedParams() {
        let msg = Message.parse("USER username 0 * :Real Name")

        #expect(msg.command == "USER")
        #expect(msg.params == ["username", "0", "*", "Real Name"])
        #expect(msg.text == "Real Name")
    }

    // MARK: - Prefix Parsing

    @Test("Server prefix parsing")
    func serverPrefix() {
        let msg = Message.parse(":server.name PING :token")

        #expect(msg.prefix == "server.name")
        #expect(msg.command == "PING")
        #expect(msg.params == ["token"])
        #expect(msg.nick == "server.name")
        #expect(msg.user == nil)
        #expect(msg.host == nil)
    }

    @Test("Full user prefix parsing")
    func fullUserPrefix() {
        let msg = Message.parse(":nick!user@host.com PRIVMSG #channel :Hello")

        #expect(msg.prefix == "nick!user@host.com")
        #expect(msg.nick == "nick")
        #expect(msg.user == "user")
        #expect(msg.host == "host.com")
        #expect(msg.command == "PRIVMSG")
    }

    @Test("User prefix without host")
    func userPrefixWithoutHost() {
        let msg = Message.parse(":nick!user PRIVMSG #channel :Hello")

        #expect(msg.nick == "nick")
        #expect(msg.user == "user")
        #expect(msg.host == nil)
    }

    @Test("Nick only prefix")
    func nickOnlyPrefix() {
        let msg = Message.parse(":nick QUIT :Goodbye")

        #expect(msg.nick == "nick")
        #expect(msg.user == nil)
        #expect(msg.host == nil)
    }

    // MARK: - Tag Parsing (IRCv3)

    @Test("Single tag parsing")
    func singleTag() {
        let msg = Message.parse("@time=2024-01-01T12:00:00.000Z PRIVMSG #channel :Hello")

        #expect(msg.tags["time"] == "2024-01-01T12:00:00.000Z")
        #expect(msg.command == "PRIVMSG")
    }

    @Test("Multiple tags parsing")
    func multipleTags() {
        let msg = Message.parse(
            "@time=2024-01-01T12:00:00.000Z;account=user123;msgid=abc123 PRIVMSG #channel :Hi")

        #expect(msg.tags["time"] == "2024-01-01T12:00:00.000Z")
        #expect(msg.tags["account"] == "user123")
        #expect(msg.tags["msgid"] == "abc123")
    }

    @Test("Tags with prefix")
    func tagsWithPrefix() {
        let msg = Message.parse("@account=user :nick!user@host PRIVMSG #channel :Tagged message")

        #expect(msg.tags["account"] == "user")
        #expect(msg.prefix == "nick!user@host")
        #expect(msg.nick == "nick")
        #expect(msg.command == "PRIVMSG")
    }

    @Test("Empty tag value")
    func emptyTagValue() {
        let msg = Message.parse("@flag PRIVMSG #channel :Hi")

        #expect(msg.tags["flag"] == "")
    }

    @Test("Tag value escaping")
    func tagValueEscaping() {
        // IRCv3 tag escaping: \: -> ; \s -> space \\ -> \ \r -> CR \n -> LF
        let msg = Message.parse("@key=value\\:with\\ssemicolon\\sand\\sspace PRIVMSG #channel :Hi")

        #expect(msg.tags["key"] == "value;with semicolon and space")
    }

    @Test("Timestamp property parsing")
    func timestampProperty() {
        // Test with valid time tag
        let msg = Message.parse("@time=2024-01-15T10:30:00.000Z PRIVMSG #channel :Hello")

        #expect(msg.timestamp != nil)

        // Verify the date is correctly parsed
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let expectedDate = formatter.date(from: "2024-01-15T10:30:00.000Z")
        #expect(msg.timestamp == expectedDate)

        // Test without time tag
        let msgNoTime = Message.parse("PRIVMSG #channel :Hello")
        #expect(msgNoTime.timestamp == nil)

        // Test with invalid time format
        let msgInvalidTime = Message.parse("@time=invalid PRIVMSG #channel :Hello")
        #expect(msgInvalidTime.timestamp == nil)
    }

    // MARK: - Numeric Replies

    @Test("Numeric reply parsing")
    func numericReply() {
        let msg = Message.parse(":server 001 nick :Welcome to the network")

        #expect(msg.isNumeric)
        #expect(msg.numericCode == 1)
        #expect(msg.numericName == "RPL_WELCOME")
        #expect(msg.command == "001")
    }

    @Test("Three digit numeric parsing")
    func threeDigitNumeric() {
        let msg = Message.parse(":server 353 nick = #channel :user1 user2 user3")

        #expect(msg.isNumeric)
        #expect(msg.numericCode == 353)
        #expect(msg.numericName == "RPL_NAMREPLY")
    }

    @Test("Error numeric parsing")
    func errorNumeric() {
        let msg = Message.parse(":server 433 * nick :Nickname is already in use")

        #expect(msg.isNumeric)
        #expect(msg.numericCode == 433)
        #expect(msg.numericName == "ERR_NICKNAMEINUSE")
    }

    // MARK: - Specific Commands

    @Test("PRIVMSG parsing")
    func privmsg() {
        let msg = Message.parse(":sender!user@host PRIVMSG #channel :Hello, world!")

        #expect(msg.command == "PRIVMSG")
        #expect(msg.nick == "sender")
        #expect(msg.target == "#channel")
        #expect(msg.text == "Hello, world!")
        #expect(msg.channel == "#channel")
    }

    @Test("Private PRIVMSG parsing")
    func privatePrivmsg() {
        let msg = Message.parse(":sender!user@host PRIVMSG recipient :Private message")

        #expect(msg.target == "recipient")
        #expect(msg.channel == nil)  // Not a channel
    }

    @Test("JOIN parsing")
    func join() {
        let msg = Message.parse(":user!ident@host JOIN #channel")

        #expect(msg.command == "JOIN")
        #expect(msg.nick == "user")
        #expect(msg.channel == "#channel")
    }

    @Test("JOIN with account parsing")
    func joinWithAccount() {
        let msg = Message.parse(":user!ident@host JOIN #channel account :Real Name")

        #expect(msg.command == "JOIN")
        #expect(msg.params[0] == "#channel")
        #expect(msg.params[1] == "account")
        #expect(msg.params[2] == "Real Name")
    }

    @Test("PART parsing")
    func part() {
        let msg = Message.parse(":user!ident@host PART #channel :Goodbye!")

        #expect(msg.command == "PART")
        #expect(msg.channel == "#channel")
        #expect(msg.text == "Goodbye!")
    }

    @Test("PART without reason")
    func partWithoutReason() {
        let msg = Message.parse(":user!ident@host PART #channel")

        #expect(msg.command == "PART")
        #expect(msg.channel == "#channel")
        #expect(msg.text == "#channel")  // text returns last param even if not trailing
    }

    @Test("QUIT parsing")
    func quit() {
        let msg = Message.parse(":user!ident@host QUIT :Quit message")

        #expect(msg.command == "QUIT")
        #expect(msg.nick == "user")
        #expect(msg.text == "Quit message")
    }

    @Test("KICK parsing")
    func kick() {
        let msg = Message.parse(":operator!user@host KICK #channel victim :Spam")

        #expect(msg.command == "KICK")
        #expect(msg.channel == "#channel")
        #expect(msg.params[0] == "#channel")
        #expect(msg.params[1] == "victim")
        #expect(msg.text == "Spam")
    }

    @Test("NICK parsing")
    func nick() {
        let msg = Message.parse(":oldnick!user@host NICK :newnick")

        #expect(msg.command == "NICK")
        #expect(msg.nick == "oldnick")
        #expect(msg.params[0] == "newnick")
    }

    @Test("TOPIC parsing")
    func topic() {
        let msg = Message.parse(":nick!user@host TOPIC #channel :New topic here")

        #expect(msg.command == "TOPIC")
        #expect(msg.channel == "#channel")
        #expect(msg.text == "New topic here")
    }

    @Test("MODE parsing")
    func mode() {
        let msg = Message.parse(":op!user@host MODE #channel +o nick")

        #expect(msg.command == "MODE")
        #expect(msg.channel == "#channel")
        #expect(msg.params == ["#channel", "+o", "nick"])
    }

    @Test("NOTICE parsing")
    func notice() {
        let msg = Message.parse(":server NOTICE * :*** Looking up your hostname")

        #expect(msg.command == "NOTICE")
        #expect(msg.target == "*")
        #expect(msg.text == "*** Looking up your hostname")
    }

    // MARK: - Edge Cases

    @Test("Empty message parsing")
    func emptyMessage() {
        let msg = Message.parse("")

        #expect(msg.command == "")
        #expect(msg.params.isEmpty)
    }

    @Test("Only spaces parsing")
    func onlySpaces() {
        let msg = Message.parse("   ")

        #expect(msg.command == "")
        #expect(msg.params.isEmpty)
    }

    @Test("Trailing CRLF handling")
    func trailingCRLF() {
        let msg = Message.parse("PING :server\r\n")

        #expect(msg.command == "PING")
        #expect(msg.params == ["server"])
    }

    @Test("Colon in middle parameter")
    func colonInMiddleParam() {
        // Colon only has special meaning if it's the first character of a param
        let msg = Message.parse("MODE #channel +k pass:word")

        #expect(msg.params == ["#channel", "+k", "pass:word"])
    }

    @Test("Empty trailing parameter")
    func emptyTrailingParam() {
        let msg = Message.parse("PRIVMSG #channel :")

        #expect(msg.params == ["#channel", ""])
        #expect(msg.text == "")
    }

    @Test("Multiple spaces between parameters")
    func multipleSpacesBetweenParams() {
        let msg = Message.parse("MODE    #channel    +o    nick")

        #expect(msg.params == ["#channel", "+o", "nick"])
    }

    @Test("Unicode in message")
    func unicodeInMessage() {
        let msg = Message.parse(":user!host PRIVMSG #channel :Hello 👋 世界 🌍")

        #expect(msg.text == "Hello 👋 世界 🌍")
    }

    // MARK: - Real World Examples

    @Test("Libera.Chat welcome message")
    func liberaChatWelcome() {
        let msg = Message.parse(
            ":calcium.libera.chat 001 testbot :Welcome to the Libera.Chat Internet Relay Chat Network testbot"
        )

        #expect(msg.command == "001")
        #expect(msg.numericCode == 1)
        #expect(msg.params[0] == "testbot")
        #expect(msg.text?.contains("Welcome") ?? false)
    }

    @Test("Libera.Chat MOTD message")
    func liberaChatMotd() {
        let msg = Message.parse(":calcium.libera.chat 372 testbot :- Welcome to Libera Chat")

        #expect(msg.numericCode == 372)
        #expect(msg.numericName == "RPL_MOTD")
    }

    @Test("Libera.Chat NAMES reply")
    func liberaChatNames() {
        let msg = Message.parse(":calcium.libera.chat 353 testbot = #test :@op +voice user")

        #expect(msg.numericCode == 353)
        #expect(msg.params[2] == "#test")
        #expect(msg.text == "@op +voice user")
    }

    @Test("CAP LS parsing")
    func capLS() {
        let msg = Message.parse(":server CAP * LS :multi-prefix sasl account-notify extended-join")

        #expect(msg.command == "CAP")
        #expect(msg.params[0] == "*")
        #expect(msg.params[1] == "LS")
        #expect(msg.text?.contains("sasl") ?? false)
    }

    @Test("CAP LS multiline parsing")
    func capLSMultiline() {
        let msg = Message.parse(":server CAP * LS * :multi-prefix extended-join account-notify")

        #expect(msg.command == "CAP")
        #expect(msg.params[2] == "*")  // Multiline indicator
    }

    @Test("CAP LS with values")
    func capLSWithValues() {
        let msg = Message.parse(
            ":server CAP * LS :multi-prefix sasl=PLAIN,EXTERNAL,SCRAM-SHA-256 account-notify")

        #expect(msg.command == "CAP")
        #expect(msg.params[0] == "*")
        #expect(msg.params[1] == "LS")
        #expect(msg.text?.contains("sasl=") ?? false)
    }

    @Test("SASL success message")
    func saslSuccess() {
        let msg = Message.parse(":server 903 nick :SASL authentication successful")

        #expect(msg.numericCode == 903)
        #expect(msg.numericName == "RPL_SASLSUCCESS")
    }

    @Test("WHOIS user reply")
    func whoisUser() {
        let msg = Message.parse(":server 311 requester targetnick username host.com * :Real Name")

        #expect(msg.numericCode == 311)
        #expect(msg.numericName == "RPL_WHOISUSER")
        #expect(msg.params[1] == "targetnick")
        #expect(msg.params[2] == "username")
        #expect(msg.params[3] == "host.com")
    }

    @Test("WHOIS channels reply")
    func whoisChannels() {
        let msg = Message.parse(":server 319 requester targetnick :@#channel1 +#channel2 #channel3")

        #expect(msg.numericCode == 319)
        #expect(msg.numericName == "RPL_WHOISCHANNELS")
        #expect(msg.text == "@#channel1 +#channel2 #channel3")
    }

    @Test("Complex tagged message parsing")
    func complexTaggedMessage() {
        let msg = Message.parse(
            "@time=2024-01-15T10:30:00.000Z;msgid=abc123;account=testuser :nick!user@host.com PRIVMSG #channel :Hello, world!"
        )

        #expect(msg.tags["time"] == "2024-01-15T10:30:00.000Z")
        #expect(msg.tags["msgid"] == "abc123")
        #expect(msg.tags["account"] == "testuser")
        #expect(msg.nick == "nick")
        #expect(msg.user == "user")
        #expect(msg.host == "host.com")
        #expect(msg.command == "PRIVMSG")
        #expect(msg.target == "#channel")
        #expect(msg.text == "Hello, world!")
    }

    // MARK: - Helper Properties

    @Test("Target for channel")
    func targetForChannel() {
        let msg = Message.parse("PRIVMSG #channel :text")
        #expect(msg.target == "#channel")
    }

    @Test("Target for user")
    func targetForUser() {
        let msg = Message.parse("PRIVMSG user :text")
        #expect(msg.target == "user")
    }

    @Test("Channel identification")
    func channelIdentification() {
        let channelMsg = Message.parse("JOIN #channel")
        #expect(channelMsg.channel == "#channel")

        let ampChannel = Message.parse("JOIN &local")
        #expect(ampChannel.channel == "&local")
    }
}
