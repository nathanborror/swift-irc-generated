import Foundation

public enum Command: Sendable {
    // Raw command
    case raw(String)

    // Connection Registration
    case pass(String)
    case nick(String)
    case user(username: String, mode: Int = 0, realname: String)
    case quit(String? = nil)

    // Capability Negotiation (IRCv3)
    case cap(String, [String]? = nil)  // CAP LS, REQ, END, etc.
    case capEnd

    // SASL Authentication
    case authenticate(String)

    // Channel Operations
    case join(String, key: String? = nil)
    case part(String, reason: String? = nil)
    case topic(String, newTopic: String? = nil)
    case names(String)
    case list(String? = nil)
    case invite(nick: String, channel: String)
    case kick(channel: String, nick: String, reason: String? = nil)

    // Messaging
    case privmsg(String, String)
    case notice(String, String)

    // Channel/User Modes
    case mode(target: String, modes: String? = nil)

    // User Queries
    case whois(String)
    case whowas(String, count: Int? = nil)
    case who(String, opOnly: Bool = false)
    case ison([String])
    case userhost([String])

    // Server Queries
    case ping(String)
    case pong(String)
    case motd(String? = nil)
    case version(String? = nil)
    case time(String? = nil)
    case admin(String? = nil)
    case info(String? = nil)
    case stats(query: String? = nil, server: String? = nil)

    // User State
    case away(String? = nil)
}

// MARK: - Encoding

extension Command {
    /// Encodes the command into an IRC protocol line (without CRLF)
    public func encode() -> String {
        switch self {
        case .raw(let line):
            return line

        case .pass(let password):
            return "PASS \(password)"

        case .nick(let nickname):
            return "NICK \(nickname)"

        case .user(let username, let mode, let realname):
            return "USER \(username) \(mode) * :\(realname)"

        case .quit(let message):
            if let message = message {
                return "QUIT :\(message)"
            }
            return "QUIT"

        case .cap(let subcommand, let args):
            if let args = args, !args.isEmpty {
                return "CAP \(subcommand) :\(args.joined(separator: " "))"
            }
            return "CAP \(subcommand)"

        case .capEnd:
            return "CAP END"

        case .authenticate(let data):
            return "AUTHENTICATE \(data)"

        case .join(let channel, let key):
            if let key = key {
                return "JOIN \(channel) \(key)"
            }
            return "JOIN \(channel)"

        case .part(let channel, let reason):
            if let reason = reason {
                return "PART \(channel) :\(reason)"
            }
            return "PART \(channel)"

        case .topic(let channel, let newTopic):
            if let newTopic = newTopic {
                return "TOPIC \(channel) :\(newTopic)"
            }
            return "TOPIC \(channel)"

        case .names(let channel):
            return "NAMES \(channel)"

        case .list(let channel):
            if let channel = channel {
                return "LIST \(channel)"
            }
            return "LIST"

        case .invite(let nick, let channel):
            return "INVITE \(nick) \(channel)"

        case .kick(let channel, let nick, let reason):
            if let reason = reason {
                return "KICK \(channel) \(nick) :\(reason)"
            }
            return "KICK \(channel) \(nick)"

        case .privmsg(let target, let text):
            return "PRIVMSG \(target) :\(text)"

        case .notice(let target, let text):
            return "NOTICE \(target) :\(text)"

        case .mode(let target, let modes):
            if let modes = modes {
                return "MODE \(target) \(modes)"
            }
            return "MODE \(target)"

        case .whois(let nick):
            return "WHOIS \(nick)"

        case .whowas(let nick, let count):
            if let count = count {
                return "WHOWAS \(nick) \(count)"
            }
            return "WHOWAS \(nick)"

        case .who(let mask, let opOnly):
            if opOnly {
                return "WHO \(mask) o"
            }
            return "WHO \(mask)"

        case .ison(let nicks):
            return "ISON \(nicks.joined(separator: " "))"

        case .userhost(let nicks):
            return "USERHOST \(nicks.joined(separator: " "))"

        case .ping(let token):
            return "PING :\(token)"

        case .pong(let token):
            return "PONG :\(token)"

        case .motd(let server):
            if let server = server {
                return "MOTD \(server)"
            }
            return "MOTD"

        case .version(let server):
            if let server = server {
                return "VERSION \(server)"
            }
            return "VERSION"

        case .time(let server):
            if let server = server {
                return "TIME \(server)"
            }
            return "TIME"

        case .admin(let server):
            if let server = server {
                return "ADMIN \(server)"
            }
            return "ADMIN"

        case .info(let server):
            if let server = server {
                return "INFO \(server)"
            }
            return "INFO"

        case .stats(let query, let server):
            var parts = ["STATS"]
            if let query = query {
                parts.append(query)
            }
            if let server = server {
                parts.append(server)
            }
            return parts.joined(separator: " ")

        case .away(let message):
            if let message = message {
                return "AWAY :\(message)"
            }
            return "AWAY"
        }
    }
}

// MARK: - Helper for SASL PLAIN

extension Command {
    /// Creates an AUTHENTICATE command for SASL PLAIN mechanism
    public static func authPlain(username: String, password: String) -> Command {
        let credentials = "\0\(username)\0\(password)"
        let encoded = Data(credentials.utf8).base64EncodedString()
        return .authenticate(encoded)
    }
}
