# IRC Architecture

This document explains the architectural decisions and design patterns used in the IRC library.

## Core Principles

1. **Safety First**: Use Swift's type system and actor isolation to prevent data races
2. **Modern Concurrency**: Leverage async/await, actors, and structured concurrency throughout
3. **Ergonomic API**: Provide a clean, Swift-native interface that feels natural
4. **IRC Reality**: Handle the asynchronous, multi-message nature of IRC elegantly

## Design Challenges

IRC presents unique challenges for client library design:

### 1. Asynchronous Message Passing

Unlike HTTP, IRC is a streaming protocol where:
- You send a command but don't know when (or if) a response will arrive
- A single command may trigger multiple response messages
- Responses can be interleaved with other server messages
- Some responses never complete (servers can be slow or buggy)

**Our Solution**: Use Swift's `AsyncStream` for events and actor-based aggregators for multi-message responses.

### 2. Connection State Management

The IRC connection lifecycle is complex:
- Initial connection
- CAP negotiation (optional, IRCv3)
- SASL authentication (optional)
- NICK/USER registration
- Only then can you send most commands

**Our Solution**: Actor-based state machine with registration gate using continuations.

### 3. Rate Limiting

IRC servers will disconnect clients that send too many messages too quickly.

**Our Solution**: Token bucket rate limiter built into the client actor.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│                        User Code                        │
└────────────────┬────────────────────────────────────────┘
                 │
                 │ async/await calls
                 │ AsyncStream<Event>
                 │
┌────────────────▼───────────────────────────────────────┐
│                      Client (Actor)                    │
│  ┌──────────────────────────────────────────────────┐  │
│  │ State Management                                 │  │
│  │ - Connection state machine                       │  │
│  │ - Registration gate (continuations)              │  │
│  │ - CAP/SASL negotiation                           │  │
│  └──────────────────────────────────────────────────┘  │
│  ┌──────────────────────────────────────────────────┐  │
│  │ Message Processing                               │  │
│  │ - Route to aggregators                           │  │
│  │ - Handle protocol messages (PING, CAP, etc.)     │  │
│  │ - Emit events to stream                          │  │
│  └──────────────────────────────────────────────────┘  │
│  ┌──────────────────────────────────────────────────┐  │
│  │ Aggregation Management                           │  │
│  │ - Track pending WHOIS, NAMES, WHO, etc.          │  │
│  │ - Complete aggregations on end messages          │  │
│  └──────────────────────────────────────────────────┘  │
│  ┌──────────────────────────────────────────────────┐  │
│  │ Background Tasks                                 │  │
│  │ - Read loop                                      │  │
│  │ - Write loop (with rate limiting)                │  │
│  │ - Ping/pong keepalive                            │  │
│  └──────────────────────────────────────────────────┘  │
└────────────────┬───────────────────────────────────────┘
                 │
                 │ async calls
                 │
┌────────────────▼───────────────────────────────────────┐
│                  Transport (Protocol)                  │
│  ┌──────────────────────────────────────────────────┐  │
│  │ NWTransport (Production)                         │  │
│  │ - Network.framework wrapper                      │  │
│  │ - TLS support                                    │  │
│  │ - Line buffering (handles \r\n)                  │  │
│  └──────────────────────────────────────────────────┘  │
│  ┌──────────────────────────────────────────────────┐  │
│  │ MockTransport (Testing)                          │  │
│  │ - In-memory implementation                       │  │
│  │ - Controllable for tests                         │  │
│  └──────────────────────────────────────────────────┘  │
└────────────────┬───────────────────────────────────────┘
                 │
                 │ Network I/O
                 │
┌────────────────▼───────────────────────────────────────┐
│                      IRC Server                        │
└────────────────────────────────────────────────────────┘
```

## Key Components

### Client Actor

The `Client` is an actor, which means:
- All access is serialized (no data races)
- Methods are async by default
- State mutations are isolated

**State Machine**:
```
disconnected → connecting → connected → registering → registered
                    ↓
                  error
```

**Responsibilities**:
- Connection lifecycle management
- Message routing and processing
- Protocol state (CAP negotiation, SASL)
- Event emission
- Rate limiting
- Aggregation coordination

**Key Design Decision**: Why an actor?
- IRC state is inherently mutable (connection status, nick, channels)
- Multiple concurrent operations (reading, writing, user commands)
- Actor isolation prevents race conditions automatically
- Async/await makes the code sequential and readable

### Transport Protocol

Abstraction over network I/O with two implementations:

**NWTransport (Production)**:
- Uses Apple's Network.framework
- Handles TLS automatically
- Proper line buffering (accumulates data until \r\n)
- Also an actor for thread safety

**MockTransport (Testing)**:
- In-memory queues
- Controllable responses
- No actual network I/O

**Key Design Decision**: Why a protocol?
- Testability: Mock the network layer
- Portability: Could implement Linux version using SwiftNIO
- Separation of concerns: Client doesn't know about sockets

### Message Parsing

`Message` is a value type (struct) representing a parsed IRC message:

```swift
public struct Message: Sendable, Equatable {
    public var tags: [String: String]  // IRCv3
    public var prefix: String?          // :nick!user@host
    public var command: String          // PRIVMSG, 001, etc.
    public var params: [String]
    public var raw: String
}
```

**Key Design Decision**: Why a struct?
- Sendable by default (can cross actor boundaries)
- Value semantics (no shared mutable state)
- Cheap to copy (copy-on-write for collections)
- Natural for data transfer objects

**Parsing Strategy**:
- Stateless static method `Message.parse()`
- Single pass through the string
- Handles all IRC formats (tags, prefix, params, trailing)
- Provides convenience accessors (`.nick`, `.channel`, `.text`)

### Command Encoding

`Command` enum represents outgoing IRC commands:

```swift
public enum Command: Sendable {
    case nick(String)
    case join(String, key: String? = nil)
    case privmsg(String, String)
    // ... etc
}
```

**Key Design Decision**: Why an enum?
- Type-safe command construction
- Associated values for parameters
- Exhaustive switching
- Encoding logic encapsulated in `encode()` method

### Aggregations

The most interesting design challenge: handling multi-message responses.

**Problem**: Commands like WHOIS return multiple messages:
```
→ WHOIS user
← 311 user username host * :Real Name
← 312 user server.name :Server Info
← 319 user :#channel1 #channel2
← 318 user :End of WHOIS
```

**Solution**: Actor-based aggregators that accumulate messages until complete.

```swift
public actor WhoisAggregation: AnyAggregation {
    public struct Result: Sendable { ... }

    public func feed(_ message: Message) async {
        // Accumulate data from each message
    }

    nonisolated public func isDone(_ message: Message) -> Bool {
        // Check if this is the end message (318)
    }

    public func wait() async throws -> Result {
        // Suspend until complete
    }
}
```

**Flow**:
1. User calls `client.whois("user")`
2. Client creates `WhoisAggregation` and stores it
3. Client sends WHOIS command
4. Read loop receives messages
5. Each message is fed to matching aggregations
6. When end message (318) arrives, aggregation completes
7. Continuation resumes, returning aggregated result

**Key Design Decision**: Why actors for aggregations?
- Mutable state (accumulating results)
- Accessed from read loop (different task)
- `nonisolated` for `isDone()` since it's stateless
- Continuation-based waiting for clean async API

### Event Streaming

Events are delivered via `AsyncStream`:

```swift
public let events: AsyncStream<Event>

for await event in client.events {
    switch event {
    case .privmsg(let target, let sender, let text, _):
        // Handle message
    }
}
```

**Key Design Decision**: Why AsyncStream?
- Backpressure: slow consumers don't overwhelm memory
- Natural async iteration
- Can be consumed from multiple tasks
- Continuation-based: easy to yield events from actor

**Event Flow**:
```
Network → Read Loop → Parse → Handle → Route → Emit Event
                                 ↓
                           Aggregations
```

### Rate Limiting

Token bucket algorithm:

```swift
private var rateLimitTokens: Int
private var lastRateLimitRefill: Date

private func applyRateLimit() async {
    // Refill tokens based on elapsed time
    // Wait if no tokens available
    rateLimitTokens -= 1
}
```

Every outgoing message calls `applyRateLimit()`, which:
1. Refills tokens based on time elapsed
2. Waits if no tokens available
3. Consumes a token

**Key Design Decision**: Why token bucket?
- Allows bursts (good UX for command sequences)
- Prevents sustained flooding
- Simple to implement
- Configurable per-use-case

## Concurrency Model

### Task Structure

```
Main Task (Client.connect)
├─ Read Loop Task
│  └─ Spawns tasks for slow event handlers
├─ Write Loop Task
│  └─ Rate limits and sends queued messages
└─ Ping Loop Task
   └─ Sends periodic PINGs, checks for timeout
```

**Key Design Decision**: Detached tasks for loops
- Long-running background work
- Not tied to connect() call lifetime
- Cancelled explicitly on disconnect
- No structured concurrency needed (no child tasks)

### Synchronization Primitives

1. **Actor Isolation**: Client, Transport, Aggregations
2. **Continuations**: Registration gate, aggregation completion
3. **AsyncStream**: Event delivery
4. **Sendable**: All shared types

**No locks or semaphores**: Swift concurrency handles it all!

### Registration Gate

Many commands can only be sent after registration:

```swift
public func join(_ channel: String) async throws {
    await awaitRegistered()  // Suspend until registered
    try await send(.join(channel))
}

private func awaitRegistered() async {
    if isRegistered { return }
    await withCheckedContinuation { continuation in
        registrationAwaiters.append(continuation)
    }
}

private func markRegistered() {
    for continuation in registrationAwaiters {
        continuation.resume()
    }
    registrationAwaiters.removeAll()
}
```

When RPL_WELCOME (001) arrives, all waiting tasks resume simultaneously.

**Key Design Decision**: Continuations for blocking
- Natural async waiting
- No polling
- No timers
- Multiple waiters supported

## Error Handling

Three error types:

1. **TransportError**: Network/I/O failures
2. **ClientError**: Protocol/state errors
3. **Events**: Error events in stream

**Strategy**:
- Throws from public APIs (connect, send, etc.)
- Error events for async problems (ping timeout)
- Cleanup on any error

**Key Design Decision**: Mix of throws and events
- Throws: direct response to user action
- Events: async server issues
- Always emit `.disconnected(Error?)` on cleanup

## Testing Strategy

1. **Unit Tests**: Message parsing, command encoding
2. **MockTransport**: Integration tests without network
3. **Real Connection**: Manual testing with actual servers

**Key Design Decision**: Protocol-based transport
- Easy to mock
- Tests don't need network
- Fast, deterministic tests

## Performance Considerations

### Memory

- Messages are small structs (copied cheaply)
- Events streamed, not buffered
- Aggregations cleaned up on completion
- Write queue is array (not allocating per-message)

### Latency

- Rate limiting adds delay (intentional)
- Actor serialization negligible for IRC speeds
- Network I/O dominates everything else

### Throughput

- Single connection, single actor
- Not designed for high throughput
- IRC servers rate-limit anyway
- Typical usage: 1-10 messages/second

## Trade-offs

### Actor Serialization

**Pro**: Thread-safe, simple
**Con**: Can't handle messages truly in parallel

**Verdict**: IRC is inherently sequential anyway.

### AsyncStream Backpressure

**Pro**: Can't overwhelm slow consumers
**Con**: Slow consumers can block read loop

**Verdict**: Emit events quickly, spawn tasks for slow work.

### Aggregation Memory

**Pro**: Clean API for multi-message responses
**Con**: Memory per pending aggregation

**Verdict**: Timeouts and cleanup on disconnect prevent leaks.

### Single Actor Design

**Pro**: Simple, safe, easy to reason about
**Con**: All operations serialized

**Verdict**: Right for IRC (low throughput, shared state).

## Future Enhancements

Potential improvements:

1. **Auto-reconnect**: Handle disconnect/reconnect automatically
2. **Channel State**: Track channel members, modes, etc.
3. **DCC Support**: File transfers (requires separate socket)
4. **IRCv3 Extensions**: More cap support (batch, chathistory, etc.)
5. **Multiple Servers**: Connection pool for bouncers
6. **Metrics**: Connection stats, message counts, etc.

## Conclusion

The IRC library demonstrates how Swift's modern concurrency features naturally solve the challenges of IRC client design:

- **Actors** provide safe mutable state
- **Async/await** makes sequential async code readable
- **Continuations** bridge callback-based patterns
- **AsyncStream** delivers events with backpressure
- **Sendable** ensures thread-safe data sharing

The result is a type-safe, ergonomic, modern Swift IRC library that handles the protocol's asynchronous, multi-message nature elegantly.
