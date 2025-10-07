import Foundation
import Network

public protocol Transport: Sendable {
    func open(host: String, port: Int, tls: Bool) async throws
    func readLine() async throws -> String?
    func writeLine(_ line: String) async throws
    func close() async throws
}

public actor NWTransport: Transport {
    private var conn: NWConnection?
    private let queue = DispatchQueue(label: "irc.nw")

    public func open(host: String, port: Int, tls: Bool) async throws {
        let params = NWParameters.tcp
        if tls { params.defaultProtocolStack.applicationProtocols.insert(NWProtocolTLS.Options(), at: 0) }
        let endpoint = NWEndpoint.Host(host)
        let connection = NWConnection(host: endpoint, port: NWEndpoint.Port(rawValue: UInt16(port))!, using: params)
        self.conn = connection
        let ready = AsyncThrowingStream<Void, Error> { cont in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready: cont.yield(()); cont.finish()
                case .failed(let e): cont.finish(throwing: e)
                default: break
                }
            }
            connection.start(queue: queue)
        }
        for try await _ in ready { }
    }

    public func readLine() async throws -> String? {
        try await withCheckedThrowingContinuation { cc in
            conn?.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, isComplete, error in
                if let error { cc.resume(throwing: error); return }
                guard var data = data, !data.isEmpty else {
                    if isComplete { cc.resume(returning: nil) } else { cc.resume(returning: "") }
                    return
                }
                // You’ll want a small buffer and decode until you hit \r\n; omitted for brevity.
                let s = String(decoding: data, as: UTF8.self)
                cc.resume(returning: s)
            }
        }
    }

    public func writeLine(_ line: String) async throws {
        let out = line.hasSuffix("\r\n") ? line : line + "\r\n"
        try await withCheckedThrowingContinuation { (cc: CheckedContinuation<Void, Error>) in
            guard let conn else {
                cc.resume(throwing: NSError(domain: "NWTransport", code: -1, userInfo: [NSLocalizedDescriptionKey: "Connection is not open"]))
                return
            }
            conn.send(content: out.data(using: .utf8), completion: .contentProcessed { err in
                if let err {
                    cc.resume(throwing: err)
                } else {
                    cc.resume(returning: ())
                }
            })
        }
    }

    public func close() async { conn?.cancel(); conn = nil }
}
