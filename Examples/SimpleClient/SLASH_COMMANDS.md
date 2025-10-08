# Slash Commands

The SimpleClient example supports IRC slash commands in the channel input field. When you type a command starting with `/`, it will be parsed and executed on the IRC server.

## Available Commands

### Channel Management

#### `/join` or `/j`
Join a channel.

**Syntax:**
```
/join <channel> [key]
/j <channel> [key]
```

**Examples:**
```
/join #swift
/join #private secret123
/j #help
```

#### `/part` or `/leave`
Leave a channel.

**Syntax:**
```
/part <channel> [reason]
/leave <channel> [reason]
```

**Examples:**
```
/part #swift
/part #swift Goodbye everyone!
/leave #help
```

#### `/topic` or `/t`
View or set the channel topic. When used without arguments in a channel view, it operates on the current channel.

**Syntax:**
```
/topic <channel> [new topic]
/t [new topic]
```

**Examples:**
```
/topic #swift                    # View topic
/topic #swift Swift Programming  # Set topic
/t New topic for current channel # Set topic in current channel
```

#### `/names`
List users in a channel. When used without arguments in a channel view, it operates on the current channel.

**Syntax:**
```
/names <channel>
/names
```

**Examples:**
```
/names #swift
/names
```

#### `/list`
List all channels or get information about a specific channel.

**Syntax:**
```
/list [channel]
```

**Examples:**
```
/list          # List all channels
/list #swift   # Get info about #swift
```

### User Actions

#### `/kick`
Kick a user from a channel (requires operator privileges).

**Syntax:**
```
/kick <channel> <nick> [reason]
```

**Examples:**
```
/kick #swift baduser
/kick #swift spammer Spam not allowed
```

#### `/mode` or `/m`
Change channel or user modes (requires appropriate privileges).

**Syntax:**
```
/mode <target> <modes>
/m <target> <modes>
```

**Examples:**
```
/mode #swift +m              # Set channel to moderated
/mode #swift +o alice        # Give alice operator status
/mode alice +i               # Set alice as invisible
/m #swift -t                 # Remove topic protection
```

### User Information

#### `/whois` or `/wi`
Get detailed information about a user.

**Syntax:**
```
/whois <nick>
/wi <nick>
```

**Examples:**
```
/whois alice
/wi bob
```

### Messaging

#### `/msg` or `/query`
Send a private message to a user or channel.

**Syntax:**
```
/msg <target> <message>
/query <target> <message>
```

**Examples:**
```
/msg alice Hello!
/msg #swift This is a message
/query bob How are you?
```

### Connection

#### `/nick`
Change your nickname.

**Syntax:**
```
/nick <new nickname>
```

**Examples:**
```
/nick alice
/nick alice_away
```

#### `/quit`
Disconnect from the server.

**Syntax:**
```
/quit [reason]
```

**Examples:**
```
/quit
/quit Goodbye everyone!
```

## Context-Aware Commands

When you're in a channel view, some commands will automatically use the current channel if you don't specify one:

- `/topic` - Sets/views the topic for the current channel
- `/names` - Lists users in the current channel

## Implementation Details

The slash command parser is in `SlashCommand.swift`. It parses user input and creates typed command objects that are then executed by `AppState.executeSlashCommand()`.

The commands ultimately call methods on `IRC.Client`, such as:
- `client.join(_:key:)`
- `client.part(_:reason:)`
- `client.setTopic(_:topic:)`
- `client.getTopic(_:)`
- `client.kick(_:nick:reason:)`
- `client.whois(_:)`
- `client.names(_:)`
- `client.list(_:)`
- `client.privmsg(_:_:)`
- `client.send(.mode(target:modes:))`
- `client.send(.nick(_:))`
- `client.disconnect(reason:)`

## Adding New Commands

To add a new slash command:

1. Add a case to the `SlashCommand` enum in `SlashCommand.swift`
2. Add parsing logic in the `parse()` method
3. Add a helper parsing method if needed
4. Add execution logic in `AppState.executeSlashCommand()`
5. Call the appropriate `IRC.Client` method

For example, to add a `/away` command:

```swift
// In SlashCommand.swift
enum SlashCommand {
    // ... existing cases ...
    case away(message: String?)
}

// In the parse() switch statement
case "away":
    let message = args.isEmpty ? nil : args
    return .away(message: message)

// In AppState.executeSlashCommand()
case .away(let message):
    try await client.send(.away(message))
```
