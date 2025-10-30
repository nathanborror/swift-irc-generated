# Registered Nick Handling

This document explains how the IRC client handles registered nicknames during the connection handshake process.

## Overview

When connecting to IRC servers, some nicknames may be registered with services like NickServ and require authentication before they can be used. The client now intelligently delays sending the NICK/USER commands when SASL authentication is configured, allowing the user to authenticate before claiming their registered nickname.

## The Problem

Previously, the client would immediately send:
1. `CAP LS 302` (if capabilities requested)
2. `PASS` (if server password provided)
3. `NICK <nickname>`
4. `USER <username> ...`

If the nickname was registered and SASL authentication was configured, the server would reject the nick claim with `433 ERR_NICKNAMEINUSE` before SASL authentication could complete. The client would then append `_` to the nickname and retry, resulting in the user connecting with `nickname_` instead of their registered `nickname`.

## The Solution

The updated handshake process now checks if SASL authentication is configured and delays sending NICK/USER commands until after SASL authentication completes:

### Handshake Flow with SASL (for Registered Nicks)

```
1. Client sends: CAP LS 302
2. Server sends: CAP * LS :sasl multi-prefix extended-join ...
3. Client sends: CAP REQ :sasl multi-prefix ...
4. Server sends: CAP * ACK :sasl multi-prefix ...
5. Client sends: AUTHENTICATE PLAIN
6. Server sends: AUTHENTICATE +
7. Client sends: AUTHENTICATE <base64-credentials>
8. Server sends: 903 RPL_SASLSUCCESS
9. Client sends: NICK <nickname>        <-- Delayed until here
10. Client sends: USER <username> ...    <-- Delayed until here
11. Client sends: CAP END
12. Server sends: 001 RPL_WELCOME
```

### Handshake Flow without SASL

```
1. Client sends: CAP LS 302 (if caps requested)
2. Client sends: NICK <nickname>        <-- Sent immediately
3. Client sends: USER <username> ...    <-- Sent immediately
4. Server sends: 001 RPL_WELCOME
```

## Implementation Details

### Detection Logic

The client determines whether to delay NICK/USER based on:

```swift
let usingSASL = config.sasl != nil && config.requestedCaps.contains("sasl")
```

If `usingSASL` is `true`, the client delays sending NICK/USER until one of the following events:

1. **SASL Success (903)**: Authentication succeeded, now safe to claim nick
2. **SASL Failure (904/905/906)**: Authentication failed, send NICK/USER anyway to continue registration
3. **CAP ACK without SASL**: Server acknowledged caps but we're not using SASL
4. **CAP NAK**: Server rejected capabilities, proceed with registration

### Error Handling

#### ERR_NICKNAMEINUSE (433)

If the nickname is still in use during registration (even after SASL auth), the client appends `_` to the nickname and retries:

```swift
case "433":  // ERR_NICKNAMEINUSE
    if state == .registering {
        currentNick = currentNick + "_"
        try? await send(.nick(currentNick))
    }
```

This provides a fallback mechanism if:
- The registered nick is already in use by another connection
- SASL authentication failed but the nick is still registered
- Network issues caused timing problems

## Configuration Examples

### Example 1: Registered Nick with SASL

```swift
let config = Client.Config(
    server: "irc.libera.chat",
    port: 6697,
    useTLS: true,
    nick: "mybot",                    // Registered nickname
    username: "mybot",
    realname: "My IRC Bot",
    sasl: .plain(                      // SASL authentication
        username: "mybot",
        password: "my-nickserv-password"
    ),
    requestedCaps: [
        "sasl",                        // Must request sasl capability
        "echo-message",
        "message-tags",
        "server-time",
    ]
)

let client = Client(config: config)
try await client.connect()
await client.awaitRegistered()
// Connected with nickname "mybot" (authenticated)
```

### Example 2: Unregistered Nick (No SASL)

```swift
let config = Client.Config(
    server: "irc.libera.chat",
    port: 6697,
    useTLS: true,
    nick: "testuser",                 // Unregistered nickname
    username: "testuser",
    realname: "Test User",
    sasl: nil,                        // No SASL
    requestedCaps: []                 // No capabilities
)

let client = Client(config: config)
try await client.connect()
// NICK/USER sent immediately during handshake
```

### Example 3: Server Password (Not NickServ)

```swift
let config = Client.Config(
    server: "private.irc.server",
    port: 6667,
    useTLS: false,
    nick: "user",
    username: "user",
    realname: "User",
    password: "server-password",      // Server password (PASS command)
    sasl: nil                         // No SASL needed
)

// PASS is sent before NICK/USER
// This is for server passwords, NOT NickServ authentication
```

## Benefits

1. **Automatic Nick Claiming**: Users with registered nicks and SASL don't need manual intervention
2. **No Underscore Suffix**: Avoids connecting as `nick_` when the real nick is available after auth
3. **Fallback Handling**: Still works if SASL fails or nick is genuinely in use
4. **Backward Compatible**: Existing code without SASL continues to work as before

## Testing

To test registered nick handling:

1. Register a nickname with NickServ on your IRC server
2. Configure client with SASL credentials
3. Connect and verify you receive your registered nick
4. Try connecting without SASL to verify fallback to `nick_` behavior
5. Try connecting while already connected to verify ERR_NICKNAMEINUSE handling

## Related Files

- `Sources/IRC/Client.swift` - Main implementation
  - `performHandshake()` - Initial handshake logic
  - `handleCAP()` - Capability negotiation
  - `handleAuthenticate()` - SASL PLAIN mechanism
  - Message handler for 433, 903, 904, 905, 906

## References

- [RFC 2812 - Internet Relay Chat: Client Protocol](https://tools.ietf.org/html/rfc2812)
- [IRCv3 SASL Authentication](https://ircv3.net/specs/extensions/sasl-3.1)
- [Libera.Chat SASL Documentation](https://libera.chat/guides/sasl)