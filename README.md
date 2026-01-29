# IRC

A Swift-native IRC client library built with Swift 6 concurrency.

## Requirements

- iOS 18.0+ / macOS 15.0+
- Swift 6.2+

## Installation

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/nathanborror/swift-irc-generated", branch: "main")
]
```

## Quick Start

```swift
import IRC

let config = Client.Config(
    server: "irc.libera.chat",
    port: 6697,
    useTLS: true,
    nick: "MyBot"
)

let client = Client(config: config, transport: NWTransport())
try await client.connect()

Task {
    for await event in client.events {
        switch event {
        case .registered:
            try await client.join("#channel")
        case .privmsg(let target, let sender, let text, _):
            print("[\(target)] <\(sender)> \(text)")
        default:
            break
        }
    }
}

await client.awaitRegistered()
try await client.privmsg("#channel", "Hello!")
```

## Features

- Async/await and actor-based concurrency
- IRCv3 support (CAP negotiation, SASL, message tags)
- Aggregated queries (WHOIS, NAMES, WHO, LIST, MOTD)
- TLS via Network.framework
- Built-in rate limiting
- Auto-reconnect

## Testing

Use `MockTransport` for testing without network connections. See the test suite for detailed usage examples and API coverage.

## License

MIT
