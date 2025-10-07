import Foundation
import Network

public protocol Transport: Sendable {
    func open(host: String, port: Int, tls: Bool) async throws
    func readLine() async throws -> String?
    func writeLine(_ line: String) async throws
    func close() async throws
}

// MARK: - Network Transport Error

public enum TransportError: Error, CustomStringConvertible {
    case notConnected
    case connectionFailed(Error)
    case readFailed(Error)
    case writeFailed(Error)
    case invalidData
    case connectionClosed

    public var description: String {
        switch self {
        case .notConnected:
            return "Transport is not connected"
        case .connectionFailed(let error):
            return "Connection failed: \(error.localizedDescription)"
        case .readFailed(let error):
            return "Read failed: \(error.localizedDescription)"
        case .writeFailed(let error):
            return "Write failed: \(error.localizedDescription)"
        case .invalidData:
            return "Invalid data received"
        case .connectionClosed:
            return "Connection closed"
        }
    }
}

// MARK: - NWConnection Transport

public actor NWTransport: Transport {
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "com.irc.nwtransport", qos: .userInitiated)

    // Line buffering
    private var buffer = Data()
    private let maxBufferSize = 1024 * 64  // 64KB max buffer

    public init() {}

    // MARK: - Connection Management

    public func open(host: String, port: Int, tls: Bool) async throws {
        guard connection == nil else { return }

        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        params.includePeerToPeer = false

        // Configure TLS if needed
        if tls {
            let tlsOptions = NWProtocolTLS.Options()
            params.defaultProtocolStack.applicationProtocols.insert(tlsOptions, at: 0)
        }

        // Create endpoint
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: UInt16(port))
                ?? NWEndpoint.Port(integerLiteral: UInt16(port))
        )

        let conn = NWConnection(to: endpoint, using: params)
        self.connection = conn

        // Wait for connection to be ready
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in

            // Use a class to wrap the continuation and make it thread-safe
            final class ContinuationBox: @unchecked Sendable {
                var continuation: CheckedContinuation<Void, Error>?
                let lock = NSLock()

                init(_ continuation: CheckedContinuation<Void, Error>) {
                    self.continuation = continuation
                }

                func resumeOnce(_ block: (CheckedContinuation<Void, Error>) -> Void) {
                    lock.lock()
                    defer { lock.unlock() }
                    if let cont = continuation {
                        block(cont)
                        continuation = nil
                    }
                }
            }

            let box = ContinuationBox(continuation)

            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    box.resumeOnce { $0.resume() }

                case .failed(let error):
                    box.resumeOnce { cont in
                        cont.resume(throwing: TransportError.connectionFailed(error))
                    }

                case .waiting(let error):
                    // Still trying to connect, log but don't fail yet
                    print("Connection waiting: \(error)")

                case .cancelled:
                    box.resumeOnce { $0.resume(throwing: TransportError.connectionClosed) }

                default:
                    break
                }
            }

            conn.start(queue: queue)
        }
    }

    public func close() async throws {
        await cleanup()
    }

    private func cleanup() async {
        connection?.cancel()
        connection = nil
        buffer.removeAll()
    }

    // MARK: - Reading

    public func readLine() async throws -> String? {
        guard connection != nil else {
            throw TransportError.notConnected
        }

        // Check if we already have a complete line in the buffer
        if let line = try extractLine() {
            return line
        }

        // Keep reading until we get a complete line
        while true {
            guard let conn = connection else {
                throw TransportError.notConnected
            }

            // Read more data
            let data = try await receiveData(from: conn)

            // Connection closed
            guard let data = data else {
                // Return any remaining buffered data as final line
                if !buffer.isEmpty {
                    let remaining = String(data: buffer, encoding: .utf8)
                    buffer.removeAll()
                    return remaining
                }
                return nil
            }

            // Append to buffer
            buffer.append(data)

            // Check buffer size
            if buffer.count > maxBufferSize {
                buffer.removeAll()
                throw TransportError.invalidData
            }

            // Try to extract a line
            if let line = try extractLine() {
                return line
            }
        }
    }

    private func receiveData(from connection: NWConnection) async throws -> Data? {
        try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) {
                data, _, isComplete, error in
                if let error = error {
                    continuation.resume(throwing: TransportError.readFailed(error))
                    return
                }

                if let data = data, !data.isEmpty {
                    continuation.resume(returning: data)
                } else if isComplete {
                    continuation.resume(returning: nil)
                } else {
                    // No data but not complete - shouldn't happen, but return empty
                    continuation.resume(returning: Data())
                }
            }
        }
    }

    private func extractLine() throws -> String? {
        // Look for CRLF (\r\n)
        guard let crlfRange = buffer.range(of: Data([0x0D, 0x0A])) else {
            return nil
        }

        // Extract line data (without CRLF)
        let lineData = buffer.subdata(in: 0..<crlfRange.lowerBound)

        // Remove line and CRLF from buffer
        buffer.removeSubrange(0..<crlfRange.upperBound)

        // Convert to string
        guard let line = String(data: lineData, encoding: .utf8) else {
            throw TransportError.invalidData
        }

        return line
    }

    // MARK: - Writing

    public func writeLine(_ line: String) async throws {
        guard let conn = connection else {
            throw TransportError.notConnected
        }

        // Ensure line ends with CRLF
        let output = line.hasSuffix("\r\n") ? line : line + "\r\n"

        guard let data = output.data(using: .utf8) else {
            throw TransportError.invalidData
        }

        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            conn.send(
                content: data,
                completion: .contentProcessed { error in
                    if let error = error {
                        continuation.resume(throwing: TransportError.writeFailed(error))
                    } else {
                        continuation.resume()
                    }
                })
        }
    }
}

// MARK: - Mock Transport (for testing)

/// A mock transport for testing that uses in-memory streams
public actor MockTransport: Transport {
    private var readLines: [String] = []
    private var writtenLines: [String] = []
    private var isOpen = false

    public init() {}

    public func open(host: String, port: Int, tls: Bool) async throws {
        isOpen = true
    }

    public func readLine() async throws -> String? {
        guard isOpen else { throw TransportError.notConnected }
        guard !readLines.isEmpty else {
            // Simulate waiting for data
            try await Task.sleep(nanoseconds: 100_000_000)
            return nil
        }
        return readLines.removeFirst()
    }

    public func writeLine(_ line: String) async throws {
        guard isOpen else { throw TransportError.notConnected }
        let cleaned = line.trimmingCharacters(in: .whitespacesAndNewlines)
        writtenLines.append(cleaned)
    }

    public func close() async throws {
        isOpen = false
        readLines.removeAll()
    }

    // Test helpers
    public func queueRead(_ line: String) {
        readLines.append(line)
    }

    public func getWrittenLines() -> [String] {
        return writtenLines
    }

    public func clearWrittenLines() {
        writtenLines.removeAll()
    }
}
