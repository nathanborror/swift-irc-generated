import Foundation
import IRC

@MainActor
@Observable
class AppState {
    static let shared = AppState()

    var joined: [String: Channel] = [:]
    var channels: [String: IRC.ListAggregation.Entry] = [:]
    var events: [IRC.Client.Event] = []
    var state: State = .disconnected
    var selected: Selection = .console

    var showingInfo = false
    var showingJoinForm = false

    enum State {
        case connecting
        case connected
        case disconnected
    }

    enum Selection: Hashable {
        case channel(Channel)
        case console
    }

    struct Channel: Identifiable, Hashable {
        var name: String
        var members: Set<String> = []
        var topic: String? = nil

        var id: String { name }
    }

    private let client: IRC.Client

    init() {
        let config = IRC.Client.Config(
            server: "localhost",
            port: 6697,
            useTLS: true,
            nick: "nathan",
            username: "nathan",
            realname: "Nathan Borror",
            sasl: nil,
            requestedCaps: [
                "sasl",
                "echo-message",
                "message-tags",
                "server-time",
                "account-tag",
                "extended-join",
                "multi-prefix",
            ],
            pingTimeout: 120.0,
            rateLimit: .default
        )
        let transport = IRC.NWTransport()

        self.client = .init(config: config, transport: transport)
    }

    func connect() {
        Task {
            do {
                try await client.connect()
                Task { await processEvents() }
                await client.awaitRegistered()
            } catch {
                print(error)
            }
        }
    }

    func join(_ channel: String) {
        Task {
            do {
                try await client.join(channel)
                let result = try await client.names(channel)
                let channel = Channel(name: channel, members: Set(result.names))
                joined[channel.name] = channel
                selected = .channel(channel)
            } catch {
                print(error)
            }
        }
    }

    func privmsg(target: String, text: String) {
        Task {
            do {
                try await client.privmsg(target, text)
            } catch {
                print(error)
            }
        }
    }

    func list() {
        Task {
            do {
                let results = try await client.list()
                self.channels = Dictionary(
                    uniqueKeysWithValues: results.entries.map { ($0.channel, $0) })
            } catch {
                print(error)
            }
        }
    }

    func executeSlashCommand(_ command: SlashCommand, currentChannel: String? = nil) {
        Task {
            do {
                switch command {
                case .join(let channel, let key):
                    try await client.join(channel, key: key)
                    let result = try await client.names(channel)
                    let newChannel = Channel(name: channel, members: Set(result.names))
                    joined[newChannel.name] = newChannel
                    selected = .channel(newChannel)

                case .part(let channel, let reason):
                    try await client.part(channel, reason: reason)
                    joined.removeValue(forKey: channel)
                    if case .channel(let ch) = selected, ch.name == channel {
                        selected = .console
                    }

                case .topic(let channel, let newTopic):
                    if let newTopic = newTopic {
                        try await client.setTopic(channel, topic: newTopic)
                    } else {
                        try await client.getTopic(channel)
                    }

                case .kick(let channel, let nick, let reason):
                    try await client.kick(channel, nick: nick, reason: reason)

                case .mode(let target, let modes):
                    // Send raw MODE command
                    try await client.send(.mode(target: target, modes: modes))

                case .whois(let nick):
                    let result = try await client.whois(nick)
                    var info = "\(result.nick)"
                    if let user = result.username, let host = result.host {
                        info += " (\(user)@\(host))"
                    }
                    if let realname = result.realname {
                        info += " - \(realname)"
                    }
                    if let account = result.account {
                        info += " [account: \(account)]"
                    }
                    if result.isAway, let msg = result.awayMessage {
                        info += " (away: \(msg))"
                    }
                    print("WHOIS: \(info)")
                    if !result.channels.isEmpty {
                        print("  Channels: \(result.channels.joined(separator: " "))")
                    }

                case .names(let channel):
                    let result = try await client.names(channel)
                    print("NAMES: \(result.names.count) users in \(channel)")
                    print("  \(result.names.joined(separator: ", "))")

                case .list(let channel):
                    let results = try await client.list(channel)
                    self.channels = Dictionary(
                        uniqueKeysWithValues: results.entries.map { ($0.channel, $0) })
                    print("LIST: Found \(results.entries.count) channels")

                case .quit(let reason):
                    try await client.disconnect(reason: reason ?? "Quit")

                case .nick(let newNick):
                    try await client.send(.nick(newNick))

                case .msg(let target, let text):
                    try await client.privmsg(target, text)
                }
            } catch {
                print("Error executing slash command: \(error)")
            }
        }
    }

    func processEvents() async {
        var messageCount = 0

        for await event in await client.events {
            events.append(event)

            switch event {
            case .connected:
                state = .connecting

            case .registered:
                state = .connected

            case .disconnected(let error):
                state = .disconnected
                print("Disconnected reason: \(error?.localizedDescription ?? "Unknown")")

            case .privmsg(let target, let sender, let text, _):
                messageCount += 1
                await handleCommands(
                    target: target, sender: sender, text: text, messageCount: messageCount)

            case .notice(let target, let sender, let text, _):
                print("NOTICE: \(target) - \(sender) :\(text)")

            case .join(let channel, let nick, _):
                channelInsert(nick: nick, channel: channel)

            case .part(let channel, let nick, _, _):
                channelRemove(nick: nick, channel: channel)

            case .quit(let nick, _, _):
                for (key, _) in joined {
                    channelRemove(nick: nick, channel: key)
                }

            case .kick(let channel, let kicked, _, _, _):
                channelRemove(nick: kicked, channel: channel)

            case .nick(let oldNick, let newNick, _):
                for (key, _) in joined {
                    channelRemove(nick: oldNick, channel: key)
                    channelInsert(nick: newNick, channel: key)
                }

            case .topic(let channel, let topic, _):
                if var existing = joined[channel] {
                    existing.topic = topic
                    joined[channel] = existing
                }

            case .mode(let target, let modes, _):
                print("MODE: \(target) - \(modes)")

            case .error(let error):
                print("ERROR: \(error)")

            case .message:
                break
            }
        }
    }

    func handleCommands(target: String, sender: String, text: String, messageCount: Int) async {
        guard text.hasPrefix("!") else { return }  // ignore if not a command

        let components = text.split(separator: " ", maxSplits: 1)
        let command = String(components[0].dropFirst())  // Remove '!'
        let args = components.count > 1 ? String(components[1]) : ""

        do {
            switch command {
            case "hello", "hi":
                try await client.privmsg(target, "Hello, \(sender)! 👋")

            case "help":
                try await client.privmsg(
                    target,
                    "\(sender): Commands: !hello !help !ping !stats !whois <nick> !topic !names")

            case "ping":
                try await client.privmsg(target, "\(sender): Pong! 🏓")

            case "stats":
                let uptime = ProcessInfo.processInfo.systemUptime
                let minutes = Int(uptime) / 60
                let nick = await client.getCurrentNick()
                try await client.privmsg(
                    target,
                    "\(sender): I'm \(nick), running for \(minutes)m, seen \(messageCount) messages"
                )

            case "whois":
                guard !args.isEmpty else {
                    try await client.privmsg(target, "\(sender): Usage: !whois <nick>")
                    return
                }

                let nick = args.trimmingCharacters(in: .whitespaces)
                let result = try await client.whois(nick)

                var info = "\(sender): \(result.nick)"
                if let user = result.username, let host = result.host {
                    info += " (\(user)@\(host))"
                }
                if let realname = result.realname {
                    info += " - \(realname)"
                }
                if let account = result.account {
                    info += " [account: \(account)]"
                }
                if result.isAway, let msg = result.awayMessage {
                    info += " (away: \(msg))"
                }

                try await client.privmsg(target, info)

                if !result.channels.isEmpty {
                    try await client.privmsg(
                        target, "  Channels: \(result.channels.joined(separator: " "))")
                }

            case "topic":
                guard target.hasPrefix("#") else {
                    try await client.privmsg(
                        target, "\(sender): This command only works in channels")
                    return
                }

                if args.isEmpty {
                    try await client.getTopic(target)
                } else {
                    try await client.setTopic(target, topic: args)
                }

            case "names":
                guard target.hasPrefix("#") else {
                    try await client.privmsg(
                        target, "\(sender): This command only works in channels")
                    return
                }

                let result = try await client.names(target)
                try await client.privmsg(
                    target, "\(sender): \(result.names.count) users in \(target)")

                // Show first 10 users
                let preview = result.names.prefix(10).joined(separator: ", ")
                if result.names.count > 10 {
                    try await client.privmsg(
                        target, "  \(preview), and \(result.names.count - 10) more...")
                } else {
                    try await client.privmsg(target, "  \(preview)")
                }

            case "list":
                let result = try await client.list()
                let channelCount = result.entries.count
                try await client.privmsg(target, "\(sender): Found \(channelCount) channels")

                // Show top 5 by user count
                let top5 = result.entries
                    .sorted { $0.userCount > $1.userCount }
                    .prefix(5)

                for entry in top5 {
                    try await client.privmsg(
                        target,
                        "  \(entry.channel) (\(entry.userCount)): \(entry.topic)"
                    )
                }

            case "quit":
                // Only allow bot owner to quit (check by host/account in production)
                try await client.privmsg(target, "Goodbye! 👋")
                try await client.disconnect(reason: "Requested by \(sender)")

            default:
                // Unknown command, ignore
                break
            }

        } catch {
            print("Error handling command '\(command)': \(error)")
            try? await client.privmsg(
                target, "\(sender): Error executing command: \(error.localizedDescription)")
        }
    }

    private func channelInsert(nick: String, channel: String) {
        if var existing = joined[channel] {
            existing.members.insert(nick)
            joined[existing.name] = existing
        }
    }

    private func channelRemove(nick: String, channel: String) {
        if var existing = joined[channel] {
            existing.members.remove(nick)
            joined[existing.name] = existing
        }
    }
}
