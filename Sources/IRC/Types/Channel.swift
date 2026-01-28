import Foundation

public struct Channel: Identifiable, Sendable {
    public var name: String
    public var topic: String?
    public var topicSetBy: String?
    public var topicSetAt: Date?
    public var modes: Set<Mode>
    public var modeParams: [String: String]  // mode -> parameter (e.g., "l" -> "50" for user limit)
    public var created: Date?

    public var id: String { name }

    public enum Mode: String, Sendable {
        case inviteOnly = "i"
        case moderated = "m"
        case noExternalMessages = "n"
        case `private` = "p"
        case secret = "s"
        case topicProtected = "t"
        case key = "k"
        case userLimit = "l"
    }

    public init(name: String) {
        self.name = name
        self.topic = nil
        self.topicSetBy = nil
        self.topicSetAt = nil
        self.modes = []
        self.modeParams = [:]
        self.created = nil
    }

    // MARK: - Message Application

    /// Applies an IRC message to update channel state
    /// Returns true if the message was relevant and applied, false otherwise
    @discardableResult
    public mutating func apply(_ message: Message) -> Bool {
        guard let channel = message.channel, channel == name else {
            return false
        }
        switch message.command {
        case "332": // RPL_TOPIC: 332 <client> <channel> :<topic>
            guard message.params.count >= 3 else { return false }
            topic = message.params[2]
            return true

        case "331": // RPL_NOTOPIC: 331 <client> <channel> :No topic is set
            topic = nil
            return true

        case "333": // RPL_TOPICWHOTIME: 333 <client> <channel> <nick> <timestamp>
            guard message.params.count >= 4 else { return false }
            topicSetBy = message.params[2]
            if let timestamp = TimeInterval(message.params[3]) {
                topicSetAt = Date(timeIntervalSince1970: timestamp)
            }
            return true

        case "TOPIC": // TOPIC: :<nick>!<user>@<host> TOPIC <channel> :<topic>
            guard message.params.count >= 2 else { return false }
            topic = message.params[1]
            topicSetBy = message.nick
            topicSetAt = message.timestamp ?? Date()
            return true

        case "324": // RPL_CHANNELMODEIS: 324 <client> <channel> <modes> [<mode params>]
            guard message.params.count >= 3 else { return false }
            let modeString = message.params[2]
            let (newModes, newParams) = Self.parseModes(modeString, params: Array(message.params.dropFirst(3)))
            modes = newModes
            modeParams = newParams
            return true

        case "MODE": // MODE: :<nick>!<user>@<host> MODE <channel> <modes> [<params>]
            guard message.params.count >= 2 else { return false }
            let modeString = message.params[1]
            let (newModes, newParams) = Self.parseModes(modeString, params: Array(message.params.dropFirst(2)))
            modes = newModes
            modeParams = newParams
            return true

        case "329": // RPL_CREATIONTIME: 329 <client> <channel> <timestamp>
            guard message.params.count >= 3 else { return false }
            if let timestamp = TimeInterval(message.params[2]) {
                created = Date(timeIntervalSince1970: timestamp)
            }
            return true

        default:
            return false
        }
    }

    /// Parses channel modes from MODE command or RPL_CHANNELMODEIS
    /// Mode string format: +imnst or +l 50 or +k password
    private static func parseModes(_ modeString: String, params: [String]) -> (Set<Mode>, [String: String]) {
        var modes: Set<Mode> = []
        var modeParams: [String: String] = [:]
        var paramIndex = 0
        var adding = true

        for char in modeString {
            switch char {
            case "+":
                adding = true
            case "-":
                adding = false
            default:
                if let mode = Mode(rawValue: String(char)) {
                    if adding {
                        modes.insert(mode)
                        // Handle modes that take parameters
                        if mode == .key || mode == .userLimit {
                            if paramIndex < params.count {
                                modeParams[String(char)] = params[paramIndex]
                                paramIndex += 1
                            }
                        }
                    } else {
                        modes.remove(mode)
                        modeParams.removeValue(forKey: String(char))
                    }
                }
            }
        }

        return (modes, modeParams)
    }
}
