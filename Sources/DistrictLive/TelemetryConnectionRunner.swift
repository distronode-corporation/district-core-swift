import DistrictModel
import Foundation

/// Runs one ``TelemetryConnection`` over a real socket and a real clock.
///
/// ⛔ IT DECIDES NOTHING. Every branch about the protocol is in the state machine;
/// this actor performs its commands (mint, open, read, close, wait) and feeds each
/// result back as an event, tagged with the attempt the command was issued for.
/// Keep it that way: a decision added here is a decision tested only through
/// timing.
///
/// ⚠️ ``updates`` MUST BE READ, and is unbounded so that a slow reader never delays
/// the socket. Abandoning the stream (its consumer is cancelled or released) stops
/// the connection, the same as ``stop()``.
public actor TelemetryConnectionRunner {
    /// Every update the connection reports, ending after ``TelemetryUpdate/ended(_:)``.
    public nonisolated let updates: AsyncStream<TelemetryUpdate>

    private let continuation: AsyncStream<TelemetryUpdate>.Continuation
    private let minter: any TelemetryTokenMinter
    private let transport: any TelemetrySocketTransport
    private let clock: any LiveClock
    private let jitter: @Sendable () -> Double
    private var machine: TelemetryConnection
    private var sockets: [Int: any TelemetrySocket] = [:]
    private var timers: [TelemetryTimer: Task<Void, Never>] = [:]
    /// The last send issued on each attempt's socket, which the next one waits for.
    private var sends: [Int: Task<Void, Never>] = [:]

    /// - Parameters:
    ///   - broadcast: whether the socket takes the workspace-wide relay; see
    ///     ``TelemetryConnection/broadcast``. ⚠️ The Mac rings from that relay and keeps the
    ///     default; a client that only watches transcripts passes false.
    ///   - jitter: a number between 0 and 1 for each backoff wait: ``randomJitter()`` in the
    ///     apps, a constant in a test.
    public init(
        workspaceId: String,
        broadcast: Bool = true,
        minter: any TelemetryTokenMinter,
        transport: any TelemetrySocketTransport,
        clock: any LiveClock,
        jitter: @escaping @Sendable () -> Double
    ) {
        (updates, continuation) = AsyncStream.makeStream(bufferingPolicy: .unbounded)
        machine = TelemetryConnection(workspaceId: workspaceId, broadcast: broadcast)
        self.minter = minter
        self.transport = transport
        self.clock = clock
        self.jitter = jitter
    }

    /// A uniformly random number between 0 and 1, for
    /// ``init(workspaceId:broadcast:minter:transport:clock:jitter:)``.
    public static func randomJitter() -> Double {
        Double.random(in: 0 ... 1)
    }

    /// Where the connection is.
    public var phase: TelemetryConnection.Phase {
        machine.phase
    }

    /// Start connecting. ⚠️ Once: a stopped connection is not restarted, start a new
    /// runner.
    public func start() {
        // ⚠️ REGISTERED HERE AND NOT IN `init`, because the handler captures `self`,
        // which an actor's initialiser may not hand out before it returns.
        continuation.onTermination = { [weak self] _ in
            Task { await self?.stop() }
        }
        apply(.start)
    }

    /// Stop: close the socket, cancel every wait, and report
    /// ``TelemetryUpdate/ended(_:)`` with no error, unless it had already ended.
    public func stop() {
        apply(.stop)
    }

    /// Receive `callId`'s live transcript, now and after every reconnect. See
    /// ``TelemetryConnection``.
    public func subscribeTranscript(callId: String) {
        apply(.subscribeTranscript(callId: callId))
    }

    /// Stop receiving `callId`'s live transcript.
    public func unsubscribeTranscript(callId: String) {
        apply(.unsubscribeTranscript(callId: callId))
    }

    /// Ask again for `callId`'s transcript, for a fresh snapshot.
    public func resubscribeTranscript(callId: String) {
        apply(.resubscribeTranscript(callId: callId))
    }

    private func apply(_ event: TelemetryConnectionEvent) {
        let commands = machine.handle(event, atMilliseconds: clock.nowMilliseconds(), jitter: jitter())
        for command in commands {
            perform(command)
        }
    }

    private func perform(_ command: TelemetryConnectionCommand) {
        switch command {
        case let .mint(attempt):
            let workspaceId = machine.workspaceId
            Task {
                let result = await minter.mintTelemetryToken(workspaceId: workspaceId)
                apply(.minted(result, attempt: attempt))
            }
        case let .open(url, subprotocols, attempt):
            Task {
                do {
                    let socket = try await transport.connect(to: url, subprotocols: subprotocols)
                    opened(socket, attempt: attempt)
                } catch {
                    apply(.openFailed(reason: String(describing: error), attempt: attempt))
                }
            }
        case let .close(attempt):
            // ⚠️ A CLOSE DOES NOT WAIT FOR SENDS STILL PENDING on the socket, which then fail
            // on a closed socket. Nothing is lost by it: the server keeps a socket's ops per
            // socket and drops them with it, so an unsubscribe before a close is not needed.
            sends[attempt] = nil
            if let socket = sockets.removeValue(forKey: attempt) {
                Task { await socket.close() }
            }
        case let .send(text, attempt):
            // ⛔ CHAINED, NOT FIRED: two tasks started one after the other may run in either
            // order, and `socket.mode` must reach the server before the subscriptions. A
            // failed send is not reported here; the broken socket's read reports it.
            // ⚠️ The machine sends only while open, when the socket is always held; the
            // guard states that rather than trapping on it.
            guard let socket = sockets[attempt] else { return }
            let previous = sends[attempt]
            sends[attempt] = Task {
                await previous?.value
                try? await socket.send(text)
            }
        case let .schedule(timer, delay, attempt):
            timers[timer]?.cancel()
            timers[timer] = Task { [clock] in
                guard await (try? clock.sleep(milliseconds: delay)) != nil else { return }
                apply(.timerFired(timer, attempt: attempt))
            }
        case .cancelTimers:
            timers.values.forEach { $0.cancel() }
            timers = [:]
        case let .emit(update):
            continuation.yield(update)
        case .finish:
            continuation.finish()
        }
    }

    /// ⚠️ THE SOCKET IS HELD BEFORE THE MACHINE HEARS OF IT, so that when the machine
    /// answers a stale handshake with ``TelemetryConnectionCommand/close(attempt:)``
    /// there is a socket to close.
    private func opened(_ socket: any TelemetrySocket, attempt: Int) {
        sockets[attempt] = socket
        apply(.opened(selectedSubprotocol: socket.selectedSubprotocol, attempt: attempt))
        guard sockets[attempt] != nil else { return }
        Task { await read(socket, attempt: attempt) }
    }

    private func read(_ socket: any TelemetrySocket, attempt: Int) async {
        do {
            while true {
                let frame = try await socket.receive()
                apply(.received(frame, attempt: attempt))
                if case .closed = frame {
                    return
                }
            }
        } catch {
            apply(.broken(reason: String(describing: error), attempt: attempt))
        }
    }
}
