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

    public init(nick: String) {
        self.nick = nick
        self.username = nil
        self.hostname = nil
        self.realname = nil
        self.account = nil
        self.server = nil
        self.idleSeconds = nil
    }
}
