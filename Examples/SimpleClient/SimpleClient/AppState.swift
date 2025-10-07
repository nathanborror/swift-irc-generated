import Foundation
import IRC

@MainActor
@Observable
class AppState {
    static let shared = AppState()

    var channels: [String] = []
    var events: [IRC.Client.Event] = []
    var state: State = .disconnected

    enum State {
        case connecting
        case connected
        case disconnected
    }

    private let client: IRC.Client

    init() {
        let config = IRC.Client.Config(
            server: "localhost",
            port: 6697,
            useTLS: true,
            nick: "swiftbot",
            username: "swiftbot",
            realname: "A Swift IRC Bot",
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
                channels.append(channel)
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

            case .privmsg(let target, let sender, let text, let message):
                messageCount += 1
                await handleCommands(
                    target: target, sender: sender, text: text, messageCount: messageCount)

            case .notice(let target, let sender, let text, let message):
                print("NOTICE")

            case .join(let channel, let nick, let message):
                print("JOIN")

            case .part(let channel, let nick, let reason, let message):
                print("PART")

            case .quit(let nick, let reason, let message):
                print("QUIT")

            case .kick(let channel, let kicked, let by, let reason, let message):
                print("KICK")

            case .nick(let oldNick, let newNick, let message):
                print("NICK")

            case .topic(let channel, let topic, let message):
                print("TOPIC")

            case .mode(let target, let modes, let message):
                print("MODE")

            case .error(let error):
                print("Error: \(error)")

            case .message(let message):
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
}
