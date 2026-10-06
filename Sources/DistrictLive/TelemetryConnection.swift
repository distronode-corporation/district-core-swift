import DistrictModel
import Foundation

/// What a connection reports to the app.
public enum TelemetryUpdate: Sendable, Equatable {
    /// The socket is open.
    ///
    /// ⛔ EVERY `connected` AFTER THE FIRST FOLLOWS A GAP IN WHICH EVENTS MAY HAVE BEEN
    /// MISSED, including the second each renewal takes. Read the state again on
    /// each one rather than trusting what earlier events built up.
    case connected
    /// An event for this workspace.
    case event(TelemetryEnvelope)
    /// A message that is not an envelope this client can read, or names another
    /// workspace. Its content was dropped unread. Treat it as a hint that something
    /// changed.
    case discarded
    /// The socket closed or could not be opened, and the connection tries again
    /// after `delayMilliseconds`.
    case reconnecting(delayMilliseconds: Int64, cause: TelemetryDisconnect)
    /// The connection has ended and will not reconnect. nil when the app stopped
    /// it. ⚠️ Always the last update a connection sends.
    case ended(TelemetryLiveError?)
}

/// Why a connection is reconnecting.
public enum TelemetryDisconnect: Sendable, Equatable {
    /// Routine: the credential was about to expire, so the socket is being replaced
    /// on a fresh one. Not worth showing.
    case renewal
    /// The server refused the credential (4401). A new one is minted first.
    case unauthorized(reason: String)
    /// The server closed the socket with another code (1001 when it shuts down).
    case closed(code: Int, reason: String)
    /// Nothing arrived for ``TelemetryProtocol/silenceLimitMilliseconds``, not even
    /// a heartbeat.
    case silent
    /// The handshake did not finish within ``TelemetryProtocol/connectTimeoutMilliseconds``.
    case connectTimedOut
    /// The network: no connection, a TLS failure, a refused handshake, a socket
    /// that broke.
    case network(String)
    /// The credential could not be minted, for a reason that may pass.
    case mint(ApiError)
}

/// Why a connection ended for good.
///
/// ⛔ NONE OF THESE IS FIXED BY RETRYING ON A TIMER, so the connection stops. The
/// app shows it and starts a new connection once something changed (the user
/// signed in again, or was added back to the workspace).
public enum TelemetryLiveError: Error, Sendable, Equatable {
    /// The server would not mint a credential: the member may not read the
    /// workspace, or the request itself was refused.
    case mint(ApiError)
    /// The server answered with a credential that cannot be presented.
    case invalidGrant
    /// The socket's address is missing or unusable.
    case endpoint(TelemetryEndpointError)
    /// The server did not select ``TelemetryProtocol/subprotocol``.
    case protocolMismatch
    /// The server closed the socket with 4403.
    case forbidden(reason: String)
}

/// The timers a connection runs. At most one of each is pending.
public enum TelemetryTimer: Sendable, Equatable, Hashable, CaseIterable {
    /// The handshake's deadline.
    case connect
    /// The moment to replace the socket before its credential expires.
    case renewal
    /// The silence watchdog's next check.
    case silence
    /// The end of a backoff wait.
    case backoff
}

/// Everything that can happen to a connection.
///
/// ⚠️ EVERY ASYNCHRONOUS RESULT CARRIES THE `attempt` ITS COMMAND WAS ISSUED FOR,
/// and a result for any other attempt is stale and changes nothing. That is what
/// makes a late mint, a handshake that finishes after its timeout, or a timer that
/// fires after the socket it guarded was replaced, harmless.
public enum TelemetryConnectionEvent: Sendable, Equatable {
    case start
    /// The app stopped the connection, or nobody is reading its updates.
    case stop
    case minted(Result<TelemetryTokenResponse, ApiError>, attempt: Int)
    case opened(selectedSubprotocol: String?, attempt: Int)
    case openFailed(reason: String, attempt: Int)
    case received(TelemetrySocketFrame, attempt: Int)
    /// Reading the socket threw: the connection broke.
    case broken(reason: String, attempt: Int)
    case timerFired(TelemetryTimer, attempt: Int)
    /// Receive `callId`'s live transcript on this connection, now and after every
    /// reconnect, until ``unsubscribeTranscript(callId:)``.
    case subscribeTranscript(callId: String)
    /// Stop receiving `callId`'s live transcript.
    case unsubscribeTranscript(callId: String)
    /// Ask again for `callId`'s transcript, which brings a fresh snapshot: how a client
    /// heals a gap. Nothing for a call that is not subscribed.
    case resubscribeTranscript(callId: String)
}

/// What a connection asks its driver to do.
public enum TelemetryConnectionCommand: Sendable, Equatable {
    /// Mint a credential; answer with ``TelemetryConnectionEvent/minted(_:attempt:)``.
    case mint(attempt: Int)
    /// Open a socket; answer with ``TelemetryConnectionEvent/opened(selectedSubprotocol:attempt:)``
    /// or ``TelemetryConnectionEvent/openFailed(reason:attempt:)``, then read it.
    case open(url: URL, subprotocols: [String], attempt: Int)
    /// Close `attempt`'s socket, if there is one, and stop reading it.
    case close(attempt: Int)
    /// Arm `timer`, replacing any pending one of the same kind.
    case schedule(TelemetryTimer, afterMilliseconds: Int64, attempt: Int)
    case cancelTimers
    /// Send `text` on `attempt`'s socket, after every send issued before it.
    case send(String, attempt: Int)
    case emit(TelemetryUpdate)
    /// The connection has ended; release everything.
    case finish
}

/// One workspace's live telemetry connection, as a pure state machine.
///
/// ⛔ NO SOCKET, NO TIMER AND NO NETWORK CALL IN HERE, ONLY EVENTS IN AND COMMANDS
/// OUT, the same split `DistrictCall`'s controllers make. Every rule of the protocol
/// is an assertion about a command list, tested on Linux with an injected time;
/// ``TelemetryConnectionRunner`` performs the commands over a
/// ``TelemetrySocketTransport`` and a ``LiveClock``.
///
/// What it does:
///
/// - Mints a credential, opens the socket with it, and reports
///   ``TelemetryUpdate/connected``.
/// - A minute before the credential expires (no sooner than 5 s after opening, no
///   later than an hour) it closes the socket and reconnects at once on a fresh
///   credential, because the server closes a socket whose credential expired.
/// - 4401: mints a new credential and reconnects. 4403: stops.
/// - Any other close, a broken socket, 90 s of silence, a 15 s handshake, or a
///   mint that failed for a reason that may pass: reconnects after a backoff that
///   doubles with each consecutive failure, with jitter, capped at 60 s. A socket
///   that stayed open 30 s resets the count.
/// - A credential with more than the renewal lead left is reused on reconnect;
///   only a refused or expiring one is replaced.
/// - ⛔ EVERY OPEN RE-SENDS THE CONNECTION'S OPS, because the server keeps them per socket:
///   `socket.mode` first when ``broadcast`` is false, then a `transcript.subscribe` for
///   every subscribed call, in call-id order. A renewal is an open like any other, so a
///   transcript survives the socket being replaced every fifteen minutes.
public struct TelemetryConnection: Sendable, Equatable {
    /// Where the connection is.
    public enum Phase: Sendable, Equatable {
        case idle
        case minting
        /// The handshake is under way on a credential expiring at `expiresAt`.
        case connecting(expiresAt: Int64)
        case open(openedAt: Int64, lastHeardAt: Int64)
        case waiting
        case ended
    }

    public let workspaceId: String

    /// Whether this socket takes the workspace-wide `call_*` and `message_*` relay. ⚠️ The
    /// server's default is true; false is sent as `socket.mode` on every open. A client
    /// that wants only transcripts (the phone) says false; one that rings (the Mac) must not.
    public let broadcast: Bool

    /// The calls whose live transcript this connection receives.
    public private(set) var transcriptSubscriptions: Set<String> = []

    public private(set) var phase: Phase = .idle

    /// The attempt every command is currently issued for. See the ⚠️ on
    /// ``TelemetryConnectionEvent``.
    public private(set) var attempt = 0

    /// Consecutive failed attempts, for the backoff.
    public private(set) var failures = 0

    /// The credential the last socket used, kept while it has time left.
    private var token: TelemetryTokenResponse?

    public init(workspaceId: String, broadcast: Bool = true) {
        self.workspaceId = workspaceId
        self.broadcast = broadcast
    }

    /// Apply one event at `now` (epoch milliseconds).
    ///
    /// - Parameter jitter: a number between 0 and 1 for a backoff this event may
    ///   start; ignored otherwise. See ``TelemetryProtocol/backoffMilliseconds(failures:jitter:)``.
    public mutating func handle(
        _ event: TelemetryConnectionEvent,
        atMilliseconds now: Int64,
        jitter: Double
    ) -> [TelemetryConnectionCommand] {
        switch event {
        case .start:
            guard phase == .idle else { return [] }
            return beginAttempt(now: now)
        case .stop:
            return stop()
        case let .minted(result, attempt):
            guard attempt == self.attempt, phase == .minting else { return [] }
            return minted(result, jitter: jitter)
        case let .opened(selected, attempt):
            // ⛔ A STALE SOCKET IS CLOSED, NOT IGNORED. The driver already holds it;
            // a handshake that finished after its timeout or after a stop would
            // otherwise stay open with nothing reading it.
            guard attempt == self.attempt, case let .connecting(expiresAt) = phase else {
                return [.close(attempt: attempt)]
            }
            return opened(selected, expiresAt: expiresAt, now: now)
        case let .openFailed(reason, attempt):
            guard attempt == self.attempt, case .connecting = phase else { return [] }
            return retry(.network(reason), stable: false, jitter: jitter)
        case let .received(frame, attempt):
            guard attempt == self.attempt, case let .open(openedAt, _) = phase else { return [] }
            return received(frame, openedAt: openedAt, now: now, jitter: jitter)
        case let .broken(reason, attempt):
            guard attempt == self.attempt, case let .open(openedAt, _) = phase else { return [] }
            return retry(.network(reason), stable: isStable(openedAt, now), jitter: jitter)
        case let .timerFired(timer, attempt):
            guard attempt == self.attempt else { return [] }
            return timerFired(timer, now: now, jitter: jitter)
        case let .subscribeTranscript(callId):
            return subscribe(callId)
        case let .unsubscribeTranscript(callId):
            guard transcriptSubscriptions.remove(callId) != nil else { return [] }
            return sendIfOpen(.unsubscribe(callId: callId))
        case let .resubscribeTranscript(callId):
            guard transcriptSubscriptions.contains(callId) else { return [] }
            return sendIfOpen(.subscribe(callId: callId))
        }
    }

    // MARK: - Transcript ops

    /// ⚠️ A CALL ID THE SERVER WOULD REFUSE IS NOT RECORDED, so it is never re-sent on
    /// every open only to earn a `bad_request` each time.
    private mutating func subscribe(_ callId: String) -> [TelemetryConnectionCommand] {
        guard TranscriptClientOp.isValidCallId(callId), !transcriptSubscriptions.contains(callId) else { return [] }
        transcriptSubscriptions.insert(callId)
        return sendIfOpen(.subscribe(callId: callId))
    }

    /// While closed, nothing is sent: the next open sends every subscription.
    private func sendIfOpen(_ op: TranscriptClientOp) -> [TelemetryConnectionCommand] {
        guard case .open = phase else { return [] }
        return send(op)
    }

    /// ⚠️ THE FORCE IS SAFE: an op's text is nil only for an invalid call id, and none
    /// reaches here (``subscribe(_:)`` refuses one before it is recorded).
    private func send(_ op: TranscriptClientOp) -> [TelemetryConnectionCommand] {
        [.send(op.text!, attempt: attempt)]
    }

    /// What every open sends: the socket's mode, then each subscription.
    private func opsOnOpen() -> [TelemetryConnectionCommand] {
        let mode = broadcast ? [] : send(.socketMode(broadcast: false))
        return mode + transcriptSubscriptions.sorted().flatMap { send(.subscribe(callId: $0)) }
    }

    // MARK: - Transitions

    /// A new attempt: reuse the credential while it has more than the renewal lead
    /// left, else mint.
    private mutating func beginAttempt(now: Int64) -> [TelemetryConnectionCommand] {
        attempt += 1
        if let token, token.expiresAt &- now > TelemetryProtocol.renewalLeadMilliseconds {
            return open(token)
        }
        token = nil
        phase = .minting
        return [.mint(attempt: attempt)]
    }

    private mutating func minted(
        _ result: Result<TelemetryTokenResponse, ApiError>,
        jitter: Double
    ) -> [TelemetryConnectionCommand] {
        switch result {
        case let .success(minted):
            guard TelemetryProtocol.isPresentable(minted.token) else { return end(.invalidGrant) }
            token = minted
            return open(minted)
        case let .failure(error):
            guard Self.isTransient(error) else { return end(.mint(error)) }
            return retry(.mint(error), stable: false, jitter: jitter)
        }
    }

    private mutating func open(_ token: TelemetryTokenResponse) -> [TelemetryConnectionCommand] {
        switch TelemetryProtocol.socketURL(wsUrl: token.wsUrl, workspaceId: workspaceId) {
        case let .failure(error):
            return end(.endpoint(error))
        case let .success(url):
            phase = .connecting(expiresAt: token.expiresAt)
            return [
                .open(
                    url: url,
                    subprotocols: TelemetryProtocol.offeredSubprotocols(token: token.token),
                    attempt: attempt
                ),
                .schedule(.connect, afterMilliseconds: TelemetryProtocol.connectTimeoutMilliseconds, attempt: attempt),
            ]
        }
    }

    private mutating func opened(_ selected: String?, expiresAt: Int64, now: Int64) -> [TelemetryConnectionCommand] {
        guard selected == TelemetryProtocol.subprotocol else {
            return [.close(attempt: attempt)] + end(.protocolMismatch)
        }
        phase = .open(openedAt: now, lastHeardAt: now)
        return [
            .emit(.connected),
            .schedule(
                .renewal,
                afterMilliseconds: TelemetryProtocol.renewalDelayMilliseconds(expiresAt: expiresAt, now: now),
                attempt: attempt
            ),
            .schedule(.silence, afterMilliseconds: TelemetryProtocol.silenceLimitMilliseconds, attempt: attempt),
        ] + opsOnOpen()
    }

    private mutating func received(
        _ frame: TelemetrySocketFrame,
        openedAt: Int64,
        now: Int64,
        jitter: Double
    ) -> [TelemetryConnectionCommand] {
        phase = .open(openedAt: openedAt, lastHeardAt: now)
        switch frame {
        case let .text(text):
            return [.emit(update(for: Data(text.utf8)))]
        case let .binary(bytes):
            return [.emit(update(for: bytes))]
        case .heartbeat:
            return []
        case let .closed(code, reason):
            return closed(code: code, reason: reason, stable: isStable(openedAt, now), jitter: jitter)
        }
    }

    /// ⛔ A MESSAGE THAT IS NOT AN ENVELOPE FOR THIS WORKSPACE IS REPORTED WITHOUT ITS
    /// CONTENT. Call events are customer data; nothing about an unreadable one is
    /// kept, logged or passed on.
    private func update(for bytes: Data) -> TelemetryUpdate {
        guard let envelope = try? JSONDecoder().decode(TelemetryEnvelope.self, from: bytes),
              envelope.workspaceId == workspaceId
        else { return .discarded }
        return .event(envelope)
    }

    private mutating func closed(
        code: Int,
        reason: String,
        stable: Bool,
        jitter: Double
    ) -> [TelemetryConnectionCommand] {
        switch code {
        case TelemetryProtocol.closeUnauthorized:
            token = nil
            return [.close(attempt: attempt)] + retry(.unauthorized(reason: reason), stable: stable, jitter: jitter)
        case TelemetryProtocol.closeForbidden:
            return [.close(attempt: attempt)] + end(.forbidden(reason: reason))
        default:
            return [.close(attempt: attempt)] + retry(
                .closed(code: code, reason: reason),
                stable: stable,
                jitter: jitter
            )
        }
    }

    private mutating func timerFired(
        _ timer: TelemetryTimer,
        now: Int64,
        jitter: Double
    ) -> [TelemetryConnectionCommand] {
        switch (timer, phase) {
        case (.connect, .connecting):
            return [.close(attempt: attempt)] + retry(.connectTimedOut, stable: false, jitter: jitter)
        case let (.renewal, .open(openedAt, _)):
            token = nil
            return [.close(attempt: attempt)] + retry(.renewal, stable: isStable(openedAt, now), jitter: jitter)
        case let (.silence, .open(openedAt, lastHeardAt)):
            let quietFor = now &- lastHeardAt
            guard quietFor >= TelemetryProtocol.silenceLimitMilliseconds else {
                // ⚠️ NOT A RESET PER MESSAGE: the watchdog re-checks the fact when it
                // fires and re-arms for what is left, so a busy socket costs no timer
                // churn.
                let left = TelemetryProtocol.silenceLimitMilliseconds - quietFor
                return [.schedule(.silence, afterMilliseconds: left, attempt: attempt)]
            }
            return [.close(attempt: attempt)] + retry(.silent, stable: isStable(openedAt, now), jitter: jitter)
        case (.backoff, .waiting):
            return beginAttempt(now: now)
        default:
            // ⚠️ A TIMER FOR ANOTHER PHASE OF THE SAME ATTEMPT (the handshake's deadline
            // after it opened, say). A cancelled timer is a promise; the phase is the
            // fact.
            return []
        }
    }

    /// A reconnect: a renewal after an established socket goes again at once, and
    /// anything else counts as a failure and backs off.
    private mutating func retry(
        _ cause: TelemetryDisconnect,
        stable: Bool,
        jitter: Double
    ) -> [TelemetryConnectionCommand] {
        if stable {
            failures = 0
        }
        var delay: Int64 = 0
        if !(stable && cause == .renewal) {
            failures += 1
            delay = TelemetryProtocol.backoffMilliseconds(failures: failures, jitter: jitter)
        }
        phase = .waiting
        return [
            .emit(.reconnecting(delayMilliseconds: delay, cause: cause)),
            .schedule(.backoff, afterMilliseconds: delay, attempt: attempt),
        ]
    }

    private mutating func stop() -> [TelemetryConnectionCommand] {
        switch phase {
        case .ended:
            []
        case .connecting, .open:
            [.close(attempt: attempt)] + end(nil)
        case .idle, .minting, .waiting:
            end(nil)
        }
    }

    private mutating func end(_ error: TelemetryLiveError?) -> [TelemetryConnectionCommand] {
        phase = .ended
        return [.cancelTimers, .emit(.ended(error)), .finish]
    }

    private func isStable(_ openedAt: Int64, _ now: Int64) -> Bool {
        now &- openedAt >= TelemetryProtocol.stableAfterMilliseconds
    }

    /// Whether a failed mint may succeed if tried again later.
    ///
    /// Transient: no answer, a 5xx, a 429, and a 401. ⚠️ THE 401 IS TRANSIENT HERE
    /// AND FINAL ON THE LINUX CLIENT, because that client's API layer refreshes and
    /// resends on a 401 and this one does not: ``ApiClient`` reports the refused
    /// bearer so the NEXT request refreshes, which makes the retry the refresh. A
    /// session that has really ended is signed out by the app, which stops the
    /// connection.
    ///
    /// Final: a 403 (not a member), any other 4xx, and an answer that does not
    /// decode or affirm success. Retrying the same request cannot fix those.
    public static func isTransient(_ error: ApiError) -> Bool {
        switch error {
        case .transport:
            true
        case let .http(status, _):
            status >= 500 || status == 429 || status == 401
        case .decoding:
            false
        }
    }
}
