import Foundation

public actor Client {

    // MARK: - Configuration

    public struct Config: Sendable {
        public var server: String
        public var port: Int
        public var useTLS: Bool
        public var nick: String
        public var username: String
        public var realname: String
        public var password: String?
        public var sasl: SASL?
        public var requestedCaps: [String]
        public var autoReconnect: Bool
        public var reconnectDelay: TimeInterval
        public var pingTimeout: TimeInterval
        public var rateLimit: RateLimit

        public enum SASL: Sendable {
            case plain(username: String, password: String)
            case external
        }

        public struct RateLimit: Sendable {
            public var messagesPerWindow: Int
            public var windowDuration: TimeInterval

            public static let `default` = RateLimit(messagesPerWindow: 5, windowDuration: 2.0)
            public static let none = RateLimit(messagesPerWindow: Int.max, windowDuration: 0.001)
        }

        public init(
            server: String,
            port: Int = 6697,
            useTLS: Bool = true,
            nick: String,
            username: String? = nil,
            realname: String? = nil,
            password: String? = nil,
            sasl: SASL? = nil,
            requestedCaps: [String] = [
                "sasl", "echo-message", "message-tags", "server-time", "account-tag",
                "extended-join", "multi-prefix",
            ],
            autoReconnect: Bool = false,
            reconnectDelay: TimeInterval = 5.0,
            pingTimeout: TimeInterval = 120.0,
            rateLimit: RateLimit = .default
        ) {
            self.server = server
            self.port = port
            self.useTLS = useTLS
            self.nick = nick
            self.username = username ?? nick
            self.realname = realname ?? nick
            self.password = password
            self.sasl = sasl
            self.requestedCaps = requestedCaps
            self.autoReconnect = autoReconnect
            self.reconnectDelay = reconnectDelay
            self.pingTimeout = pingTimeout
            self.rateLimit = rateLimit
        }
    }

    // MARK: - Events

    public enum Event: Sendable {
        case connected
        case registered
        case disconnected(Error?)
        case message(Message)
        case privmsg(target: String, sender: String, text: String, message: Message)
        case notice(target: String, sender: String, text: String, message: Message)
        case join(channel: String, nick: String, message: Message)
        case part(channel: String, nick: String, reason: String?, message: Message)
        case quit(nick: String, reason: String?, message: Message)
        case kick(channel: String, kicked: String, by: String, reason: String?, message: Message)
        case nick(oldNick: String, newNick: String, message: Message)
        case topic(channel: String, topic: String?, message: Message)
        case mode(target: String, modes: String, message: Message)
        case error(String)
    }

    // MARK: - Connection State

    public enum State: Sendable {
        case disconnected
        case connecting
        case connected
        case registering
        case registered
    }

    // MARK: - Properties

    private let config: Config
    private let transport: Transport

    private var state: State = .disconnected
    private var currentNick: String

    // Event streaming
    public let events: AsyncStream<Event>
    private let eventsContinuation: AsyncStream<Event>.Continuation

    // Registration gate
    private var registrationAwaiters: [CheckedContinuation<Void, Never>] = []

    // CAP negotiation state
    private var availableCaps: Set<String> = []
    private var enabledCaps: Set<String> = []
    private var capNegotiationComplete = false
    private var saslAuthenticated = false

    // Rate limiting
    private var rateLimitTokens: Int
    private var lastRateLimitRefill: Date

    // Pending aggregations
    private enum AggregationKey: Hashable, Sendable {
        case whois(String)
        case names(String)
        case who(String)
        case list
        case motd
    }
    private var pendingAggregations: [AggregationKey: any AnyAggregation] = [:]

    // Background tasks
    private var readerTask: Task<Void, Never>?
    private var writerTask: Task<Void, Never>?
    private var pingTask: Task<Void, Never>?

    // Write queue
    private var writeQueue: [String] = []

    // Last activity tracking
    private var lastPingSent: Date?
    private var lastPongReceived: Date?

    // MARK: - Initialization

    public init(config: Config, transport: Transport) {
        self.config = config
        self.transport = transport
        self.currentNick = config.nick
        self.rateLimitTokens = config.rateLimit.messagesPerWindow
        self.lastRateLimitRefill = Date()

        var continuation: AsyncStream<Event>.Continuation!
        self.events = AsyncStream { continuation = $0 }
        self.eventsContinuation = continuation
    }

    // MARK: - Connection Management

    public func connect() async throws {
        guard state == .disconnected else { return }

        state = .connecting
        eventsContinuation.yield(.connected)

        do {
            try await transport.open(host: config.server, port: config.port, tls: config.useTLS)
            state = .connected

            // Start background tasks
            readerTask = Task { await readLoop() }
            writerTask = Task { await writeLoop() }
            pingTask = Task { await pingLoop() }

            // Begin handshake
            await performHandshake()

        } catch {
            state = .disconnected
            eventsContinuation.yield(.disconnected(error))
            throw error
        }
    }

    public func disconnect(reason: String? = nil) async throws {
        guard state != .disconnected else { return }

        if state == .registered {
            try await send(.quit(reason))
            // Give it a moment to send
            try? await Task.sleep(nanoseconds: 500_000_000)
        }

        await cleanup()
    }

    private func cleanup() async {
        readerTask?.cancel()
        writerTask?.cancel()
        pingTask?.cancel()

        readerTask = nil
        writerTask = nil
        pingTask = nil

        try? await transport.close()

        state = .disconnected
        capNegotiationComplete = false
        saslAuthenticated = false
        availableCaps.removeAll()
        enabledCaps.removeAll()
        writeQueue.removeAll()

        // Complete any pending aggregations with error
        for (_, aggregation) in pendingAggregations {
            if let whois = aggregation as? WhoisAggregation {
                await whois.complete(error: ClientError.disconnected)
            } else if let names = aggregation as? NamesAggregation {
                await names.complete(error: ClientError.disconnected)
            } else if let who = aggregation as? WhoAggregation {
                await who.complete(error: ClientError.disconnected)
            } else if let list = aggregation as? ListAggregation {
                await list.complete(error: ClientError.disconnected)
            } else if let motd = aggregation as? MOTDAggregation {
                await motd.complete(error: ClientError.disconnected)
            }
        }
        pendingAggregations.removeAll()

        eventsContinuation.yield(.disconnected(nil))
    }

    // MARK: - Handshake

    private func performHandshake() async {
        state = .registering

        do {
            // Start with CAP negotiation if we want capabilities
            if !config.requestedCaps.isEmpty {
                try await sendRaw("CAP LS 302")
            }

            // Send PASS if we have a server password
            if let password = config.password {
                try await send(.pass(password))
            }

            // Send NICK and USER
            try await send(.nick(config.nick))
            try await send(.user(username: config.username, realname: config.realname))

            // If we're not doing CAP negotiation, we're done with our part
            if config.requestedCaps.isEmpty {
                capNegotiationComplete = true
            }

        } catch {
            eventsContinuation.yield(.error("Handshake failed: \(error)"))
            await cleanup()
        }
    }

    // MARK: - Public API

    public func awaitRegistered() async {
        if state == .registered { return }
        await withCheckedContinuation { continuation in
            registrationAwaiters.append(continuation)
        }
    }

    public func getCurrentNick() -> String {
        return currentNick
    }

    public func getState() -> State {
        return state
    }

    // MARK: - High-Level Commands

    public func join(_ channel: String, key: String? = nil) async throws {
        await awaitRegistered()
        try await send(.join(channel, key: key))
    }

    public func part(_ channel: String, reason: String? = nil) async throws {
        await awaitRegistered()
        try await send(.part(channel, reason: reason))
    }

    public func privmsg(_ target: String, _ text: String) async throws {
        await awaitRegistered()
        try await send(.privmsg(target, text))
    }

    public func notice(_ target: String, _ text: String) async throws {
        await awaitRegistered()
        try await send(.notice(target, text))
    }

    public func setNick(_ nick: String) async throws {
        try await send(.nick(nick))
    }

    public func setTopic(_ channel: String, topic: String) async throws {
        await awaitRegistered()
        try await send(.topic(channel, newTopic: topic))
    }

    public func getTopic(_ channel: String) async throws {
        await awaitRegistered()
        try await send(.topic(channel))
    }

    public func kick(_ channel: String, nick: String, reason: String? = nil) async throws {
        await awaitRegistered()
        try await send(.kick(channel: channel, nick: nick, reason: reason))
    }

    public func invite(_ nick: String, to channel: String) async throws {
        await awaitRegistered()
        try await send(.invite(nick: nick, channel: channel))
    }

    public func setMode(_ target: String, modes: String) async throws {
        await awaitRegistered()
        try await send(.mode(target: target, modes: modes))
    }

    public func away(_ message: String? = nil) async throws {
        await awaitRegistered()
        try await send(.away(message))
    }

    // MARK: - Aggregated Queries

    public func whois(_ nick: String) async throws -> WhoisAggregation.Result {
        await awaitRegistered()

        let aggregation = WhoisAggregation(nick: nick)
        let key = AggregationKey.whois(nick)
        pendingAggregations[key] = aggregation

        try await send(.whois(nick))

        let result = try await aggregation.wait()
        pendingAggregations.removeValue(forKey: key)
        return result
    }

    public func names(_ channel: String) async throws -> NamesAggregation.Result {
        await awaitRegistered()

        let aggregation = NamesAggregation(channel: channel)
        let key = AggregationKey.names(channel)
        pendingAggregations[key] = aggregation

        try await send(.names(channel))

        let result = try await aggregation.wait()
        pendingAggregations.removeValue(forKey: key)
        return result
    }

    public func who(_ mask: String) async throws -> WhoAggregation.Result {
        await awaitRegistered()

        let aggregation = WhoAggregation(mask: mask)
        let key = AggregationKey.who(mask)
        pendingAggregations[key] = aggregation

        try await send(.who(mask))

        let result = try await aggregation.wait()
        pendingAggregations.removeValue(forKey: key)
        return result
    }

    public func list(_ channel: String? = nil) async throws -> ListAggregation.Result {
        await awaitRegistered()

        let aggregation = ListAggregation()
        let key = AggregationKey.list
        pendingAggregations[key] = aggregation

        try await send(.list(channel))

        let result = try await aggregation.wait()
        pendingAggregations.removeValue(forKey: key)
        return result
    }

    public func motd() async throws -> MOTDAggregation.Result {
        await awaitRegistered()

        let aggregation = MOTDAggregation()
        let key = AggregationKey.motd
        pendingAggregations[key] = aggregation

        try await send(.motd())

        let result = try await aggregation.wait()
        pendingAggregations.removeValue(forKey: key)
        return result
    }

    // MARK: - Low-Level Sending

    public func send(_ command: Command) async throws {
        try await sendRaw(command.encode())
    }

    public func sendRaw(_ line: String) async throws {
        guard state != .disconnected else {
            throw ClientError.notConnected
        }

        await applyRateLimit()
        writeQueue.append(line)
    }

    // MARK: - Background Loops

    private func readLoop() async {
        while state != .disconnected {
            do {
                guard let line = try await transport.readLine() else {
                    // Connection closed
                    await cleanup()
                    return
                }

                if !line.isEmpty {
                    let message = Message.parse(line)
                    await handleMessage(message)
                }

            } catch {
                eventsContinuation.yield(.error("Read error: \(error)"))
                await cleanup()
                return
            }
        }
    }

    private func writeLoop() async {
        while state != .disconnected {
            if let line = writeQueue.first {
                do {
                    try await transport.writeLine(line)
                    writeQueue.removeFirst()
                } catch {
                    eventsContinuation.yield(.error("Write error: \(error)"))
                    await cleanup()
                    return
                }
            } else {
                try? await Task.sleep(nanoseconds: 10_000_000)  // 10ms
            }
        }
    }

    private func pingLoop() async {
        while state != .disconnected {
            try? await Task.sleep(nanoseconds: UInt64(config.pingTimeout * 0.5 * 1_000_000_000))

            if state == .registered {
                // Check if we've timed out
                if let lastPong = lastPongReceived,
                    Date().timeIntervalSince(lastPong) > config.pingTimeout
                {
                    eventsContinuation.yield(.error("Ping timeout"))
                    await cleanup()
                    return
                }

                // Send ping
                let token = "\(Date().timeIntervalSince1970)"
                try? await sendRaw("PING :\(token)")
                lastPingSent = Date()
            }
        }
    }

    // MARK: - Message Handling

    private func handleMessage(_ message: Message) async {
        // Update pong tracking
        if message.command == "PONG" {
            lastPongReceived = Date()
        }

        // Handle aggregations first
        await routeToAggregations(message)

        // Then handle specific messages
        switch message.command {
        case "PING":
            if let token = message.params.last {
                try? await sendRaw("PONG :\(token)")
            }

        case "PRIVMSG":
            if let target = message.target, let text = message.text, let sender = message.nick {
                eventsContinuation.yield(
                    .privmsg(target: target, sender: sender, text: text, message: message))
            }

        case "NOTICE":
            if let target = message.target, let text = message.text, let sender = message.nick {
                eventsContinuation.yield(
                    .notice(target: target, sender: sender, text: text, message: message))
            }

        case "JOIN":
            if let channel = message.channel, let nick = message.nick {
                eventsContinuation.yield(.join(channel: channel, nick: nick, message: message))
            }

        case "PART":
            if let channel = message.channel, let nick = message.nick {
                let reason = message.text
                eventsContinuation.yield(
                    .part(channel: channel, nick: nick, reason: reason, message: message))
            }

        case "QUIT":
            if let nick = message.nick {
                let reason = message.text
                eventsContinuation.yield(.quit(nick: nick, reason: reason, message: message))
            }

        case "KICK":
            if message.params.count >= 2, let kicker = message.nick {
                let channel = message.params[0]
                let kicked = message.params[1]
                let reason = message.text
                eventsContinuation.yield(
                    .kick(
                        channel: channel, kicked: kicked, by: kicker, reason: reason,
                        message: message))
            }

        case "NICK":
            if let oldNick = message.nick, let newNick = message.params.first {
                if oldNick == currentNick {
                    currentNick = newNick
                }
                eventsContinuation.yield(
                    .nick(oldNick: oldNick, newNick: newNick, message: message))
            }

        case "TOPIC":
            if let channel = message.channel {
                let topic = message.text
                eventsContinuation.yield(.topic(channel: channel, topic: topic, message: message))
            }

        case "MODE":
            if let target = message.params.first {
                let modes = message.params.dropFirst().joined(separator: " ")
                eventsContinuation.yield(.mode(target: target, modes: modes, message: message))
            }

        case "CAP":
            await handleCAP(message)

        case "AUTHENTICATE":
            await handleAuthenticate(message)

        case "001":  // RPL_WELCOME
            await markRegistered()

        case "433":  // ERR_NICKNAMEINUSE
            // Nick in use during registration, try alternate
            if state == .registering {
                currentNick = currentNick + "_"
                try? await send(.nick(currentNick))
            }

        default:
            // Check for SASL responses
            if let code = message.numericCode {
                switch code {
                case 903:  // RPL_SASLSUCCESS
                    saslAuthenticated = true
                    if capNegotiationComplete {
                        try? await sendRaw("CAP END")
                    }

                case 904, 905, 906:  // SASL failures
                    eventsContinuation.yield(.error("SASL authentication failed: \(message.raw)"))
                    saslAuthenticated = false
                    try? await sendRaw("CAP END")

                default:
                    break
                }
            }

            break
        }

        // Always yield raw message
        eventsContinuation.yield(.message(message))
    }

    private func handleCAP(_ message: Message) async {
        guard message.params.count >= 2 else { return }

        let subcommand = message.params[1]

        switch subcommand {
        case "LS":
            // Server listing available capabilities
            if let capsString = message.params.last {
                let caps = capsString.split(separator: " ").map(String.init)
                availableCaps.formUnion(caps)

                // Check if this is multiline (has * as param 2)
                let isMultiline = message.params.count >= 3 && message.params[2] == "*"

                if !isMultiline {
                    // Request the caps we want
                    let requestCaps = config.requestedCaps.filter { availableCaps.contains($0) }
                    if !requestCaps.isEmpty {
                        try? await sendRaw("CAP REQ :\(requestCaps.joined(separator: " "))")
                    } else {
                        capNegotiationComplete = true
                        try? await sendRaw("CAP END")
                    }
                }
            }

        case "ACK":
            // Server acknowledged our capability request
            if let capsString = message.params.last {
                let caps = capsString.split(separator: " ").map(String.init)
                enabledCaps.formUnion(caps)

                // If we got SASL, authenticate
                if enabledCaps.contains("sasl"), let sasl = config.sasl, !saslAuthenticated {
                    switch sasl {
                    case .plain(_, _):
                        try? await sendRaw("AUTHENTICATE PLAIN")
                    // Will continue in handleAuthenticate

                    case .external:
                        try? await sendRaw("AUTHENTICATE EXTERNAL")
                        try? await sendRaw("AUTHENTICATE +")
                    }
                } else {
                    capNegotiationComplete = true
                    try? await sendRaw("CAP END")
                }
            }

        case "NAK":
            // Server rejected our capability request
            capNegotiationComplete = true
            try? await sendRaw("CAP END")

        default:
            break
        }
    }

    private func handleAuthenticate(_ message: Message) async {
        guard let param = message.params.first else { return }

        if param == "+", case .plain(let username, let password) = config.sasl {
            // Server ready for SASL PLAIN credentials
            let credentials = "\0\(username)\0\(password)"
            if let encoded = credentials.data(using: .utf8)?.base64EncodedString() {
                try? await sendRaw("AUTHENTICATE \(encoded)")
            }
        }
    }

    private func markRegistered() async {
        guard state != .registered else { return }
        state = .registered
        lastPongReceived = Date()

        // Resume all registration awaiters
        for continuation in registrationAwaiters {
            continuation.resume()
        }
        registrationAwaiters.removeAll()

        eventsContinuation.yield(.registered)
    }

    // MARK: - Aggregation Routing

    private func routeToAggregations(_ message: Message) async {
        // Try to route to all applicable aggregations
        for (key, aggregation) in pendingAggregations {
            // Feed the message
            await aggregation.feed(message)

            // Check if done
            if aggregation.isDone(message) {
                if let whois = aggregation as? WhoisAggregation {
                    await whois.complete()
                } else if let names = aggregation as? NamesAggregation {
                    await names.complete()
                } else if let who = aggregation as? WhoAggregation {
                    await who.complete()
                } else if let list = aggregation as? ListAggregation {
                    await list.complete()
                } else if let motd = aggregation as? MOTDAggregation {
                    await motd.complete()
                }

                pendingAggregations.removeValue(forKey: key)
            }
        }
    }

    // MARK: - Rate Limiting

    private func applyRateLimit() async {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastRateLimitRefill)

        // Refill tokens based on elapsed time
        if elapsed >= config.rateLimit.windowDuration {
            rateLimitTokens = config.rateLimit.messagesPerWindow
            lastRateLimitRefill = now
        }

        // Wait if no tokens available
        while rateLimitTokens <= 0 {
            let waitTime = config.rateLimit.windowDuration - elapsed
            if waitTime > 0 {
                try? await Task.sleep(nanoseconds: UInt64(waitTime * 1_000_000_000))
            }

            rateLimitTokens = config.rateLimit.messagesPerWindow
            lastRateLimitRefill = Date()
        }

        rateLimitTokens -= 1
    }
}

// MARK: - Errors

public enum ClientError: Error, CustomStringConvertible {
    case notConnected
    case alreadyConnected
    case registrationFailed(String)
    case authenticationFailed(String)
    case timeout
    case disconnected
    case invalidResponse

    public var description: String {
        switch self {
        case .notConnected:
            return "Client is not connected"
        case .alreadyConnected:
            return "Client is already connected"
        case .registrationFailed(let reason):
            return "Registration failed: \(reason)"
        case .authenticationFailed(let reason):
            return "Authentication failed: \(reason)"
        case .timeout:
            return "Operation timed out"
        case .disconnected:
            return "Client disconnected"
        case .invalidResponse:
            return "Invalid response from server"
        }
    }
}
