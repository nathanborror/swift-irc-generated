import Foundation
import IRC

/// A simple IRC bot demonstrating the IRC library
@main
struct SimpleBot {
    static func main() async {
        do {
            try await run()
        } catch {
            print("Fatal error: \(error)")
            exit(1)
        }
    }

    static func run() async throws {
        // Configuration
        let config = Client.Config(
            server: "localhost",
            port: 6697,
            useTLS: true,
            nick: "swiftbot",
            username: "swiftbot",
            realname: "A Swift IRC Bot",
            sasl: nil,  // Set to .plain(username: "user", password: "pass") for SASL auth
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

        // Create transport and client
        let transport = NWTransport()
        let client = Client(config: config, transport: transport)

        print("🤖 Starting SwiftBot...")
        print("📡 Connecting to \(config.server):\(config.port)")

        // Connect to server
        try await client.connect()

        // Start event processing task
        Task {
            await processEvents(client: client)
        }

        // Wait for registration
        await client.awaitRegistered()
        print("✅ Registered successfully!")

        // Join channels
        let channels = ["#bots", "#swift-irc-generated"]
        for channel in channels {
            print("→ Joining \(channel)")
            try await client.join(channel)
        }

        // Keep running
        try await Task.sleep(for: .seconds(3600))  // Run for 1 hour

        // Clean disconnect
        print("👋 Disconnecting...")
        try await client.disconnect(reason: "Goodbye!")
    }

    static func processEvents(client: Client) async {
        var messageCount = 0

        for await event in await client.events {
            switch event {
            case .connected:
                print("🔌 Connected to server")

            case .registered:
                print("📝 Registration complete")

            case .disconnected(let error):
                if let error = error {
                    print("❌ Disconnected: \(error.localizedDescription)")
                } else {
                    print("👋 Disconnected cleanly")
                }

            case .privmsg(let target, let sender, let text, let message):
                messageCount += 1

                // Log with timestamp if available
                if let time = message.tags["time"] {
                    print("[\(time)] [\(target)] <\(sender)> \(text)")
                } else {
                    print("[\(target)] <\(sender)> \(text)")
                }

                // Handle commands
                await handleCommands(
                    client: client,
                    target: target,
                    sender: sender,
                    text: text,
                    messageCount: messageCount
                )
            case .notice(let target, let sender, let text, _):
                print("[\(target)] -\(sender)- \(text)")

            case .join(let channel, let nick, _):
                print("→ \(nick) joined \(channel)")

                // Greet users who join (but not ourselves)
                let currentNick = await client.getCurrentNick()
                if nick != currentNick {
                    Task {
                        try? await client.privmsg(channel, "Welcome, \(nick)! 👋")
                    }
                }

            case .part(let channel, let nick, let reason, _):
                if let reason = reason {
                    print("← \(nick) left \(channel): \(reason)")
                } else {
                    print("← \(nick) left \(channel)")
                }

            case .quit(let nick, let reason, _):
                if let reason = reason {
                    print("⚠️ \(nick) quit: \(reason)")
                } else {
                    print("⚠️ \(nick) quit")
                }

            case .kick(let channel, let kicked, let by, let reason, _):
                print(
                    "⚡ \(kicked) was kicked from \(channel) by \(by)"
                        + (reason.map { ": \($0)" } ?? ""))

            case .nick(let oldNick, let newNick, _):
                print("✏️ \(oldNick) is now known as \(newNick)")

            case .topic(let channel, let topic, _):
                if let topic = topic {
                    print("📌 Topic for \(channel): \(topic)")
                } else {
                    print("📌 No topic set for \(channel)")
                }

            case .mode(let target, let modes, _):
                print("🔧 Mode \(modes) on \(target)")

            case .error(let error):
                print("❌ Error: \(error)")

            case .message(let message):
                // Log any unhandled numeric replies
                if let code = message.numericCode, code >= 400 {
                    print("⚠️ Error [\(code)]: \(message.text ?? message.raw)")
                }
            }
        }
    }

    static func handleCommands(
        client: Client, target: String, sender: String, text: String, messageCount: Int
    ) async {
        // Ignore if not a command
        guard text.hasPrefix("!") else { return }

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
