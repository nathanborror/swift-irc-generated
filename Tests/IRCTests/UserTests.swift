import Foundation
import Testing

@testable import IRC

@Suite("User Tests")
struct UserTests {

    // MARK: - WHO Reply Parsing (352)

    @Test("Standard WHO reply parsing")
    func whoReply() {
        let msg = Message.parse(":server 352 client #channel username host.com irc.server nick H :0 Real Name")

        var user = User(nick: "")
        let result = user.apply(msg)

        #expect(user.nick == "nick")
        #expect(user.username == "username")
        #expect(user.hostname == "host.com")
        #expect(user.server == "irc.server")
        #expect(user.realname == "Real Name")
        #expect(user.account == nil)
        #expect(user.idleSeconds == nil)
        #expect(result?.channel == "#channel")
        #expect(result?.prefixes.isEmpty == true)
    }

    @Test("WHO reply with IRC operator flag")
    func whoReplyWithOperator() {
        let msg = Message.parse(":server 352 client * username host.com irc.server nick H* :0 Real Name")

        var user = User(nick: "")
        let result = user.apply(msg)

        #expect(user.nick == "nick")
        #expect(user.username == "username")
        #expect(result?.prefixes.isEmpty == true)  // * is IRC operator, not a channel prefix
    }

    @Test("WHO reply with channel op")
    func whoReplyWithOp() {
        let msg = Message.parse(":server 352 client #channel username host.com irc.server nick H@ :0 Real Name")

        var user = User(nick: "")
        let result = user.apply(msg)

        #expect(user.nick == "nick")
        #expect(result?.channel == "#channel")
        #expect(result?.prefixes.contains(.op) == true)
        #expect(result?.prefixes.count == 1)
    }

    @Test("WHO reply with voice")
    func whoReplyWithVoice() {
        let msg = Message.parse(":server 352 client #channel username host.com irc.server nick H+ :0 Real Name")

        var user = User(nick: "")
        let result = user.apply(msg)

        #expect(result?.prefixes.contains(.voice) == true)
    }

    @Test("WHO reply with multiple prefixes")
    func whoReplyWithMultiplePrefixes() {
        let msg = Message.parse(":server 352 client #channel username host.com irc.server nick H@+ :0 Real Name")

        var user = User(nick: "")
        let result = user.apply(msg)

        #expect(result?.prefixes.contains(.op) == true)
        #expect(result?.prefixes.contains(.voice) == true)
        #expect(result?.prefixes.count == 2)
    }

    @Test("WHO reply with owner prefix")
    func whoReplyWithOwner() {
        let msg = Message.parse(":server 352 client #channel username host.com irc.server nick H~ :0 Real Name")

        var user = User(nick: "")
        let result = user.apply(msg)

        #expect(result?.prefixes.contains(.owner) == true)
    }

    @Test("WHO reply with away status")
    func whoReplyAway() {
        let msg = Message.parse(":server 352 client #channel username host.com irc.server nick G :0 Away User")

        var user = User(nick: "")
        user.apply(msg)

        #expect(user.nick == "nick")
        #expect(user.realname == "Away User")
    }

    @Test("WHO reply with hopcount")
    func whoReplyWithHopcount() {
        let msg = Message.parse(":server 352 client #channel user host.com irc.server nick H :3 Real Name")

        var user = User(nick: "")
        user.apply(msg)

        #expect(user.realname == "Real Name")
    }

    @Test("WHO reply with multi-word realname")
    func whoReplyMultiWordRealname() {
        let msg = Message.parse(":server 352 client #channel user host.com irc.server nick H :0 John Q. Public Esquire")

        var user = User(nick: "")
        user.apply(msg)

        #expect(user.realname == "John Q. Public Esquire")
    }

    @Test("WHO reply with no realname")
    func whoReplyNoRealname() {
        let msg = Message.parse(":server 352 client #channel user host.com irc.server nick H :0")

        var user = User(nick: "")
        user.apply(msg)

        #expect(user.realname == nil)
    }

    @Test("Invalid WHO reply with insufficient params")
    func invalidWhoReply() {
        let msg = Message.parse(":server 352 client #channel username")

        var user = User(nick: "")
        user.apply(msg)

        #expect(user.nick == "")
    }

    // MARK: - WHOX Reply Parsing (354)

    @Test("WHOX reply with account information")
    func whoxReplyWithAccount() {
        let msg = Message.parse(":server 354 client 1 #channel username 127.0.0.1 host.com irc.server nick H 0 0 accountname :Real Name")

        var user = User(nick: "")
        let result = user.apply(msg)

        #expect(user.nick == "nick")
        #expect(user.username == "username")
        #expect(user.hostname == "host.com")
        #expect(user.server == "irc.server")
        #expect(user.realname == "Real Name")
        #expect(user.account == "accountname")
        #expect(user.idleSeconds == 0)
        #expect(result?.channel == "#channel")
        #expect(result?.prefixes.isEmpty == true)
    }

    @Test("WHOX reply with channel op")
    func whoxReplyWithOp() {
        let msg = Message.parse(":server 354 client 1 #channel username 127.0.0.1 host.com irc.server nick H@ 0 0 accountname :Real Name")

        var user = User(nick: "")
        let result = user.apply(msg)

        #expect(result?.prefixes.contains(.op) == true)
        #expect(result?.channel == "#channel")
    }

    @Test("WHOX reply without account")
    func whoxReplyNoAccount() {
        let msg = Message.parse(":server 354 client 1 #channel username 127.0.0.1 host.com irc.server nick H 0 0 0 :Real Name")

        var user = User(nick: "")
        user.apply(msg)

        #expect(user.nick == "nick")
        #expect(user.account == nil)  // "0" means not logged in
    }

    @Test("WHOX reply with idle time")
    func whoxReplyWithIdleTime() {
        let msg = Message.parse(":server 354 client 1 #channel username 127.0.0.1 host.com irc.server nick H 0 300 someaccount :Real Name")

        var user = User(nick: "")
        user.apply(msg)

        #expect(user.idleSeconds == 300)
        #expect(user.account == "someaccount")
    }

    @Test("WHOX reply with zero idle time")
    func whoxReplyZeroIdle() {
        let msg = Message.parse(":server 354 client 1 #channel username 127.0.0.1 host.com irc.server nick H 0 0 account :Real Name")

        var user = User(nick: "")
        user.apply(msg)

        #expect(user.idleSeconds == 0)  // Zero is valid (user is active)
    }

    @Test("WHOX reply minimal format fallback")
    func whoxReplyMinimal() {
        let msg = Message.parse(":server 354 client 1 nick :Real Name")

        var user = User(nick: "")
        user.apply(msg)

        #expect(user.nick == "nick")
        #expect(user.username == nil)
        #expect(user.hostname == nil)
        #expect(user.realname == "Real Name")
    }

    @Test("WHOX reply with multi-word realname")
    func whoxReplyMultiWordRealname() {
        let msg = Message.parse(":server 354 client 1 #channel user 127.0.0.1 host.com irc.server nick H 0 0 account :Full Real Name Here")

        var user = User(nick: "")
        user.apply(msg)

        #expect(user.realname == "Full Real Name Here")
    }

    @Test("Invalid WHOX reply with insufficient params")
    func invalidWhoxReply() {
        let msg = Message.parse(":server 354 client")

        var user = User(nick: "")
        user.apply(msg)

        #expect(user.nick == "")
    }

    // MARK: - Non-WHO/WHOX Messages

    @Test("Non-WHO message returns nil")
    func nonWhoMessage() {
        let msg = Message.parse(":nick!user@host PRIVMSG #channel :Hello")

        var user = User(nick: "")
        user.apply(msg)

        #expect(user.nick == "")
    }

    @Test("Numeric reply that is not WHO returns nil")
    func nonWhoNumericReply() {
        let msg = Message.parse(":server 001 nick :Welcome")

        var user = User(nick: "")
        user.apply(msg)

        #expect(user.nick == "")
    }

    // MARK: - User Properties

    @Test("User ID is just nick")
    func userID() {
        let msg = Message.parse(":server 352 client #channel user host.com irc.server testnick H :0 Real Name")

        var user = User(nick: "")
        user.apply(msg)

        #expect(user.id == "testnick")
    }

    @Test("User authentication status with account")
    func userAuthenticatedWithAccount() {
        let msg = Message.parse(":server 354 client 1 #channel user 127.0.0.1 host.com irc.server nick H 0 0 accountname :Real Name")

        var user = User(nick: "")
        user.apply(msg)

        #expect(user.isAuthenticated == true)
    }

    @Test("User authentication status without account")
    func userNotAuthenticated() {
        let msg = Message.parse(":server 352 client #channel user host.com irc.server nick H :0 Real Name")

        var user = User(nick: "")
        user.apply(msg)

        #expect(user.isAuthenticated == false)
    }
}
