import Foundation
import Observation

@Observable
public final class ConnectionState: @unchecked Sendable {
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

        case .part(let channel, let nick, _, _):
            channels[channel]?.removeMember(nick)

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
        let nicks = nickList.split(separator: " ")
        for nickWithPrefix in nicks {
            let (nick, prefixes) = parseNickWithPrefixes(String(nickWithPrefix))
            channels[channelName]?.addMember(nick, prefixes: prefixes)
            ensureUser(nick, from: message)
        }
    }

    private func parseNickWithPrefixes(_ nickWithPrefix: String) -> (String, Set<User.Prefix>) {
        var prefixes: Set<User.Prefix> = []
        var nick = nickWithPrefix

        // Strip leading prefix characters
        while let first = nick.first {
            if let prefix = User.Prefix(rawValue: String(first)) {
                prefixes.insert(prefix)
                nick = String(nick.dropFirst())
            } else {
                break
            }
        }

        return (nick, prefixes)
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
