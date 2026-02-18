import Foundation

public struct User: Identifiable, Sendable {
    public var nick: String
    public var username: String?
    public var host: String?
    public var realname: String?
    public var account: String?
    public var server: String?
    public var idleSeconds: Int?

    public var id: String { nick }
    public var isAuthenticated: Bool { account != nil }

    public init(nick: String, username: String? = nil, host: String? = nil, realname: String? = nil,
                account: String? = nil, server: String? = nil, idleSeconds: Int? = nil) {
        self.nick = nick
        self.username = username
        self.host = host
        self.realname = realname
        self.account = account
        self.server = server
        self.idleSeconds = idleSeconds
    }
}
