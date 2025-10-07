import Foundation

public actor Client {

    public struct Config {
        public var server: String
        public var port: Int = 6697
        public var useTLS: Bool = true
        public var nick: String
        public var username: String
        public var realname: String
        public var sasl: SASL? = nil
        public var requestedCaps: [String] = ["sasl", "echo-message", "message-tags", "server-time", "account-tag", "extended-join"]

        public enum SASL {
            case plain(username: String, password: String)
            case external
        }

        init(server: String, nick: String, username: String, realname: String) {
            self.server = server
            self.nick = nick
            self.username = username
            self.realname = realname
        }
    }

    public enum Event {
        case connected
        case registered
        case message(Message)
        case notice(Message)
        case privmsg(Message)
        case join(Message)
        case part(Message)
        case error(Message)
        case disconnected(Error?)
    }

    private let config: Config
    private let transport: Transport

    // Events
    public let events: AsyncStream<Event>
    private let eventsContinuation: AsyncStream<Event>.Continuation

    // Outbound Queue
    private var sendQueue: [String] = []
//    private var sendSemaphore = AsyncSemaphore(value: 1)
    private var isConnected = false

    // Registration Gate
    private var registrationAwaiters: [CheckedContinuation<Void, Never>] = []
    private var isRegistered = false

    // Pending Aggregations (WOIS, NAMES, etc.)
    private struct PendingKey: Hashable { let verb: String; let token: String }
    private var pending: [PendingKey: AnyAggregation] = [:]

    public init(config: Config, transport: Transport) {
        self.config = config
        self.transport = transport

        var c: AsyncStream<Event>.Continuation!
        self.events = AsyncStream { c = $0 }
        self.eventsContinuation = c
    }

    public func connect() async throws {
        guard !isConnected else { return }
        try await transport.open(host: config.server, port: config.port, tls: config.useTLS)
        isConnected = true
        eventsContinuation.yield(.connected)

        // Writer
        Task.detached { [weak self] in await self?.writerLoop() }

        // Reader
        Task.detached { [weak self] in await self?.readerLoop() }

        // Handshake
        Task.detached { [weak self] in await self?.handshake() }
    }

    public func disconnect() async throws {
        print("not implemented")
    }

    // High-Level

    public func join(_ channel: String) async throws {
        await awaitRegistered()
        try await send(.join(channel))
    }

    public func privmsg(_ target: String, _ text: String) async throws {
        print("not implemented")
    }

    public func whois(_ nick: String) async throws {
        print("not implemented")
    }

    public func names(_ channel: String) async throws {
        print("not implemented")
    }

    // Low-Level

    public func send(_ command: Command) async throws {
        let line = encode(command)
        // simple token-bucket (1 msg / 200ms) to be nice:
        try await rateLimit()
        sendQueue.append(line)
    }

    // Private

    private func handshake() async {
        do {
            try await send(.cap("LS", ["302"]))
            try await send(.nick(config.nick))
            try await send(.user(username: config.username, realname: config.realname))
            // The readerLoop handles CAP LS/ACK/NAK, AUTHENTICATE, 001, etc.
        } catch {
            eventsContinuation.yield(.disconnected(error))
        }
    }

    public func awaitRegistered() async {
        if isRegistered { return }
        await withCheckedContinuation { (cc: CheckedContinuation<Void, Never>) in
            registrationAwaiters.append(cc)
        }
    }

    private func markRegistered() {
        guard !isRegistered else { return }
        isRegistered = true
        for cc in registrationAwaiters { cc.resume() }
        registrationAwaiters.removeAll()
        eventsContinuation.yield(.registered)
    }

    private func writerLoop() async {
        while isConnected {
            if let line = sendQueue.first {
                do {
                    try await transport.writeLine(line)
                    sendQueue.removeFirst()
                } catch {
                    eventsContinuation.yield(.disconnected(error)); break
                }
            } else {
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        }
    }

    private func readerLoop() async {
        while isConnected {
            do {
                guard let raw = try await transport.readLine() else { break }
                let msg = parse(raw)
                await handle(msg)
            } catch {
                eventsContinuation.yield(.disconnected(error)); break
            }
        }
    }

    private func parse(_ raw: String) -> Message {
        return .init(tags: [:], command: "", params: [], raw: raw)
    }

    private func handle(_ m: Message) async {
        switch m.command {
        case "PING":
            if let t = m.params.last { try? await send(.pong(t)) }
        case "001": // RPL_WELCOME
            markRegistered()
        case "CAP":
            print("unhandled CAP: \(m.raw)")
        case "AUTHENTICATE":
            print("unhandled AUTHENTICATE: \(m.raw)")
        case "PRIVMSG":
            eventsContinuation.yield(.privmsg(m))
        case "NOTICE":
            eventsContinuation.yield(.notice(m))
        default:
            eventsContinuation.yield(.message(m))
            print("unhandled message to aggregate: \(m.raw)")
        }
    }
}
