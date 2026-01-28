import Foundation

public struct User: Identifiable, Sendable {
    public var nick: String
    public var username: String?
    public var hostname: String?
    public var realname: String?
    public var account: String?
    public var server: String?
    public var idleSeconds: Int?

    public var id: String { nick }
    public var isAuthenticated: Bool { account != nil }

    public enum Prefix: String, Sendable {
        case owner = "~"
        case admin = "&"
        case op = "@"
        case halfop = "%"
        case voice = "+"
    }

    public init(nick: String) {
        self.nick = nick
        self.username = nil
        self.hostname = nil
        self.realname = nil
        self.account = nil
        self.server = nil
        self.idleSeconds = nil
    }

    /// Result from applying a WHO/WHOX message, containing channel context and prefixes
    public struct WhoResult: Sendable {
        public let channel: String?
        public let prefixes: Set<Prefix>
    }

    /// Applies an IRC message to update user info
    /// Returns WhoResult with channel context and prefixes for WHO/WHOX replies, nil otherwise
    @discardableResult
    public mutating func apply(_ message: Message) -> WhoResult? {
        switch message.command {
        case "352": // WHO reply: 352 <client> <channel> <user> <host> <server> <nick> <flags> :<hopcount> <realname>
            guard message.params.count >= 8 else {
                return nil
            }
            self.nick = message.params[5]
            self.username = message.params[2]
            self.hostname = message.params[3]
            self.server = message.params[4]

            let channel = message.params[1]

            // Parse flags (format: H/G + * (ircop) + channel prefixes like @, +, %, ~, &)
            let flags = message.params[6]
            let prefixes = Self.parsePrefixes(from: flags)

            // Parse realname from trailing parameter (format: "<hopcount> <realname>")
            let trailing = message.params[7]
            if let spaceIdx = trailing.firstIndex(of: " ") {
                self.realname = String(trailing[trailing.index(after: spaceIdx)...])
            } else {
                self.realname = nil
            }

            self.account = nil
            self.idleSeconds = nil
            return WhoResult(channel: channel, prefixes: prefixes)

        case "354": // WHOX reply: 354 <client> <querytype> [custom fields based on format]
            // Common format: 354 <client> <querytype> <channel> <user> <ip> <host> <server> <nick> <flags> <hopcount> <idle> <account> :<realname>
            guard message.params.count >= 2 else {
                return nil
            }

            // Try to parse common WHOX format with account
            // Format: 354 <client> <querytype> <channel> <user> <ip> <host> <server> <nick> <flags> <hopcount> <idle> <account> :<realname>
            if message.params.count >= 13 {
                self.nick = message.params[7]
                self.username = message.params[3]
                self.hostname = message.params[5]
                self.server = message.params[6]
                self.realname = message.params.last

                let channel = message.params[2]

                // Parse flags
                let flags = message.params[8]
                let prefixes = Self.parsePrefixes(from: flags)

                // Parse account (0 means not logged in)
                let accountStr = message.params[11]
                self.account = accountStr == "0" ? nil : accountStr

                // Parse idle time
                if let idle = Int(message.params[10]) {
                    self.idleSeconds = idle
                } else {
                    self.idleSeconds = nil
                }
                return WhoResult(channel: channel, prefixes: prefixes)
            }

            // Fallback for other WHOX formats - try to extract what we can
            // This is a simplified parser that assumes nick is always present
            if message.params.count >= 3 {
                // In most WHOX formats, nick is one of the middle fields
                // We'll try to find it by looking for a parameter that looks like a nickname
                // For now, just take the 3rd parameter as nick (after client and querytype)
                self.nick = message.params[2]
                self.username = nil
                self.hostname = nil
                self.server = nil
                self.realname = message.params.last
                self.account = nil
                self.idleSeconds = nil
                return WhoResult(channel: nil, prefixes: [])
            }

            return nil
        default:
            return nil
        }
    }

    /// Parses channel prefixes from WHO/WHOX flags field
    /// Flags format: H/G (here/gone) + * (ircop) + channel prefixes (@, +, %, ~, &)
    private static func parsePrefixes(from flags: String) -> Set<Prefix> {
        var prefixes: Set<Prefix> = []

        for char in flags {
            switch char {
            case "~":
                prefixes.insert(.owner)
            case "&":
                prefixes.insert(.admin)
            case "@":
                prefixes.insert(.op)
            case "%":
                prefixes.insert(.halfop)
            case "+":
                prefixes.insert(.voice)
            default:
                break  // Ignore H, G, *, and other flags
            }
        }

        return prefixes
    }
}
