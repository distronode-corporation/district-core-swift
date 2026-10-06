import DistrictLive
import DistrictModel
import DistrictNetwork
import Foundation
import XCTest

/// A clock that moves only when a test moves it.
///
/// ⛔ NO TEST IN THIS TARGET SLEEPS. Every wait the module makes goes through
/// ``LiveClock``, and this one parks each sleeper until ``advance(by:)`` passes its
/// deadline, so an hour-long renewal ceiling is proved in microseconds.
final class ManualClock: LiveClock, @unchecked Sendable {
    private struct Sleeper {
        let id: UUID
        let deadline: Int64
        let continuation: CheckedContinuation<Void, Error>
    }

    private let lock = NSLock()
    private var now: Int64
    private var sleepers: [Sleeper] = []
    private var cancelledBeforeParking: Set<UUID> = []

    init(now: Int64 = 1_790_433_000_000) {
        self.now = now
    }

    func nowMilliseconds() -> Int64 {
        lock.withLock { now }
    }

    var pendingSleepers: Int {
        lock.withLock { sleepers.count }
    }

    func sleep(milliseconds: Int64) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                enum Outcome { case parked, due, cancelled }
                let outcome: Outcome = lock.withLock {
                    if cancelledBeforeParking.remove(id) != nil {
                        return .cancelled
                    }
                    if milliseconds <= 0 {
                        return .due
                    }
                    sleepers.append(Sleeper(id: id, deadline: now + milliseconds, continuation: continuation))
                    return .parked
                }
                switch outcome {
                case .parked: break
                case .due: continuation.resume()
                case .cancelled: continuation.resume(throwing: CancellationError())
                }
            }
        } onCancel: {
            let parked: Sleeper? = lock.withLock {
                guard let index = sleepers.firstIndex(where: { $0.id == id }) else {
                    cancelledBeforeParking.insert(id)
                    return nil
                }
                return sleepers.remove(at: index)
            }
            parked?.continuation.resume(throwing: CancellationError())
        }
    }

    /// Move time forward and wake every sleeper whose deadline has passed, earliest
    /// first.
    func advance(by milliseconds: Int64) {
        let due: [Sleeper] = lock.withLock {
            now += milliseconds
            let ready = sleepers.filter { $0.deadline <= now }.sorted { $0.deadline < $1.deadline }
            sleepers.removeAll { $0.deadline <= now }
            return ready
        }
        due.forEach { $0.continuation.resume() }
    }
}

/// A value a test hands over when it chooses, to a caller already waiting for it.
final class Scripted<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var ready: [Value] = []
    private var waiting: [CheckedContinuation<Value, Never>] = []
    private(set) var calls = 0

    init(_ values: [Value] = []) {
        ready = values
    }

    var callCount: Int {
        lock.withLock { calls }
    }

    var waiters: Int {
        lock.withLock { waiting.count }
    }

    func next() async -> Value {
        await withCheckedContinuation { continuation in
            let value: Value? = lock.withLock {
                calls += 1
                guard !ready.isEmpty else {
                    waiting.append(continuation)
                    return nil
                }
                return ready.removeFirst()
            }
            if let value {
                continuation.resume(returning: value)
            }
        }
    }

    func provide(_ value: Value) {
        let waiter: CheckedContinuation<Value, Never>? = lock.withLock {
            guard !waiting.isEmpty else {
                ready.append(value)
                return nil
            }
            return waiting.removeFirst()
        }
        waiter?.resume(returning: value)
    }
}

final class FakeMinter: TelemetryTokenMinter {
    let results = Scripted<Result<TelemetryTokenResponse, ApiError>>()

    func mintTelemetryToken(workspaceId _: String) async -> Result<TelemetryTokenResponse, ApiError> {
        await results.next()
    }
}

enum FakeFailure: Error {
    case refused
    case broken
}

final class FakeTransport: TelemetrySocketTransport, @unchecked Sendable {
    let outcomes = Scripted<Result<FakeSocket, FakeFailure>>()
    private let lock = NSLock()
    private var dialled: [(url: URL, subprotocols: [String])] = []

    var dials: [(url: URL, subprotocols: [String])] {
        lock.withLock { dialled }
    }

    func connect(to url: URL, subprotocols: [String]) async throws -> any TelemetrySocket {
        lock.withLock { dialled.append((url, subprotocols)) }
        return try await outcomes.next().get()
    }
}

final class FakeSocket: TelemetrySocket, @unchecked Sendable {
    let selectedSubprotocol: String?
    private let frames = Scripted<Result<TelemetrySocketFrame, FakeFailure>>()
    private let lock = NSLock()
    private var closedCount = 0
    private var sentTexts: [String] = []
    /// When set, the next send waits for ``releaseSend()`` before it is recorded: how a
    /// test proves the runner waits for one send before starting the next.
    private var gate: CheckedContinuation<Void, Never>?
    private var holdNextSend = false
    private var failSends = false

    init(selected: String? = TelemetryProtocol.subprotocol) {
        selectedSubprotocol = selected
    }

    var isClosed: Bool {
        lock.withLock { closedCount > 0 }
    }

    /// Every text sent, in the order it was sent.
    var sent: [String] {
        lock.withLock { sentTexts }
    }

    /// Hold the next send until ``releaseSend()``.
    func holdSends() {
        lock.withLock { holdNextSend = true }
    }

    var isHoldingASend: Bool {
        lock.withLock { gate != nil }
    }

    func releaseSend() {
        let held: CheckedContinuation<Void, Never>? = lock.withLock {
            defer { gate = nil }
            return gate
        }
        held?.resume()
    }

    /// Make every send throw, as a broken socket's does.
    func breakSends() {
        lock.withLock { failSends = true }
    }

    func send(_ text: String) async throws {
        let hold = lock.withLock {
            defer { holdNextSend = false }
            return holdNextSend
        }
        if hold {
            await withCheckedContinuation { continuation in
                lock.withLock { gate = continuation }
            }
        }
        try lock.withLock {
            if failSends {
                throw FakeFailure.broken
            }
            sentTexts.append(text)
        }
    }

    var readers: Int {
        frames.waiters
    }

    func push(_ frame: TelemetrySocketFrame) {
        frames.provide(.success(frame))
    }

    func fail() {
        frames.provide(.failure(.broken))
    }

    func receive() async throws -> TelemetrySocketFrame {
        try await frames.next().get()
    }

    /// ⚠️ A CLOSED SOCKET'S PENDING READ THROWS, as `URLSessionWebSocketTask`'s does.
    func close() async {
        lock.withLock { closedCount += 1 }
        frames.provide(.failure(.broken))
    }
}

final class FakePresenceAPI: PresenceAPI, @unchecked Sendable {
    enum Call: Equatable {
        case register(String)
        case unregister
    }

    let registerResults = Scripted<Result<Void, ApiError>>()
    let unregisterResults = Scripted<Result<Void, ApiError>>()
    private let lock = NSLock()
    private var log: [Call] = []

    var calls: [Call] {
        lock.withLock { log }
    }

    func registerPresence(token: String) async -> Result<Void, ApiError> {
        lock.withLock { log.append(.register(token)) }
        return await registerResults.next()
    }

    func unregisterPresence() async -> Result<Void, ApiError> {
        lock.withLock { log.append(.unregister) }
        return await unregisterResults.next()
    }
}

/// The ``HTTPTransport`` double for the two `ApiClient` conformances.
///
/// ⚠️ A THIRD SMALL COPY, for the reason `RepositoryTransport` gives: test targets
/// share no code.
final class LiveHTTPTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [HTTPResponse]
    private var sent: [HTTPRequest] = []

    init(json bodies: String...) {
        responses = bodies.map { HTTPResponse(statusCode: 200, body: Data($0.utf8)) }
    }

    var requests: [HTTPRequest] {
        lock.withLock { sent }
    }

    var bodies: [String] {
        requests.compactMap { $0.body.flatMap { String(data: $0, encoding: .utf8) } }
    }

    func send(_ request: HTTPRequest, followRedirects _: Bool) async throws -> HTTPResponse {
        lock.withLock {
            sent.append(request)
            return responses.removeFirst()
        }
    }
}

extension ApiClient {
    static func live(_ transport: LiveHTTPTransport) -> ApiClient {
        ApiClient(baseURL: URL(string: "https://www.distronode.com")!, transport: transport, accessToken: { "at.jwt" })
    }
}

extension XCTestCase {
    /// Spin until `condition` holds, yielding between checks. ⚠️ Bounded, and fails
    /// rather than hanging.
    func waitUntil(
        iterations: Int = 100_000,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: () async -> Bool
    ) async {
        for _ in 0 ..< iterations {
            if await condition() {
                return
            }
            await Task.yield()
        }
        XCTFail("condition never became true", file: file, line: line)
    }
}

extension TelemetryTokenResponse {
    static func grant(
        token: String = "a.b.c",
        expiresAt: Int64,
        wsUrl: String? = "wss://telemetry.example.com/ws/telemetry"
    ) -> TelemetryTokenResponse {
        TelemetryTokenResponse(success: true, token: token, expiresAt: expiresAt, wsUrl: wsUrl)
    }
}

extension Result {
    var failureOnly: Failure? {
        guard case let .failure(error) = self else { return nil }
        return error
    }
}
