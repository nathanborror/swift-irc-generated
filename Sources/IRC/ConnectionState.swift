import Foundation
import Observation

@Observable
@MainActor
public final class ConnectionState {
    public private(set) var users: [String: User] = [:]
    public private(set) var channels: [String: Channel] = [:]
    public private(set) var myNick: String?

    public init() {}

    // MARK: - Event Application

    /// Applies a Client.Event to update the connection state
    public func apply(_ event: Client.Event) {
        switch event {
        case .registered:
            break

        case .join(let channel, let nick, let message):
            ensureChannel(channel)
            channels[channel]?.addMember(nick, prefixes: [])
            ensureUser(nick, from: message)

        case .part(let channel, _, _, _):
            channels.removeValue(forKey: channel)

        case .quit(let nick, _, _):
            removeUserFromAllChannels(nick)

        case .kick(let channel, let kicked, _, _, _):
            channels[channel]?.removeMember(kicked)

        case .nick(let oldNick, let newNick, _):
            renameUser(from: oldNick, to: newNick)

        case .topic(let channel, _, let message):
            channels[channel]?.apply(message)

        case .mode(let target, _, let message):
            if target.hasPrefix("#") || target.hasPrefix("&") {
                channels[target]?.apply(message)
            }

        case .message(let message):
            applyRawMessage(message)

        default:
            break
        }
    }

    /// Sets the current user's nick (call this after registration)
    public func setMyNick(_ nick: String) {
        myNick = nick
    }

    // MARK: - Private Helpers

    private func ensureChannel(_ name: String) {
        if channels[name] == nil {
            channels[name] = Channel(name: name)
        }
    }

    private func ensureUser(_ nick: String, from message: Message) {
        if users[nick] == nil {
            var user = User(nick: nick)
            // Try to extract user info from message prefix if available
            user.username = message.user
            user.hostname = message.host
            users[nick] = user
        }
    }

    private func ensureUserFromNames(nick: String, user: String?, host: String?) {
        if var existingUser = users[nick] {
            // Update existing user with new info if not already set
            if existingUser.username == nil {
                existingUser.username = user
            }
            if existingUser.hostname == nil {
                existingUser.hostname = host
            }
            users[nick] = existingUser
        } else {
            var newUser = User(nick: nick)
            newUser.username = user
            newUser.hostname = host
            users[nick] = newUser
        }
    }

    private func removeUserFromAllChannels(_ nick: String) {
        for channelName in channels.keys {
            channels[channelName]?.removeMember(nick)
        }
        users.removeValue(forKey: nick)
    }

    private func renameUser(from oldNick: String, to newNick: String) {
        // Update user record
        if var user = users.removeValue(forKey: oldNick) {
            user.nick = newNick
            users[newNick] = user
        }

        // Update in all channels
        for channelName in channels.keys {
            channels[channelName]?.renameMember(from: oldNick, to: newNick)
        }

        // Update myNick if it's us
        if myNick == oldNick {
            myNick = newNick
        }
    }

    private func applyRawMessage(_ message: Message) {
        switch message.command {
        case "353": // RPL_NAMREPLY: 353 <client> <symbol> <channel> :<nick list>
            parseNamesReply(message)

        case "352": // WHO reply
            parseWhoReply(message)

        case "354": // WHOX reply
            parseWhoxReply(message)

        case "332", "333", "324", "329": // Topic and mode replies
            if let channelName = message.channel {
                channels[channelName]?.apply(message)
            }

        default:
            break
        }
    }

    // MARK: - NAMES Parsing

    private func parseNamesReply(_ message: Message) {
        // 353 <client> <symbol> <channel> :<nick list>
        // symbol is = (public), * (private), or @ (secret)
        guard message.params.count >= 4 else { return }

        let channelName = message.params[2]
        let nickList = message.params[3]

        ensureChannel(channelName)

        // Parse nick list - each nick may have prefixes like @nick or +nick
        // With userhost-in-names capability, format is @nick!user@host
        let nicks = nickList.split(separator: " ")
        for nickWithPrefix in nicks {
            let (nick, user, host, prefixes) = parseNickWithPrefixes(String(nickWithPrefix))
            channels[channelName]?.addMember(nick, prefixes: prefixes)
            ensureUserFromNames(nick: nick, user: user, host: host)
        }
    }

    /// Parses a nick entry from NAMES reply, returning (nick, user, host, prefixes)
    /// Handles both simple format (@nick) and userhost-in-names format (@nick!user@host)
    private func parseNickWithPrefixes(_ nickWithPrefix: String) -> (nick: String, user: String?, host: String?, prefixes: Set<User.Prefix>) {
        var prefixes: Set<User.Prefix> = []
        var remaining = nickWithPrefix

        // Strip leading channel prefix characters (@, +, %, ~, &)
        while let first = remaining.first {
            if let prefix = User.Prefix(rawValue: String(first)) {
                prefixes.insert(prefix)
                remaining = String(remaining.dropFirst())
            } else {
                break
            }
        }

        // Check for userhost-in-names format: nick!user@host
        if let bangIdx = remaining.firstIndex(of: "!") {
            let nick = String(remaining[..<bangIdx])
            let afterBang = remaining.index(after: bangIdx)
            let userHost = remaining[afterBang...]

            if let atIdx = userHost.firstIndex(of: "@") {
                let user = String(userHost[..<atIdx])
                let host = String(userHost[userHost.index(after: atIdx)...])
                return (nick, user, host, prefixes)
            } else {
                // Has ! but no @, treat rest as user
                return (nick, String(userHost), nil, prefixes)
            }
        }

        return (remaining, nil, nil, prefixes)
    }

    // MARK: - WHO/WHOX Parsing

    private func parseWhoReply(_ message: Message) {
        var user = User(nick: "")
        guard let result = user.apply(message) else { return }

        // Store/update the user
        users[user.nick] = user

        // Update channel membership if we have channel context
        if let channelName = result.channel, channelName != "*" {
            ensureChannel(channelName)
            channels[channelName]?.addMember(user.nick, prefixes: result.prefixes)
        }
    }

    private func parseWhoxReply(_ message: Message) {
        var user = User(nick: "")
        guard let result = user.apply(message) else { return }

        // Store/update the user
        users[user.nick] = user

        // Update channel membership if we have channel context
        if let channelName = result.channel, channelName != "*" {
            ensureChannel(channelName)
            channels[channelName]?.addMember(user.nick, prefixes: result.prefixes)
        }
    }
}
