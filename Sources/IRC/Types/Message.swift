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
    /// Extracts nickname from prefix (nick!user@host)
    public var nick: String? {
        guard let prefix = prefix else { return nil }
        if let bangIdx = prefix.firstIndex(of: "!") {
            return String(prefix[..<bangIdx])
        }
        return prefix
    }

    /// Extracts user from prefix (nick!user@host)
    public var user: String? {
        guard let prefix = prefix else { return nil }
        guard let bangIdx = prefix.firstIndex(of: "!") else { return nil }
        let afterBang = prefix.index(after: bangIdx)
        if let atIdx = prefix[afterBang...].firstIndex(of: "@") {
            return String(prefix[afterBang..<atIdx])
        }
        return String(prefix[afterBang...])
    }

    /// Extracts host from prefix (nick!user@host)
    public var host: String? {
        guard let prefix = prefix else { return nil }
        if let atIdx = prefix.firstIndex(of: "@") {
            return String(prefix[prefix.index(after: atIdx)...])
        }
        return nil
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
        return NumericReply.name(for: code)
    }
}

// MARK: - Numeric Reply Codes

extension Message {
    /// IRC numeric reply codes
    public enum NumericReply {
        // Connection/Welcome (001-099)
        public static let RPL_WELCOME = 1
        public static let RPL_YOURHOST = 2
        public static let RPL_CREATED = 3
        public static let RPL_MYINFO = 4
        public static let RPL_ISUPPORT = 5
        public static let RPL_BOUNCE = 10

        // Statistics (200-299)
        public static let RPL_STATSCOMMANDS = 212
        public static let RPL_ENDOFSTATS = 219
        public static let RPL_UMODEIS = 221
        public static let RPL_STATSUPTIME = 242
        public static let RPL_LUSERCLIENT = 251
        public static let RPL_LUSEROP = 252
        public static let RPL_LUSERUNKNOWN = 253
        public static let RPL_LUSERCHANNELS = 254
        public static let RPL_LUSERME = 255
        public static let RPL_ADMINME = 256
        public static let RPL_ADMINLOC1 = 257
        public static let RPL_ADMINLOC2 = 258
        public static let RPL_ADMINEMAIL = 259

        // Server/Network Info (300-399)
        public static let RPL_NONE = 300
        public static let RPL_AWAY = 301
        public static let RPL_USERHOST = 302
        public static let RPL_ISON = 303
        public static let RPL_UNAWAY = 305
        public static let RPL_NOWAWAY = 306
        public static let RPL_WHOISUSER = 311
        public static let RPL_WHOISSERVER = 312
        public static let RPL_WHOISOPERATOR = 313
        public static let RPL_WHOWASUSER = 314
        public static let RPL_ENDOFWHO = 315
        public static let RPL_WHOISIDLE = 317
        public static let RPL_ENDOFWHOIS = 318
        public static let RPL_WHOISCHANNELS = 319
        public static let RPL_LISTSTART = 321
        public static let RPL_LIST = 322
        public static let RPL_LISTEND = 323
        public static let RPL_CHANNELMODEIS = 324
        public static let RPL_CREATIONTIME = 329
        public static let RPL_NOTOPIC = 331
        public static let RPL_TOPIC = 332
        public static let RPL_TOPICWHOTIME = 333
        public static let RPL_INVITING = 341
        public static let RPL_INVITELIST = 346
        public static let RPL_ENDOFINVITELIST = 347
        public static let RPL_EXCEPTLIST = 348
        public static let RPL_ENDOFEXCEPTLIST = 349
        public static let RPL_VERSION = 351
        public static let RPL_WHOREPLY = 352
        public static let RPL_NAMREPLY = 353
        public static let RPL_LINKS = 364
        public static let RPL_ENDOFLINKS = 365
        public static let RPL_ENDOFNAMES = 366
        public static let RPL_BANLIST = 367
        public static let RPL_ENDOFBANLIST = 368
        public static let RPL_ENDOFWHOWAS = 369
        public static let RPL_INFO = 371
        public static let RPL_ENDOFINFO = 374
        public static let RPL_MOTDSTART = 375
        public static let RPL_MOTD = 372
        public static let RPL_ENDOFMOTD = 376
        public static let RPL_YOUREOPER = 381
        public static let RPL_REHASHING = 382
        public static let RPL_TIME = 391

        // Errors (400-599)
        public static let ERR_NOSUCHNICK = 401
        public static let ERR_NOSUCHSERVER = 402
        public static let ERR_NOSUCHCHANNEL = 403
        public static let ERR_CANNOTSENDTOCHAN = 404
        public static let ERR_TOOMANYCHANNELS = 405
        public static let ERR_WASNOSUCHNICK = 406
        public static let ERR_TOOMANYTARGETS = 407
        public static let ERR_NOORIGIN = 409
        public static let ERR_NORECIPIENT = 411
        public static let ERR_NOTEXTTOSEND = 412
        public static let ERR_NOTOPLEVEL = 413
        public static let ERR_WILDTOPLEVEL = 414
        public static let ERR_UNKNOWNCOMMAND = 421
        public static let ERR_NOMOTD = 422
        public static let ERR_NOADMININFO = 423
        public static let ERR_NONICKNAMEGIVEN = 431
        public static let ERR_ERRONEUSNICKNAME = 432
        public static let ERR_NICKNAMEINUSE = 433
        public static let ERR_NICKCOLLISION = 436
        public static let ERR_USERNOTINCHANNEL = 441
        public static let ERR_NOTONCHANNEL = 442
        public static let ERR_USERONCHANNEL = 443
        public static let ERR_NOTREGISTERED = 451
        public static let ERR_NEEDMOREPARAMS = 461
        public static let ERR_ALREADYREGISTERED = 462
        public static let ERR_PASSWDMISMATCH = 464
        public static let ERR_YOUREBANNEDCREEP = 465
        public static let ERR_KEYSET = 467
        public static let ERR_CHANNELISFULL = 471
        public static let ERR_UNKNOWNMODE = 472
        public static let ERR_INVITEONLYCHAN = 473
        public static let ERR_BANNEDFROMCHAN = 474
        public static let ERR_BADCHANNELKEY = 475
        public static let ERR_BADCHANMASK = 476
        public static let ERR_NOPRIVILEGES = 481
        public static let ERR_CHANOPRIVSNEEDED = 482
        public static let ERR_CANTKILLSERVER = 483
        public static let ERR_NOOPERHOST = 491
        public static let ERR_UMODEUNKNOWNFLAG = 501
        public static let ERR_USERSDONTMATCH = 502

        // SASL (900-909)
        public static let RPL_LOGGEDIN = 900
        public static let RPL_LOGGEDOUT = 901
        public static let RPL_SASLSUCCESS = 903
        public static let ERR_SASLFAIL = 904
        public static let ERR_SASLTOOLONG = 905
        public static let ERR_SASLABORTED = 906
        public static let ERR_SASLALREADY = 907

        /// Maps numeric codes to their symbolic names
        public static func name(for code: Int) -> String? {
            switch code {
            case 1: return "RPL_WELCOME"
            case 2: return "RPL_YOURHOST"
            case 3: return "RPL_CREATED"
            case 4: return "RPL_MYINFO"
            case 5: return "RPL_ISUPPORT"
            case 10: return "RPL_BOUNCE"

            case 212: return "RPL_STATSCOMMANDS"
            case 219: return "RPL_ENDOFSTATS"
            case 221: return "RPL_UMODEIS"
            case 242: return "RPL_STATSUPTIME"
            case 251: return "RPL_LUSERCLIENT"
            case 252: return "RPL_LUSEROP"
            case 253: return "RPL_LUSERUNKNOWN"
            case 254: return "RPL_LUSERCHANNELS"
            case 255: return "RPL_LUSERME"
            case 256: return "RPL_ADMINME"
            case 257: return "RPL_ADMINLOC1"
            case 258: return "RPL_ADMINLOC2"
            case 259: return "RPL_ADMINEMAIL"

            case 300: return "RPL_NONE"
            case 301: return "RPL_AWAY"
            case 302: return "RPL_USERHOST"
            case 303: return "RPL_ISON"
            case 305: return "RPL_UNAWAY"
            case 306: return "RPL_NOWAWAY"
            case 311: return "RPL_WHOISUSER"
            case 312: return "RPL_WHOISSERVER"
            case 313: return "RPL_WHOISOPERATOR"
            case 314: return "RPL_WHOWASUSER"
            case 315: return "RPL_ENDOFWHO"
            case 317: return "RPL_WHOISIDLE"
            case 318: return "RPL_ENDOFWHOIS"
            case 319: return "RPL_WHOISCHANNELS"
            case 321: return "RPL_LISTSTART"
            case 322: return "RPL_LIST"
            case 323: return "RPL_LISTEND"
            case 324: return "RPL_CHANNELMODEIS"
            case 329: return "RPL_CREATIONTIME"
            case 331: return "RPL_NOTOPIC"
            case 332: return "RPL_TOPIC"
            case 333: return "RPL_TOPICWHOTIME"
            case 341: return "RPL_INVITING"
            case 346: return "RPL_INVITELIST"
            case 347: return "RPL_ENDOFINVITELIST"
            case 348: return "RPL_EXCEPTLIST"
            case 349: return "RPL_ENDOFEXCEPTLIST"
            case 351: return "RPL_VERSION"
            case 352: return "RPL_WHOREPLY"
            case 353: return "RPL_NAMREPLY"
            case 364: return "RPL_LINKS"
            case 365: return "RPL_ENDOFLINKS"
            case 366: return "RPL_ENDOFNAMES"
            case 367: return "RPL_BANLIST"
            case 368: return "RPL_ENDOFBANLIST"
            case 369: return "RPL_ENDOFWHOWAS"
            case 371: return "RPL_INFO"
            case 372: return "RPL_MOTD"
            case 374: return "RPL_ENDOFINFO"
            case 375: return "RPL_MOTDSTART"
            case 376: return "RPL_ENDOFMOTD"
            case 381: return "RPL_YOUREOPER"
            case 382: return "RPL_REHASHING"
            case 391: return "RPL_TIME"

            case 401: return "ERR_NOSUCHNICK"
            case 402: return "ERR_NOSUCHSERVER"
            case 403: return "ERR_NOSUCHCHANNEL"
            case 404: return "ERR_CANNOTSENDTOCHAN"
            case 405: return "ERR_TOOMANYCHANNELS"
            case 406: return "ERR_WASNOSUCHNICK"
            case 407: return "ERR_TOOMANYTARGETS"
            case 409: return "ERR_NOORIGIN"
            case 411: return "ERR_NORECIPIENT"
            case 412: return "ERR_NOTEXTTOSEND"
            case 413: return "ERR_NOTOPLEVEL"
            case 414: return "ERR_WILDTOPLEVEL"
            case 421: return "ERR_UNKNOWNCOMMAND"
            case 422: return "ERR_NOMOTD"
            case 423: return "ERR_NOADMININFO"
            case 431: return "ERR_NONICKNAMEGIVEN"
            case 432: return "ERR_ERRONEUSNICKNAME"
            case 433: return "ERR_NICKNAMEINUSE"
            case 436: return "ERR_NICKCOLLISION"
            case 441: return "ERR_USERNOTINCHANNEL"
            case 442: return "ERR_NOTONCHANNEL"
            case 443: return "ERR_USERONCHANNEL"
            case 451: return "ERR_NOTREGISTERED"
            case 461: return "ERR_NEEDMOREPARAMS"
            case 462: return "ERR_ALREADYREGISTERED"
            case 464: return "ERR_PASSWDMISMATCH"
            case 465: return "ERR_YOUREBANNEDCREEP"
            case 467: return "ERR_KEYSET"
            case 471: return "ERR_CHANNELISFULL"
            case 472: return "ERR_UNKNOWNMODE"
            case 473: return "ERR_INVITEONLYCHAN"
            case 474: return "ERR_BANNEDFROMCHAN"
            case 475: return "ERR_BADCHANNELKEY"
            case 476: return "ERR_BADCHANMASK"
            case 481: return "ERR_NOPRIVILEGES"
            case 482: return "ERR_CHANOPRIVSNEEDED"
            case 483: return "ERR_CANTKILLSERVER"
            case 491: return "ERR_NOOPERHOST"
            case 501: return "ERR_UMODEUNKNOWNFLAG"
            case 502: return "ERR_USERSDONTMATCH"

            case 900: return "RPL_LOGGEDIN"
            case 901: return "RPL_LOGGEDOUT"
            case 903: return "RPL_SASLSUCCESS"
            case 904: return "ERR_SASLFAIL"
            case 905: return "ERR_SASLTOOLONG"
            case 906: return "ERR_SASLABORTED"
            case 907: return "ERR_SASLALREADY"

            default: return nil
            }
        }
    }
}
