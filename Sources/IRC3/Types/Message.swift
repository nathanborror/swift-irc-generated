import Foundation

public struct Message: Sendable, Equatable {
    public var tags: [String:String]   // ircv3 tags
    public var prefix: String?         // nick!user@host or server
    public var command: String         // "PRIVMSG", "001", "RPL_WHOISUSER", etc.
    public var params: [String]        // trailing last element may contain spaces
    public var raw: String             // original line (optional)
}
