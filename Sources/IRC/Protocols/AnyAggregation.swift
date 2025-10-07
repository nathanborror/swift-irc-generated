import Foundation

// MARK: - Aggregation Protocol

/// Protocol for aggregating multi-message IRC responses
public protocol AnyAggregation: Sendable {
    /// Feed a message to this aggregation
    func feed(_ message: Message) async

    /// Check if this message completes the aggregation
    nonisolated func isDone(_ message: Message) -> Bool

    /// Check if this aggregation has timed out
    func isTimedOut() async -> Bool
}

// MARK: - WHOIS Aggregation

/// Aggregates WHOIS response messages (311-319, ending with 318)
public actor WhoisAggregation: AnyAggregation {
    public struct Result: Sendable {
        public var nick: String
        public var username: String?
        public var host: String?
        public var realname: String?
        public var server: String?
        public var serverInfo: String?
        public var channels: [String] = []
        public var isOperator: Bool = false
        public var idleSeconds: Int?
        public var signonTime: Date?
        public var account: String?
        public var isAway: Bool = false
        public var awayMessage: String?
    }

    private var result: Result
    private var continuation: CheckedContinuation<Result, Error>?
    private let timeout: TimeInterval
    private let startTime: Date

    public init(nick: String, timeout: TimeInterval = 30.0) {
        self.result = Result(nick: nick)
        self.timeout = timeout
        self.startTime = Date()
    }

    public func isTimedOut() async -> Bool {
        return Date().timeIntervalSince(startTime) > timeout
    }

    public func feed(_ message: Message) async {
        guard let code = message.numericCode else { return }

        switch code {
        case 311:  // RPL_WHOISUSER: <nick> <user> <host> * :<real name>
            if message.params.count >= 6 {
                result.username = message.params[2]
                result.host = message.params[3]
                result.realname = message.params[5]
            }

        case 312:  // RPL_WHOISSERVER: <nick> <server> :<server info>
            if message.params.count >= 4 {
                result.server = message.params[2]
                result.serverInfo = message.params[3]
            }

        case 313:  // RPL_WHOISOPERATOR: <nick> :is an IRC operator
            result.isOperator = true

        case 317:  // RPL_WHOISIDLE: <nick> <integer> <integer> :seconds idle, signon time
            if message.params.count >= 3 {
                result.idleSeconds = Int(message.params[2])
                if message.params.count >= 4, let signon = Int(message.params[3]) {
                    result.signonTime = Date(timeIntervalSince1970: TimeInterval(signon))
                }
            }

        case 319:  // RPL_WHOISCHANNELS: <nick> :<channels>
            if let channelsStr = message.params.last {
                result.channels = channelsStr.split(separator: " ").map(String.init)
            }

        case 301:  // RPL_AWAY: <nick> :<away message>
            result.isAway = true
            result.awayMessage = message.params.last

        case 330:  // RPL_WHOISACCOUNT: <nick> <account> :is logged in as
            if message.params.count >= 3 {
                result.account = message.params[2]
            }

        default:
            break
        }
    }

    nonisolated public func isDone(_ message: Message) -> Bool {
        return message.numericCode == 318  // RPL_ENDOFWHOIS
            || message.numericCode == 401  // ERR_NOSUCHNICK
    }

    public func wait() async throws -> Result {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    public func complete(error: Error? = nil) {
        if let error = error {
            continuation?.resume(throwing: error)
        } else {
            continuation?.resume(returning: result)
        }
        continuation = nil
    }
}

// MARK: - NAMES Aggregation

/// Aggregates NAMES response messages (353, ending with 366)
public actor NamesAggregation: AnyAggregation {
    public struct Result: Sendable {
        public var channel: String
        public var names: [String] = []
    }

    private var result: Result
    private var continuation: CheckedContinuation<Result, Error>?
    private let timeout: TimeInterval
    private let startTime: Date

    public init(channel: String, timeout: TimeInterval = 30.0) {
        self.result = Result(channel: channel)
        self.timeout = timeout
        self.startTime = Date()
    }

    public func isTimedOut() async -> Bool {
        return Date().timeIntervalSince(startTime) > timeout
    }

    public func feed(_ message: Message) async {
        guard message.numericCode == 353 else { return }  // RPL_NAMREPLY

        // Format: <client> <symbol> <channel> :<names>
        if message.params.count >= 4, let namesStr = message.params.last {
            let names = namesStr.split(separator: " ").map(String.init)
            result.names.append(contentsOf: names)
        }
    }

    nonisolated public func isDone(_ message: Message) -> Bool {
        return message.numericCode == 366  // RPL_ENDOFNAMES
    }

    public func wait() async throws -> Result {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    public func complete(error: Error? = nil) {
        if let error = error {
            continuation?.resume(throwing: error)
        } else {
            continuation?.resume(returning: result)
        }
        continuation = nil
    }
}

// MARK: - WHO Aggregation

/// Aggregates WHO response messages (352, ending with 315)
public actor WhoAggregation: AnyAggregation {
    public struct Entry: Sendable {
        public var channel: String
        public var username: String
        public var host: String
        public var server: String
        public var nick: String
        public var flags: String
        public var hopcount: Int
        public var realname: String
    }

    public struct Result: Sendable {
        public var mask: String
        public var entries: [Entry] = []
    }

    private var result: Result
    private var continuation: CheckedContinuation<Result, Error>?
    private let timeout: TimeInterval
    private let startTime: Date

    public init(mask: String, timeout: TimeInterval = 30.0) {
        self.result = Result(mask: mask)
        self.timeout = timeout
        self.startTime = Date()
    }

    public func isTimedOut() async -> Bool {
        return Date().timeIntervalSince(startTime) > timeout
    }

    public func feed(_ message: Message) async {
        guard message.numericCode == 352 else { return }  // RPL_WHOREPLY

        // Format: <client> <channel> <user> <host> <server> <nick> <flags> :<hopcount> <real name>
        if message.params.count >= 8 {
            let lastParam = message.params[7]
            let components = lastParam.split(separator: " ", maxSplits: 1)
            let hopcount = components.first.flatMap { Int($0) } ?? 0
            let realname = components.count > 1 ? String(components[1]) : ""

            let entry = Entry(
                channel: message.params[1],
                username: message.params[2],
                host: message.params[3],
                server: message.params[4],
                nick: message.params[5],
                flags: message.params[6],
                hopcount: hopcount,
                realname: realname
            )
            result.entries.append(entry)
        }
    }

    nonisolated public func isDone(_ message: Message) -> Bool {
        return message.numericCode == 315  // RPL_ENDOFWHO
    }

    public func wait() async throws -> Result {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    public func complete(error: Error? = nil) {
        if let error = error {
            continuation?.resume(throwing: error)
        } else {
            continuation?.resume(returning: result)
        }
        continuation = nil
    }
}

// MARK: - LIST Aggregation

/// Aggregates LIST response messages (322, ending with 323)
public actor ListAggregation: AnyAggregation {
    public struct Entry: Sendable {
        public var channel: String
        public var userCount: Int
        public var topic: String
    }

    public struct Result: Sendable {
        public var entries: [Entry] = []
    }

    private var result = Result()
    private var continuation: CheckedContinuation<Result, Error>?
    private let timeout: TimeInterval
    private let startTime: Date

    public init(timeout: TimeInterval = 30.0) {
        self.timeout = timeout
        self.startTime = Date()
    }

    public func isTimedOut() async -> Bool {
        return Date().timeIntervalSince(startTime) > timeout
    }

    public func feed(_ message: Message) async {
        guard message.numericCode == 322 else { return }  // RPL_LIST

        // Format: <client> <channel> <# visible> :<topic>
        if message.params.count >= 4 {
            let entry = Entry(
                channel: message.params[1],
                userCount: Int(message.params[2]) ?? 0,
                topic: message.params[3]
            )
            result.entries.append(entry)
        }
    }

    nonisolated public func isDone(_ message: Message) -> Bool {
        return message.numericCode == 323  // RPL_LISTEND
    }

    public func wait() async throws -> Result {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    public func complete(error: Error? = nil) {
        if let error = error {
            continuation?.resume(throwing: error)
        } else {
            continuation?.resume(returning: result)
        }
        continuation = nil
    }
}

// MARK: - MOTD Aggregation

/// Aggregates MOTD response messages (372, ending with 376)
public actor MOTDAggregation: AnyAggregation {
    public struct Result: Sendable {
        public var lines: [String] = []
    }

    private var result = Result()
    private var continuation: CheckedContinuation<Result, Error>?
    private let timeout: TimeInterval
    private let startTime: Date

    public init(timeout: TimeInterval = 30.0) {
        self.timeout = timeout
        self.startTime = Date()
    }

    public func isTimedOut() async -> Bool {
        return Date().timeIntervalSince(startTime) > timeout
    }

    public func feed(_ message: Message) async {
        guard message.numericCode == 372 else { return }  // RPL_MOTD

        if let line = message.params.last {
            result.lines.append(line)
        }
    }

    nonisolated public func isDone(_ message: Message) -> Bool {
        return message.numericCode == 376  // RPL_ENDOFMOTD
            || message.numericCode == 422  // ERR_NOMOTD
    }

    public func wait() async throws -> Result {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    public func complete(error: Error? = nil) {
        if let error = error {
            continuation?.resume(throwing: error)
        } else {
            continuation?.resume(returning: result)
        }
        continuation = nil
    }
}
