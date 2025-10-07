import Foundation

public enum Command: Sendable {
    case raw(String)
    case nick(String)
    case user(username: String, mode: Int = 0, realname: String)
    case cap(String, [String]? = nil)
    case capEnd
    case authPlain(username: String, password: String)
    case authenticate(String)
    case ping(String)
    case pong(String)
    case join(String)
    case privmsg(String, String)
}
