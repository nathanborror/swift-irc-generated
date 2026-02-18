import Foundation

public struct Channel: Identifiable, Sendable {
    public var name: String
    public var topic: Topic?
    public var modes: Set<Mode>
    public var modeParams: [String: String]  // mode -> parameter (e.g., "l" -> "50" for user limit)
    public var created: Date?
    public var members: [String: Set<Prefix>]  // nick -> prefixes

    public var id: String { name }

    public struct Topic: Sendable {
        public var text: String
        public var nick: String?
        public var created: Date?

        public init(text: String, nick: String? = nil, created: Date? = nil) {
            self.text = text
            self.nick = nick
            self.created = created
        }
    }

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

    public enum Prefix: String, Sendable {
        case owner = "~"
        case admin = "&"
        case op = "@"
        case halfop = "%"
        case voice = "+"
    }

    public init(name: String, topic: Topic? = nil, modes: Set<Mode>, modeParams: [String : String],
                created: Date? = nil, members: [String : Set<Prefix>]) {
        self.name = name
        self.topic = topic
        self.modes = modes
        self.modeParams = modeParams
        self.created = created
        self.members = members
    }
}
