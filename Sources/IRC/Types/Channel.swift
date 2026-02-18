import Foundation

public struct Channel: Identifiable, Sendable {
    public var name: String
    public var topic: String?
    public var topicSetBy: String?
    public var topicSetAt: Date?
    public var modes: Set<Mode>
    public var modeParams: [String: String]  // mode -> parameter (e.g., "l" -> "50" for user limit)
    public var created: Date?
    public var members: [String: Set<Prefix>]  // nick -> prefixes

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

    public enum Prefix: String, Sendable {
        case owner = "~"
        case admin = "&"
        case op = "@"
        case halfop = "%"
        case voice = "+"
    }

    public init(name: String) {
        self.name = name
        self.topic = nil
        self.topicSetBy = nil
        self.topicSetAt = nil
        self.modes = []
        self.modeParams = [:]
        self.created = nil
        self.members = [:]
    }
}
