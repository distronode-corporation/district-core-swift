import DistrictModel
import Foundation

/// Where this Mac's presence stands.
public enum PresenceStatus: Sendable, Equatable {
    /// Not registered, and not trying: never started, stopped, or signed out.
    case off
    /// The first registration is on its way.
    case registering
    /// Registered: a call handed to this member can ring this Mac.
    case registered
    /// The last registration failed. It is tried again after
    /// ``PresenceController/retryMilliseconds``; calls do not ring here meanwhile.
    case failed(ApiError)
}

/// This Mac's presence: whether the server counts it as a device a call can ring.
///
/// ⛔ A MAC IS RUNG OVER THE TELEMETRY SOCKET, AND ONLY WHILE ITS PRESENCE IS FRESH.
/// The server counts a `kind: "desktop"` row as ringable only while it is under
/// ten minutes old (`DESKTOP_PRESENCE_FRESH_MS`), and only then publishes the
/// `call_ringing` event that rings it. So the row is renewed every
/// ``heartbeatMilliseconds``, half that window, and a Mac that slept or lost its
/// network stops holding a caller on a ring nobody hears within ten minutes
/// without saying a word.
///
/// ⛔ ONE REQUEST AT A TIME, AND THE LAST ONE ASKED FOR WINS. A renewal and the
/// sign-out's unregister can both be on their way (a renewal as the user signs
/// out), and a register that reached the server after the unregister would leave a
/// signed-out Mac ringable for ten minutes. Each call waits for the one before it,
/// and a renewal that finds the controller stopped by the time its turn comes is
/// never sent.
///
/// ⛔ ``signOut()`` WITHDRAWS EVERY ROW THIS INSTALLATION HOLDS, NOT ONLY PRESENCE.
/// `devices/unregister` runs a `deleteMany` with no `kind` predicate, so the Mac's
/// APNs alert row goes with it. That is right for a sign-out and wrong for "stop
/// ringing here", which is why ``stop()`` sends nothing: a stopped presence lapses
/// on the server within ten minutes.
public actor PresenceController {
    /// How often presence is renewed: half the server's ten-minute window, so one
    /// late renewal does not let it lapse.
    public static let heartbeatMilliseconds: Int64 = 5 * 60 * 1000

    /// How soon a failed registration is tried again, well inside the window.
    public static let retryMilliseconds: Int64 = 60 * 1000

    public private(set) var status: PresenceStatus = .off

    private let api: any PresenceAPI
    private let clock: any LiveClock
    private let token: String
    private var loop: Task<Void, Never>?
    private var tail: Task<Void, Never>?
    private var running = false

    /// - Parameter token: the opaque install nonce the row is registered under. ⚠️ A
    ///   fresh UUID per run of the app: it identifies nothing but this run, and the
    ///   server never sends anything to it.
    public init(api: any PresenceAPI, clock: any LiveClock, token: String) {
        self.api = api
        self.clock = clock
        self.token = token
    }

    /// Register now, and renew every ``heartbeatMilliseconds`` until stopped.
    /// ⚠️ Idempotent while running.
    public func start() {
        guard !running else { return }
        running = true
        status = .registering
        loop = Task { [clock] in
            var wait = await renew()
            while await (try? clock.sleep(milliseconds: wait)) != nil {
                wait = await renew()
            }
        }
    }

    /// Stop renewing. Sends nothing; see the ⛔ on the type.
    public func stop() {
        running = false
        loop?.cancel()
        loop = nil
        status = .off
    }

    /// Stop renewing, wait for a renewal already on its way, then withdraw this
    /// installation's registrations.
    ///
    /// ⚠️ A FAILURE DOES NOT BLOCK A SIGN-OUT: the caller goes on to revoke the
    /// session regardless, and the presence row lapses within ten minutes.
    @discardableResult
    public func signOut() async -> Result<Void, ApiError> {
        stop()
        return await serialised(onlyWhileRunning: false) { api in await api.unregisterPresence() }
    }

    /// One registration, unless the controller stopped before its turn came.
    /// Returns how long to wait before the next one.
    private func renew() async -> Int64 {
        let result = await serialised(onlyWhileRunning: true) { [token] api in
            await api.registerPresence(token: token)
        }
        guard running else { return Self.heartbeatMilliseconds }
        switch result {
        case .success:
            status = .registered
            return Self.heartbeatMilliseconds
        case let .failure(error):
            status = .failed(error)
            return Self.retryMilliseconds
        }
    }

    /// Runs `call` after every call queued before it has finished.
    ///
    /// ⛔ `onlyWhileRunning` IS CHECKED WHEN THE TURN COMES, NOT WHEN IT IS QUEUED.
    /// That is the whole ordering guarantee: a register queued before a sign-out
    /// reaches its turn after ``stop()`` and is not sent. It answers success, which
    /// nothing reads, because ``renew()`` discards results once stopped.
    private func serialised(
        onlyWhileRunning: Bool,
        _ call: @escaping @Sendable (any PresenceAPI) async -> Result<Void, ApiError>
    ) async -> Result<Void, ApiError> {
        let previous = tail
        let turn = Task<Result<Void, ApiError>, Never> { [api] in
            await previous?.value
            guard self.running || !onlyWhileRunning else { return .success(()) }
            return await call(api)
        }
        tail = Task { _ = await turn.value }
        return await turn.value
    }
}
