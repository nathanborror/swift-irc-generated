import Foundation

public struct Message: Sendable, Equatable {
    public var tags: [String: String]  // IRCv3 tags
    public var prefix: String?  // nick!user@host or server
    public var command: String  // "PRIVMSG", "001", "RPL_WHOISUSER", etc.
    public var params: [String]  // trailing last element may contain spaces
    public var raw: String  // original line

    public init(
        tags: [String: String] = [:], prefix: String? = nil, command: String, params: [String] = [],
        raw: String = ""
    ) {
        self.tags = tags
        self.prefix = prefix
        self.command = command
        self.params = params
        self.raw = raw
    }
}

// MARK: - Parsing

extension Message {
    /// Parses an IRC protocol line into a Message
    public static func parse(_ line: String) -> Message {
        let raw = line.trimmingCharacters(in: .whitespacesAndNewlines)
        var tags: [String: String] = [:]
        var prefix: String?
        var command = ""
        var params: [String] = []

        var remaining = raw

        // Parse tags (@tag1=value1;tag2=value2)
        if remaining.hasPrefix("@") {
            if let spaceIdx = remaining.firstIndex(of: " ") {
                let tagString = String(
                    remaining[remaining.index(after: remaining.startIndex)..<spaceIdx])
                tags = parseTags(tagString)
                remaining = String(remaining[remaining.index(after: spaceIdx)...])
                    .trimmingCharacters(in: .whitespaces)
            }
        }

        // Parse prefix (:nick!user@host or :server.name)
        if remaining.hasPrefix(":") {
            if let spaceIdx = remaining.firstIndex(of: " ") {
                prefix = String(remaining[remaining.index(after: remaining.startIndex)..<spaceIdx])
                remaining = String(remaining[remaining.index(after: spaceIdx)...])
                    .trimmingCharacters(in: .whitespaces)
            }
        }

        // Parse command
        if let spaceIdx = remaining.firstIndex(of: " ") {
            command = String(remaining[..<spaceIdx])
            remaining = String(remaining[remaining.index(after: spaceIdx)...]).trimmingCharacters(
                in: .whitespaces)
        } else {
            command = remaining
            remaining = ""
        }

        // Parse params
        while !remaining.isEmpty {
            if remaining.hasPrefix(":") {
                // Trailing parameter (rest of line)
                params.append(String(remaining.dropFirst()))
                break
            } else if let spaceIdx = remaining.firstIndex(of: " ") {
                params.append(String(remaining[..<spaceIdx]))
                remaining = String(remaining[remaining.index(after: spaceIdx)...])
                    .trimmingCharacters(in: .whitespaces)
            } else {
                params.append(remaining)
                break
            }
        }

        return Message(tags: tags, prefix: prefix, command: command, params: params, raw: raw)
    }

    private static func parseTags(_ tagString: String) -> [String: String] {
        var tags: [String: String] = [:]
        let pairs = tagString.split(separator: ";")
        for pair in pairs {
            if let eqIdx = pair.firstIndex(of: "=") {
                let key = String(pair[..<eqIdx])
                let value = String(pair[pair.index(after: eqIdx)...])
                tags[key] = unescapeTagValue(value)
            } else {
                tags[String(pair)] = ""
            }
        }
        return tags
    }

    private static func unescapeTagValue(_ value: String) -> String {
        var result = ""
        var iterator = value.makeIterator()
        while let char = iterator.next() {
            if char == "\\" {
                if let next = iterator.next() {
                    switch next {
                    case ":": result.append(";")
                    case "s": result.append(" ")
                    case "\\": result.append("\\")
                    case "r": result.append("\r")
                    case "n": result.append("\n")
                    default: result.append(next)
                    }
                }
            } else {
                result.append(char)
            }
        }
        return result
    }
}

// MARK: - Helpers

extension Message {

    public var user: User? {
        guard let prefix else { return nil }
        return User(mask: prefix)
    }

    public var nick: String? {
        user?.nick
    }

    /// Gets the target of a message (first param for most commands)
    public var target: String? {
        return params.first
    }

    /// Gets the text content (usually the last param, which is the trailing parameter)
    public var text: String? {
        return params.last
    }

    /// Returns the channel for channel-related messages
    public var channel: String? {
        // For JOIN, PART, TOPIC, etc., the channel is usually the first param
        switch command.uppercased() {
        case "JOIN", "PART", "TOPIC", "NAMES", "MODE", "KICK":
            return params.first
        case "PRIVMSG", "NOTICE":
            // Could be channel or user
            if let first = params.first, first.hasPrefix("#") || first.hasPrefix("&") {
                return first
            }
            return nil
        default:
            // Handle numeric replies where channel is in params[1]
            // 324 RPL_CHANNELMODEIS, 329 RPL_CREATIONTIME, 331 RPL_NOTOPIC,
            // 332 RPL_TOPIC, 333 RPL_TOPICWHOTIME, 353 RPL_NAMREPLY, 366 RPL_ENDOFNAMES
            if let code = numericCode {
                switch code {
                case 324, 329, 331, 332, 333, 353, 366:
                    if params.count >= 2 {
                        return params[1]
                    }
                default:
                    break
                }
            }
            return nil
        }
    }

    /// Checks if this is a numeric reply
    public var isNumeric: Bool {
        return Int(command) != nil
    }

    /// Gets the numeric code if this is a numeric reply
    public var numericCode: Int? {
        return Int(command)
    }

    /// Gets the symbolic name for a numeric reply (e.g., "001" -> "RPL_WELCOME")
    public var numericName: String? {
        guard let code = numericCode else { return nil }
        return NumericReply(rawValue: code)?.name
    }

    /// Parses and returns the timestamp from the IRCv3 'time' tag if available
    /// Handles both formats: with fractional seconds (2023-01-15T10:30:00.123Z)
    /// and without (2023-01-15T10:30:00Z)
    public var timestamp: Date? {
        guard let timeTag = tags["time"] else { return nil }
        let formatter = ISO8601DateFormatter()
        // Try with fractional seconds first
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: timeTag) {
            return date
        }
        // Fall back to without fractional seconds
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: timeTag)
    }
}

// MARK: - Numeric Reply Codes

extension Message {

    /// IRC numeric reply codes
    public enum NumericReply: Int {

        // Connection/Welcome (001-099)
        case RPL_WELCOME = 1
        case RPL_YOURHOST = 2
        case RPL_CREATED = 3
        case RPL_MYINFO = 4
        case RPL_ISUPPORT = 5
        case RPL_BOUNCE = 10

        // Statistics (200-299)
        case RPL_STATSCOMMANDS = 212
        case RPL_ENDOFSTATS = 219
        case RPL_UMODEIS = 221
        case RPL_STATSUPTIME = 242
        case RPL_LUSERCLIENT = 251
        case RPL_LUSEROP = 252
        case RPL_LUSERUNKNOWN = 253
        case RPL_LUSERCHANNELS = 254
        case RPL_LUSERME = 255
        case RPL_ADMINME = 256
        case RPL_ADMINLOC1 = 257
        case RPL_ADMINLOC2 = 258
        case RPL_ADMINEMAIL = 259

        // Server/Network Info (300-399)
        case RPL_NONE = 300
        case RPL_AWAY = 301
        case RPL_USERHOST = 302
        case RPL_ISON = 303
        case RPL_UNAWAY = 305
        case RPL_NOWAWAY = 306
        case RPL_WHOISUSER = 311
        case RPL_WHOISSERVER = 312
        case RPL_WHOISOPERATOR = 313
        case RPL_WHOWASUSER = 314
        case RPL_ENDOFWHO = 315
        case RPL_WHOISIDLE = 317
        case RPL_ENDOFWHOIS = 318
        case RPL_WHOISCHANNELS = 319
        case RPL_LISTSTART = 321
        case RPL_LIST = 322
        case RPL_LISTEND = 323
        case RPL_CHANNELMODEIS = 324
        case RPL_CREATIONTIME = 329
        case RPL_NOTOPIC = 331
        case RPL_TOPIC = 332
        case RPL_TOPICWHOTIME = 333
        case RPL_INVITING = 341
        case RPL_INVITELIST = 346
        case RPL_ENDOFINVITELIST = 347
        case RPL_EXCEPTLIST = 348
        case RPL_ENDOFEXCEPTLIST = 349
        case RPL_VERSION = 351
        case RPL_WHOREPLY = 352
        case RPL_NAMREPLY = 353
        case RPL_LINKS = 364
        case RPL_ENDOFLINKS = 365
        case RPL_ENDOFNAMES = 366
        case RPL_BANLIST = 367
        case RPL_ENDOFBANLIST = 368
        case RPL_ENDOFWHOWAS = 369
        case RPL_INFO = 371
        case RPL_ENDOFINFO = 374
        case RPL_MOTDSTART = 375
        case RPL_MOTD = 372
        case RPL_ENDOFMOTD = 376
        case RPL_YOUREOPER = 381
        case RPL_REHASHING = 382
        case RPL_TIME = 391

        // Errors (400-599)
        case ERR_NOSUCHNICK = 401
        case ERR_NOSUCHSERVER = 402
        case ERR_NOSUCHCHANNEL = 403
        case ERR_CANNOTSENDTOCHAN = 404
        case ERR_TOOMANYCHANNELS = 405
        case ERR_WASNOSUCHNICK = 406
        case ERR_TOOMANYTARGETS = 407
        case ERR_NOORIGIN = 409
        case ERR_NORECIPIENT = 411
        case ERR_NOTEXTTOSEND = 412
        case ERR_NOTOPLEVEL = 413
        case ERR_WILDTOPLEVEL = 414
        case ERR_UNKNOWNCOMMAND = 421
        case ERR_NOMOTD = 422
        case ERR_NOADMININFO = 423
        case ERR_NONICKNAMEGIVEN = 431
        case ERR_ERRONEUSNICKNAME = 432
        case ERR_NICKNAMEINUSE = 433
        case ERR_NICKCOLLISION = 436
        case ERR_USERNOTINCHANNEL = 441
        case ERR_NOTONCHANNEL = 442
        case ERR_USERONCHANNEL = 443
        case ERR_NOTREGISTERED = 451
        case ERR_NEEDMOREPARAMS = 461
        case ERR_ALREADYREGISTERED = 462
        case ERR_PASSWDMISMATCH = 464
        case ERR_YOUREBANNEDCREEP = 465
        case ERR_KEYSET = 467
        case ERR_CHANNELISFULL = 471
        case ERR_UNKNOWNMODE = 472
        case ERR_INVITEONLYCHAN = 473
        case ERR_BANNEDFROMCHAN = 474
        case ERR_BADCHANNELKEY = 475
        case ERR_BADCHANMASK = 476
        case ERR_NOPRIVILEGES = 481
        case ERR_CHANOPRIVSNEEDED = 482
        case ERR_CANTKILLSERVER = 483
        case ERR_NOOPERHOST = 491
        case ERR_UMODEUNKNOWNFLAG = 501
        case ERR_USERSDONTMATCH = 502

        // SASL (900-909)
        case RPL_LOGGEDIN = 900
        case RPL_LOGGEDOUT = 901
        case RPL_SASLSUCCESS = 903
        case ERR_SASLFAIL = 904
        case ERR_SASLTOOLONG = 905
        case ERR_SASLABORTED = 906
        case ERR_SASLALREADY = 907

        /// Maps numeric codes to their symbolic names
        public var name: String {
            switch self {
            case .RPL_WELCOME: "RPL_WELCOME"
            case .RPL_YOURHOST: "RPL_YOURHOST"
            case .RPL_CREATED: "RPL_CREATED"
            case .RPL_MYINFO: "RPL_MYINFO"
            case .RPL_ISUPPORT: "RPL_ISUPPORT"
            case .RPL_BOUNCE: "RPL_BOUNCE"

            case .RPL_STATSCOMMANDS: "RPL_STATSCOMMANDS"
            case .RPL_ENDOFSTATS: "RPL_ENDOFSTATS"
            case .RPL_UMODEIS: "RPL_UMODEIS"
            case .RPL_STATSUPTIME: "RPL_STATSUPTIME"
            case .RPL_LUSERCLIENT: "RPL_LUSERCLIENT"
            case .RPL_LUSEROP: "RPL_LUSEROP"
            case .RPL_LUSERUNKNOWN: "RPL_LUSERUNKNOWN"
            case .RPL_LUSERCHANNELS: "RPL_LUSERCHANNELS"
            case .RPL_LUSERME: "RPL_LUSERME"
            case .RPL_ADMINME: "RPL_ADMINME"
            case .RPL_ADMINLOC1: "RPL_ADMINLOC1"
            case .RPL_ADMINLOC2: "RPL_ADMINLOC2"
            case .RPL_ADMINEMAIL: "RPL_ADMINEMAIL"

            case .RPL_NONE: "RPL_NONE"
            case .RPL_AWAY: "RPL_AWAY"
            case .RPL_USERHOST: "RPL_USERHOST"
            case .RPL_ISON: "RPL_ISON"
            case .RPL_UNAWAY: "RPL_UNAWAY"
            case .RPL_NOWAWAY: "RPL_NOWAWAY"
            case .RPL_WHOISUSER: "RPL_WHOISUSER"
            case .RPL_WHOISSERVER: "RPL_WHOISSERVER"
            case .RPL_WHOISOPERATOR: "RPL_WHOISOPERATOR"
            case .RPL_WHOWASUSER: "RPL_WHOWASUSER"
            case .RPL_ENDOFWHO: "RPL_ENDOFWHO"
            case .RPL_WHOISIDLE: "RPL_WHOISIDLE"
            case .RPL_ENDOFWHOIS: "RPL_ENDOFWHOIS"
            case .RPL_WHOISCHANNELS: "RPL_WHOISCHANNELS"
            case .RPL_LISTSTART: "RPL_LISTSTART"
            case .RPL_LIST: "RPL_LIST"
            case .RPL_LISTEND: "RPL_LISTEND"
            case .RPL_CHANNELMODEIS: "RPL_CHANNELMODEIS"
            case .RPL_CREATIONTIME: "RPL_CREATIONTIME"
            case .RPL_NOTOPIC: "RPL_NOTOPIC"
            case .RPL_TOPIC: "RPL_TOPIC"
            case .RPL_TOPICWHOTIME: "RPL_TOPICWHOTIME"
            case .RPL_INVITING: "RPL_INVITING"
            case .RPL_INVITELIST: "RPL_INVITELIST"
            case .RPL_ENDOFINVITELIST: "RPL_ENDOFINVITELIST"
            case .RPL_EXCEPTLIST: "RPL_EXCEPTLIST"
            case .RPL_ENDOFEXCEPTLIST: "RPL_ENDOFEXCEPTLIST"
            case .RPL_VERSION: "RPL_VERSION"
            case .RPL_WHOREPLY: "RPL_WHOREPLY"
            case .RPL_NAMREPLY: "RPL_NAMREPLY"
            case .RPL_LINKS: "RPL_LINKS"
            case .RPL_ENDOFLINKS: "RPL_ENDOFLINKS"
            case .RPL_ENDOFNAMES: "RPL_ENDOFNAMES"
            case .RPL_BANLIST: "RPL_BANLIST"
            case .RPL_ENDOFBANLIST: "RPL_ENDOFBANLIST"
            case .RPL_ENDOFWHOWAS: "RPL_ENDOFWHOWAS"
            case .RPL_INFO: "RPL_INFO"
            case .RPL_MOTD: "RPL_MOTD"
            case .RPL_ENDOFINFO: "RPL_ENDOFINFO"
            case .RPL_MOTDSTART: "RPL_MOTDSTART"
            case .RPL_ENDOFMOTD: "RPL_ENDOFMOTD"
            case .RPL_YOUREOPER: "RPL_YOUREOPER"
            case .RPL_REHASHING: "RPL_REHASHING"
            case .RPL_TIME: "RPL_TIME"

            case .ERR_NOSUCHNICK: "ERR_NOSUCHNICK"
            case .ERR_NOSUCHSERVER: "ERR_NOSUCHSERVER"
            case .ERR_NOSUCHCHANNEL: "ERR_NOSUCHCHANNEL"
            case .ERR_CANNOTSENDTOCHAN: "ERR_CANNOTSENDTOCHAN"
            case .ERR_TOOMANYCHANNELS: "ERR_TOOMANYCHANNELS"
            case .ERR_WASNOSUCHNICK: "ERR_WASNOSUCHNICK"
            case .ERR_TOOMANYTARGETS: "ERR_TOOMANYTARGETS"
            case .ERR_NOORIGIN: "ERR_NOORIGIN"
            case .ERR_NORECIPIENT: "ERR_NORECIPIENT"
            case .ERR_NOTEXTTOSEND: "ERR_NOTEXTTOSEND"
            case .ERR_NOTOPLEVEL: "ERR_NOTOPLEVEL"
            case .ERR_WILDTOPLEVEL: "ERR_WILDTOPLEVEL"
            case .ERR_UNKNOWNCOMMAND: "ERR_UNKNOWNCOMMAND"
            case .ERR_NOMOTD: "ERR_NOMOTD"
            case .ERR_NOADMININFO: "ERR_NOADMININFO"
            case .ERR_NONICKNAMEGIVEN: "ERR_NONICKNAMEGIVEN"
            case .ERR_ERRONEUSNICKNAME: "ERR_ERRONEUSNICKNAME"
            case .ERR_NICKNAMEINUSE: "ERR_NICKNAMEINUSE"
            case .ERR_NICKCOLLISION: "ERR_NICKCOLLISION"
            case .ERR_USERNOTINCHANNEL: "ERR_USERNOTINCHANNEL"
            case .ERR_NOTONCHANNEL: "ERR_NOTONCHANNEL"
            case .ERR_USERONCHANNEL: "ERR_USERONCHANNEL"
            case .ERR_NOTREGISTERED: "ERR_NOTREGISTERED"
            case .ERR_NEEDMOREPARAMS: "ERR_NEEDMOREPARAMS"
            case .ERR_ALREADYREGISTERED: "ERR_ALREADYREGISTERED"
            case .ERR_PASSWDMISMATCH: "ERR_PASSWDMISMATCH"
            case .ERR_YOUREBANNEDCREEP: "ERR_YOUREBANNEDCREEP"
            case .ERR_KEYSET: "ERR_KEYSET"
            case .ERR_CHANNELISFULL: "ERR_CHANNELISFULL"
            case .ERR_UNKNOWNMODE: "ERR_UNKNOWNMODE"
            case .ERR_INVITEONLYCHAN: "ERR_INVITEONLYCHAN"
            case .ERR_BANNEDFROMCHAN: "ERR_BANNEDFROMCHAN"
            case .ERR_BADCHANNELKEY: "ERR_BADCHANNELKEY"
            case .ERR_BADCHANMASK: "ERR_BADCHANMASK"
            case .ERR_NOPRIVILEGES: "ERR_NOPRIVILEGES"
            case .ERR_CHANOPRIVSNEEDED: "ERR_CHANOPRIVSNEEDED"
            case .ERR_CANTKILLSERVER: "ERR_CANTKILLSERVER"
            case .ERR_NOOPERHOST: "ERR_NOOPERHOST"
            case .ERR_UMODEUNKNOWNFLAG: "ERR_UMODEUNKNOWNFLAG"
            case .ERR_USERSDONTMATCH: "ERR_USERSDONTMATCH"

            case .RPL_LOGGEDIN: "RPL_LOGGEDIN"
            case .RPL_LOGGEDOUT: "RPL_LOGGEDOUT"
            case .RPL_SASLSUCCESS: "RPL_SASLSUCCESS"
            case .ERR_SASLFAIL: "ERR_SASLFAIL"
            case .ERR_SASLTOOLONG: "ERR_SASLTOOLONG"
            case .ERR_SASLABORTED: "ERR_SASLABORTED"
            case .ERR_SASLALREADY: "ERR_SASLALREADY"
            }
        }
    }
}
