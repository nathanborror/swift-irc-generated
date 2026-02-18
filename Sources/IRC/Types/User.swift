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

    public init?(mask: String) {
        guard !mask.isEmpty else { return nil }

        let bangIdx = mask.firstIndex(of: "!")
        let nick = String(mask[..<(bangIdx ?? mask.endIndex)])
        guard !nick.isEmpty else {
            return nil
        }

        guard let bangIdx else {
            self.init(nick: nick)
            return
        }

        let remainder = mask[mask.index(after: bangIdx)...]
        guard let atIdx = remainder.firstIndex(of: "@") else {
            let username = String(remainder)
            self.init(nick: nick, username: username.isEmpty ? nil : username)
            return
        }

        let username = String(remainder[..<atIdx])
        let host = String(remainder[remainder.index(after: atIdx)...])

        self.init(
            nick: nick,
            username: username.isEmpty ? nil : username,
            host: host.isEmpty ? nil : host
        )
    }
}
