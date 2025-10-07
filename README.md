# IRC

A modern, Swift-native IRC client library built with Swift 6 concurrency features.

## Features

- **Modern Swift Concurrency**: Built from the ground up with async/await, actors, and structured concurrency
- **Type-Safe**: Strongly typed messages, commands, and responses
- **AsyncStream Events**: Real-time event streaming using Swift's AsyncStream
- **IRCv3 Support**: CAP negotiation, SASL authentication, message tags, and more
- **Aggregated Queries**: Clean API for multi-message responses (WHOIS, NAMES, WHO, LIST, MOTD)
- **Rate Limiting**: Built-in configurable rate limiting to prevent flooding
- **TLS Support**: Secure connections via Network.framework
- **Actor-Isolated**: Thread-safe by design using Swift actors
- **Comprehensive Parsing**: Full IRC message parsing including tags, prefix, and parameters

## Requirements

- iOS 18.0+ / macOS 15.0+
- Swift 6.2+
- Xcode 16.0+

## Installation

### Swift Package Manager

Add the following to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/nathanborror/swift-irc-generated", branch: "main")
]
```

Or add it via Xcode: File → Add Package Dependencies

## Quick Start

```swift
import IRC

// Configure the client
let config = Client.Config(
    server: "irc.libera.chat",
    port: 6697,
    useTLS: true,
    nick: "SwiftBot",
    username: "swiftbot",
    realname: "Swift IRC Bot"
)

// Create transport and client
let transport = NWTransport()
let client = Client(config: config, transport: transport)

// Connect
try await client.connect()

// Listen for events
Task {
    for await event in client.events {
        switch event {
        case .registered:
            print("✅ Connected and registered!")
            try await client.join("#swift")

        case .privmsg(let target, let sender, let text, _):
            print("[\(target)] <\(sender)> \(text)")

            if text.hasPrefix("!hello") {
                try await client.privmsg(target, "Hello, \(sender)!")
            }

        case .join(let channel, let nick, _):
            print("→ \(nick) joined \(channel)")

        case .part(let channel, let nick, let reason, _):
            print("← \(nick) left \(channel)" + (reason.map { ": \($0)" } ?? ""))

        case .error(let error):
            print("❌ Error: \(error)")

        case .disconnected(let error):
            print("Disconnected: \(error?.localizedDescription ?? "cleanly")")

        default:
            break
        }
    }
}

// Wait for registration
await client.awaitRegistered()

// Send messages
try await client.privmsg("#swift", "Hello from Swift!")
```

## Configuration

The `Client.Config` provides extensive configuration options:

```swift
let config = Client.Config(
    server: "irc.libera.chat",
    port: 6697,
    useTLS: true,
    nick: "MyBot",
    username: "mybot",              // Defaults to nick
    realname: "My IRC Bot",         // Defaults to nick
    password: nil,                   // Server password (not NickServ)
    sasl: .plain(                    // SASL authentication
        username: "mybot",
        password: "secret"
    ),
    requestedCaps: [                 // IRCv3 capabilities
        "sasl",
        "echo-message",
        "message-tags",
        "server-time",
        "account-tag",
        "extended-join",
        "multi-prefix"
    ],
    autoReconnect: false,            // Auto-reconnect on disconnect
    reconnectDelay: 5.0,             // Seconds between reconnect attempts
    pingTimeout: 120.0,              // Seconds before ping timeout
    rateLimit: .default              // Rate limiting strategy
)
```

### Rate Limiting

Configure rate limiting to prevent flooding:

```swift
// Default: 5 messages per 2 seconds
config.rateLimit = .default

// Custom rate limit
config.rateLimit = Client.Config.RateLimit(
    messagesPerWindow: 10,
    windowDuration: 5.0
)

// No rate limiting (not recommended)
config.rateLimit = .none
```

## SASL Authentication

Authenticate with services using SASL:

```swift
// SASL PLAIN
config.sasl = .plain(
    username: "mybot",
    password: "mypassword"
)

// SASL EXTERNAL (for CertFP)
config.sasl = .external
```

## Commands

### Basic Commands

```swift
// Join/Part channels
try await client.join("#channel")
try await client.join("#secret", key: "password")
try await client.part("#channel")
try await client.part("#channel", reason: "Goodbye!")

// Send messages
try await client.privmsg("#channel", "Hello!")
try await client.notice("#channel", "Notice message")
try await client.privmsg("Username", "Private message")

// Change nick
try await client.setNick("NewNick")

// Topic management
try await client.setTopic("#channel", topic: "New topic")
try await client.getTopic("#channel")

// Channel moderation
try await client.kick("#channel", nick: "BadUser", reason: "Spam")
try await client.invite("Friend", to: "#private")
try await client.setMode("#channel", modes: "+m")
try await client.setMode("MyNick", modes: "+i")

// Away status
try await client.away("Be right back")
try await client.away() // Clear away status
```

### Aggregated Queries

Some IRC commands return multiple messages. The library aggregates these automatically:

```swift
// WHOIS - Get detailed user information
let whois = try await client.whois("SomeUser")
print("Nick: \(whois.nick)")
print("Username: \(whois.username ?? "unknown")")
print("Host: \(whois.host ?? "unknown")")
print("Real name: \(whois.realname ?? "unknown")")
print("Channels: \(whois.channels.joined(separator: ", "))")
print("Idle: \(whois.idleSeconds ?? 0) seconds")

// NAMES - Get all users in a channel
let names = try await client.names("#swift")
print("Users in \(names.channel): \(names.names.count)")
for name in names.names {
    print("  \(name)")
}

// WHO - Get detailed channel/user information
let who = try await client.who("#swift")
for entry in who.entries {
    print("\(entry.nick): \(entry.username)@\(entry.host)")
}

// LIST - Get list of channels
let list = try await client.list()
for channel in list.entries {
    print("\(channel.channel) (\(channel.userCount)): \(channel.topic)")
}

// MOTD - Get server message of the day
let motd = try await client.motd()
for line in motd.lines {
    print(line)
}
```

## Event Handling

The client provides a rich event stream:

```swift
for await event in client.events {
    switch event {
    case .connected:
        print("Connected to server")

    case .registered:
        print("Registration complete")

    case .disconnected(let error):
        print("Disconnected: \(error?.localizedDescription ?? "cleanly")")

    case .privmsg(let target, let sender, let text, let message):
        // target: channel or your nick
        // sender: who sent it
        // text: message content
        // message: full Message struct with tags, etc.
        print("[\(target)] <\(sender)> \(text)")

    case .notice(let target, let sender, let text, _):
        print("[\(target)] -\(sender)- \(text)")

    case .join(let channel, let nick, _):
        print("\(nick) joined \(channel)")

    case .part(let channel, let nick, let reason, _):
        print("\(nick) left \(channel)")

    case .quit(let nick, let reason, _):
        print("\(nick) quit: \(reason ?? "")")

    case .kick(let channel, let kicked, let by, let reason, _):
        print("\(kicked) was kicked from \(channel) by \(by): \(reason ?? "")")

    case .nick(let oldNick, let newNick, _):
        print("\(oldNick) is now known as \(newNick)")

    case .topic(let channel, let topic, _):
        print("Topic for \(channel): \(topic ?? "no topic")")

    case .mode(let target, let modes, _):
        print("Mode \(modes) on \(target)")

    case .error(let error):
        print("Error: \(error)")

    case .message(let message):
        // All raw messages come through here too
        // Use for handling custom numeric replies or extensions
        print("Raw: \(message.raw)")
    }
}
```

## Message Parsing

Messages are automatically parsed with rich metadata:

```swift
let message = Message.parse(":nick!user@host PRIVMSG #channel :Hello world")

print(message.prefix)        // "nick!user@host"
print(message.nick)          // "nick"
print(message.user)          // "user"
print(message.host)          // "host"
print(message.command)       // "PRIVMSG"
print(message.params)        // ["#channel", "Hello world"]
print(message.target)        // "#channel"
print(message.text)          // "Hello world"
print(message.channel)       // "#channel"

// IRCv3 tags
let taggedMessage = Message.parse(
    "@time=2024-01-01T12:00:00.000Z :nick!user@host PRIVMSG #channel :Hi"
)
print(taggedMessage.tags["time"]) // "2024-01-01T12:00:00.000Z"

// Numeric replies
let numericMsg = Message.parse(":server 001 nick :Welcome!")
print(numericMsg.isNumeric)       // true
print(numericMsg.numericCode)     // 1
print(numericMsg.numericName)     // "RPL_WELCOME"
```

## Architecture

### Core Components

1. **Client (Actor)**: Main interface, handles connection lifecycle and message routing
2. **Transport (Protocol)**: Abstraction for network I/O
   - `NWTransport`: Production implementation using Network.framework
   - `MockTransport`: Testing implementation with in-memory streams
3. **Message**: Parsed IRC message with tags, prefix, command, and parameters
4. **Command**: Type-safe outgoing command builder
5. **Aggregations**: Actors that collect multi-message responses

### Async Architecture

The library leverages Swift's modern concurrency features:

- **Actor isolation** ensures thread-safe state management
- **AsyncStream** provides backpressure-aware event streaming
- **Structured concurrency** with task groups for managing I/O loops
- **Continuations** bridge callback-based network APIs with async/await

### Message Flow

```
┌─────────────┐
│   Network   │
└──────┬──────┘
       │ readLine()
       ▼
┌─────────────┐
│ Read Loop   │
└──────┬──────┘
       │ parse()
       ▼
┌─────────────┐
│   Message   │
└──────┬──────┘
       │
       ├─────────► Aggregations (WHOIS, NAMES, etc.)
       │
       ├─────────► Protocol Handlers (CAP, SASL, PING)
       │
       └─────────► Event Stream (user consumption)
```

### Connection Lifecycle

1. **Disconnected** → `connect()`
2. **Connecting** → Transport opens socket
3. **Connected** → Start I/O loops
4. **Registering** → CAP LS, NICK, USER, SASL (if configured)
5. **Registered** → Ready for commands, emit `.registered` event
6. **Disconnected** → Cleanup, emit `.disconnected` event

## Testing

Use `MockTransport` for testing without real connections:

```swift
import IRC

let transport = MockTransport()
let client = Client(config: config, transport: transport)

// Queue server responses
await transport.queueRead(":server 001 nick :Welcome!")
await transport.queueRead(":server 376 nick :End of MOTD")

try await client.connect()
await client.awaitRegistered()

// Verify sent commands
let written = await transport.getWrittenLines()
XCTAssertTrue(written.contains("NICK SwiftBot"))
```

## Examples

### Simple Echo Bot

```swift
let transport = NWTransport()
let config = Client.Config(
    server: "irc.libera.chat",
    port: 6697,
    useTLS: true,
    nick: "EchoBot"
)
let client = Client(config: config, transport: transport)

try await client.connect()
await client.awaitRegistered()
try await client.join("#bots")

for await event in client.events {
    if case .privmsg(let target, let sender, let text, _) = event {
        if text.hasPrefix("!echo ") {
            let reply = String(text.dropFirst(6))
            try await client.privmsg(target, "\(sender): \(reply)")
        }
    }
}
```

### URL Title Bot

```swift
import Foundation

for await event in client.events {
    if case .privmsg(let target, _, let text, _) = event {
        if let url = extractURL(from: text) {
            if let title = try? await fetchTitle(from: url) {
                try await client.privmsg(target, "📎 \(title)")
            }
        }
    }
}

func extractURL(from text: String) -> URL? {
    // URL extraction logic
}

func fetchTitle(from url: URL) async throws -> String {
    // Fetch and parse HTML title
}
```

### Channel Logger

```swift
import Foundation

let logger = FileHandle(forWritingAtPath: "irc.log")!

for await event in client.events {
    let timestamp = ISO8601DateFormatter().string(from: Date())

    switch event {
    case .privmsg(let target, let sender, let text, _):
        let line = "[\(timestamp)] [\(target)] <\(sender)> \(text)\n"
        logger.write(line.data(using: .utf8)!)

    case .join(let channel, let nick, _):
        let line = "[\(timestamp)] [\(channel)] → \(nick) joined\n"
        logger.write(line.data(using: .utf8)!)

    // ... other events

    default:
        break
    }
}
```

## Low-Level Access

For advanced use cases, you can send raw IRC commands:

```swift
// Send raw command
try await client.sendRaw("PRIVMSG #channel :Hello")

// Use Command enum (encodes automatically)
try await client.send(.raw("MODE #channel +m"))

// Access raw messages
for await event in client.events {
    if case .message(let message) = event {
        // Handle any message type
        print("Command: \(message.command)")
        print("Params: \(message.params)")
        print("Raw: \(message.raw)")

        // Check numeric codes
        if let code = message.numericCode {
            switch code {
            case 353: // RPL_NAMREPLY
                print("Names: \(message.text ?? "")")
            default:
                break
            }
        }
    }
}
```

## Error Handling

```swift
do {
    try await client.connect()
    await client.awaitRegistered()
    try await client.join("#channel")
} catch let error as TransportError {
    print("Transport error: \(error)")
} catch let error as ClientError {
    print("Client error: \(error)")
} catch {
    print("Unknown error: \(error)")
}
```

## Best Practices

1. **Always await registration** before sending commands (except CAP, NICK, USER, PASS)
2. **Handle disconnections** gracefully and implement reconnection logic if needed
3. **Use rate limiting** to avoid being kicked for flooding
4. **Process events asynchronously** using separate tasks for long-running operations
5. **Clean up** by calling `disconnect()` when done

## Performance Considerations

- The client uses a single actor for thread safety, which serializes all operations
- Event processing is async, so slow handlers won't block the read loop
- Rate limiting prevents server-side throttling but adds latency to high-volume bots
- Message parsing is lazy where possible (tags, prefix parsing)

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Add tests for new functionality
4. Ensure all tests pass
5. Submit a pull request

## License

MIT License - see LICENSE file for details

## Resources

- [IRC RFC 1459](https://tools.ietf.org/html/rfc1459)
- [IRC RFC 2812](https://tools.ietf.org/html/rfc2812)
- [IRCv3 Specifications](https://ircv3.net/irc/)
- [Swift Concurrency](https://docs.swift.org/swift-book/LanguageGuide/Concurrency.html)

## Credits

Built with ❤️ using Swift 6 and modern concurrency features.
