// SPDX-FileCopyrightText: Distronode Corporation
//
// SPDX-License-Identifier: Apache-2.0

@testable import DistrictAuthCore
import Foundation
import XCTest

/// The ``TokenStore`` boundary: what a failing store may and may not cost the
/// user.
///
/// ⛔ SPLIT OUT OF `TokenRefreshCoordinatorTests` BECAUSE THAT FILE HIT THE
/// 500-LINE `file_length` CEILING, not because these are a lesser tier. Every
/// case here is one where the obvious handling of a store error, treat it as
/// "no session", or let the error propagate, is a PERMANENT sign-out for a
/// user whose device was merely locked for a moment.
final class TokenRefreshStoreBoundaryTests: XCTestCase {
    private func makeCoordinator(
        store: SpyTokenStore,
        client: any RefreshClient,
        clock: TestClock
    ) -> TokenRefreshCoordinator {
        TokenRefreshCoordinator(store: store, refreshClient: client, now: clock.now)
    }

    // ── The store boundary ───────────────────────────────────────────────────

    func testAnUnreadableStoreIsRetryableRatherThanASignOut() async {
        let clock = TestClock(AuthFixtures.now)
        let store = SpyTokenStore(session: AuthFixtures.session())
        let client = ScriptedRefreshClient()
        let coordinator = makeCoordinator(store: store, client: client, clock: clock)
        await store.failReads(true)

        // ⛔ A locked device fails the Keychain read transiently. Reporting that
        // as "no session" signs the user out for locking their phone.
        await expectEqual(.retryLater(.storeUnavailable)) { await coordinator.accessToken() }
        await expectEqual(0) { await client.callCount }
    }

    func testAnUnreadableMarkerIsRetryableRatherThanASignOut() async {
        let clock = TestClock(AuthFixtures.now)
        let store = ReadableSessionUnreadableMarkerStore(session: AuthFixtures.session())
        let client = ScriptedRefreshClient()
        let coordinator = TokenRefreshCoordinator(store: store, refreshClient: client, now: clock.now)

        await expectEqual(.retryLater(.storeUnavailable)) { await coordinator.accessToken() }
        await expectEqual(0) { await client.callCount }
    }

    func testAFailedMarkerWriteAbortsInsteadOfSendingAnUnprotectedRefresh() async {
        let clock = TestClock(AuthFixtures.now)
        let store = SpyTokenStore(session: AuthFixtures.session())
        let client = ScriptedRefreshClient(script: [.success(AuthFixtures.tokens(index: 2))])
        let coordinator = makeCoordinator(store: store, client: client, clock: clock)
        await store.failMarkerWrites(true)

        await expectEqual(.retryLater(.markerNotDurable)) { await coordinator.accessToken() }
        // ⛔ A skipped mutation must abort, never fall through to the action it
        // was protecting. Without the marker a crash mid-refresh would strand
        // the successor and the next launch would present a spent token.
        await expectEqual(0) { await client.callCount }
        let session = await store.session
        XCTAssertEqual(session?.refreshToken, "refresh-1")
    }

    // ── A failed store must not lose the new pair ────────────────────────────

    func testAFailedWriteKeepsTheRotatedPairAndKeepsWorking() async {
        let clock = TestClock(AuthFixtures.now)
        let store = SpyTokenStore(session: AuthFixtures.session())
        let client = ScriptedRefreshClient(script: [.success(AuthFixtures.tokens(index: 2))])
        let coordinator = makeCoordinator(store: store, client: client, clock: clock)
        await store.failNextWrites(1)

        // ⛔ The predecessor is already spent server-side, so discarding the
        // successor here would convert a momentary Keychain failure into a
        // PERMANENT sign-out.
        await expectEqual(.available("access-2")) { await coordinator.accessToken() }
        // ⚠️ And the marker stays set, so a crash before the retry lands on the
        // clean interrupted-refresh path rather than on a replay.
        let marker = await store.pending
        XCTAssertEqual(marker, "refresh-1")
    }

    func testTheRescuedPairIsRetriedAndUsedInsteadOfTheSpentDiskCopy() async {
        let clock = TestClock(AuthFixtures.now)
        let store = SpyTokenStore(session: AuthFixtures.session())
        let client = ScriptedRefreshClient(script: [
            .success(AuthFixtures.tokens(index: 2)),
            .success(AuthFixtures.tokens(index: 3, at: AuthFixtures.now + 20 * 60 * 1000)),
        ])
        let coordinator = makeCoordinator(store: store, client: client, clock: clock)
        await store.failNextWrites(1)

        _ = await coordinator.accessToken()
        clock.advance(by: 20 * 60 * 1000)
        await expectEqual(.available("access-3")) { await coordinator.accessToken() }

        // ⛔ THE SECOND REFRESH PRESENTED refresh-2, NOT THE refresh-1 STILL ON
        // DISK. Presenting the disk copy is the replay that revokes the family.
        await expectEqual(["refresh-1", "refresh-2"]) { await client.presented }
        let session = await store.session
        XCTAssertEqual(session?.refreshToken, "refresh-3")
    }

    /// ⛔ THE RESCUE IS NEVER PRESENTED FROM MEMORY ALONE. With every write
    /// refused, the first refresh's successor lives only in memory and the disk
    /// keeps the spent predecessor; an acquisition that presented the rescue
    /// anyway would re-mark the pending marker with a token the disk does not
    /// hold, so a crash mid-refresh then presented the spent disk copy, the
    /// replay that revokes the family. The attempts answer retryable instead,
    /// and the marker keeps naming the spent disk token, so a crash lands on the
    /// interrupted-refresh path (CodeRabbit, 2026-11-23).
    func testAPersistentlyFailingStoreStillNeverRepresentsAToken() async {
        let clock = TestClock(AuthFixtures.now)
        let store = SpyTokenStore(session: AuthFixtures.session())
        let client = ScriptedRefreshClient(script: [
            .success(AuthFixtures.tokens(index: 2)),
        ])
        let coordinator = makeCoordinator(store: store, client: client, clock: clock)
        await store.failNextWrites(.max)

        // The first refresh goes out from the disk session and its successor
        // lands only in memory, with the marker still naming the spent disk token.
        await expectEqual(.available("access-2")) { await coordinator.accessToken() }
        await expectEqual("refresh-1") { await store.pending }

        // Every later attempt refuses: presenting the rescue while it is
        // unwritten is the replay window above, so nothing else reaches the wire
        // and the rescue and the marker both stay for the keychain's recovery.
        clock.millis = AuthFixtures.now + 20 * 60 * 1000
        await expectEqual(.retryLater(.storeUnavailable)) { await coordinator.accessToken() }
        await expectEqual(.retryLater(.storeUnavailable)) { await coordinator.accessToken() }

        await expectEqual(["refresh-1"]) { await client.presented }
        await expectEqual("refresh-1") { await store.pending }
        let written = await store.writtenSessions
        XCTAssertTrue(written.isEmpty)
    }

    /// ⛔ THE QUIT'S LAST-CHANCE WRITE LEAVES THE SAME FENCE BEHIND WHEN IT REFUSES:
    /// the rescue and the marker both stay, so a process that exits anyway lands
    /// on the interrupted-refresh path at the next launch rather than presenting
    /// the spent disk token, and the rescue survives the quit call for the
    /// keychain's recovery (CodeRabbit, 2026-11-23).
    func testTheQuitsLastChanceWriteKeepsTheRescueAndTheMarkerWhenItRefuses() async {
        let clock = TestClock(AuthFixtures.now)
        let store = SpyTokenStore(session: AuthFixtures.session())
        let client = ScriptedRefreshClient(script: [
            .success(AuthFixtures.tokens(index: 2)),
        ])
        let coordinator = makeCoordinator(store: store, client: client, clock: clock)
        await store.failNextWrites(.max)

        // The successor exists only in memory, with the marker naming the spent disk token.
        await expectEqual(.available("access-2")) { await coordinator.accessToken() }

        await coordinator.finishRefreshInFlight()
        await expectEqual("refresh-1") { await store.pending }

        // The rescue survived the quit's refused write: the next acquisition
        // retries the write rather than refreshing, and nothing more reaches the wire.
        clock.millis = AuthFixtures.now + 20 * 60 * 1000
        await expectEqual(.retryLater(.storeUnavailable)) { await coordinator.accessToken() }
        await expectEqual(["refresh-1"]) { await client.presented }
    }

    /// ⛔ THE QUIT'S RETRY IS A REAL WRITE: when the keychain has come back, the
    /// rescue lands on disk, the marker naming the spent token is cleared, and
    /// the next acquisition serves from the store rather than the rescue slot
    /// (CodeRabbit, 2026-11-23).
    func testTheQuitsRetryLandsTheRescueAndClearsTheMarkerWhenTheStoreRecovers() async {
        let clock = TestClock(AuthFixtures.now)
        let store = SpyTokenStore(session: AuthFixtures.session())
        let client = ScriptedRefreshClient(script: [
            .success(AuthFixtures.tokens(index: 2)),
            .success(AuthFixtures.tokens(index: 3)),
        ])
        let coordinator = makeCoordinator(store: store, client: client, clock: clock)
        await store.failNextWrites(1)

        // The first rotation's write refuses; the successor survives only as the
        // rescue, with the marker naming the spent disk token.
        await expectEqual(.available("access-2")) { await coordinator.accessToken() }
        await expectEqual("refresh-1") { await store.pending }

        await coordinator.finishRefreshInFlight()
        await expectNil { await store.pending }
        await expectEqual("refresh-2") { await store.session?.refreshToken }

        // The next acquisition serves from the store, not the rescue slot.
        clock.millis = AuthFixtures.now + 20 * 60 * 1000
        await expectEqual(.available("access-3")) { await coordinator.accessToken() }
        await expectEqual(["refresh-1", "refresh-2"]) { await client.presented }
        await expectEqual("refresh-3") { await store.session?.refreshToken }
    }

    /// ⛔ THE QUIT WAITS FOR A REFRESH ALREADY ON THE WIRE before it touches the
    /// marker: with the gate held for the whole retry, the parked refresh is
    /// awaited to its own adoption, which clears its own marker, and the quit's
    /// retry then finds nothing left to do (CodeRabbit, 2026-11-23).
    func testTheQuitWaitsForARefreshAlreadyOnTheWire() async {
        let store = SpyTokenStore(session: AuthFixtures.session())
        let client = ScriptedRefreshClient(script: [.success(AuthFixtures.tokens(index: 2))], open: false)
        let coordinator = makeCoordinator(store: store, client: client, clock: TestClock(AuthFixtures.now))
        await store.failNextWrites(1)

        let onWire = Task { await coordinator.accessToken() }
        await waitUntil { await client.callCount >= 1 }
        let quit = Task { await coordinator.finishRefreshInFlight() }
        await client.open()

        await expectEqual(.available("access-2")) { await onWire.value }
        _ = await quit.value
        // ⛔ THE MARKER IS CLEARED ONLY BY THE QUIT'S OWN RETRY: the wire's
        // adoption refused its write, so its marker deliberately survives, and
        // a quit that returned without waiting would leave it naming the
        // spent disk token. This is the assertion that pins the waiting
        // (CodeRabbit, 2026-11-23).
        await expectNil { await store.pending }
        await expectEqual("refresh-2", "the quit's retry is what persisted the rescue") {
            await store.session?.refreshToken
        }
    }

    /// ⛔ A LOGIN COMPLETING BESIDE A QUEUED REFRESH MUST NOT COST A ROTATION.
    /// The store reads inside `acquire` are suspension points, so `adopt` can
    /// land in the middle of them; without the fence that follows those reads
    /// serving the login's cached token, this refreshes a credential that is
    /// seconds old, and every avoidable refresh is one closer to the shared
    /// per-user limiter that degrades the account's other devices.
    func testALoginLandingMidAcquisitionPreemptsTheRefresh() async {
        let clock = TestClock(AuthFixtures.now)
        let store = GatedReadTokenStore(session: AuthFixtures.session())
        let client = NeverRefreshClient()
        let coordinator = TokenRefreshCoordinator(store: store, refreshClient: client, now: clock.now)

        let racer = Task { await coordinator.accessToken() }
        await waitUntil { await store.readEntered }
        await coordinator.adopt(AuthFixtures.tokens(index: 9), deviceId: "device-abc")
        await store.openGate()

        let outcome = await racer.value
        XCTAssertEqual(outcome, .available("access-9"))
        await expectEqual(0) { await client.callCount }
    }

    /// ⛔ A LOGIN LANDING INSIDE THE READS MUST NOT ARM THE ABANDONED ACQUISITION
    /// WITH THE LOGIN'S OWN SESSION. The gated read answers with whatever the
    /// store holds when it resumes, which after ``adopt(_:deviceId:)`` is the new
    /// session: without the fence that follows the reads, the acquisition went on
    /// to compare that session against the marker and present its refresh token
    /// on the wire.
    ///
    /// ⚠️ AND WITH NO FRESH CACHED TOKEN THE STALE CALLER IS TOLD THE TRUTH, not a
    /// sign-out: a session exists, just not its own, so the answer is retryable
    /// and a caller following the terminal contract cannot clear the login's
    /// state and route to login while the login is live.
    func testALoginInsideTheReadsDisarmsTheAbandonedAcquisition() async {
        let store = GatedReadTokenStore(session: AuthFixtures.session())
        let refresh = NeverRefreshClient()
        let coordinator = TokenRefreshCoordinator(store: store, refreshClient: refresh, now: { AuthFixtures.now })

        let stale = Task { await coordinator.accessToken() }
        await waitUntil { await store.readEntered }
        // A login whose access token is already due, so no cached token can serve
        // it and only the fence stands between the abandoned reads and the wire.
        await coordinator.adopt(AuthFixtures.tokens(index: 9, accessLifetime: 0), deviceId: "device-abc")
        await store.openGate()

        await expectEqual(AccessTokenOutcome.retryLater(.sessionReplaced)) { await stale.value }
        await expectEqual(0, "a replaced acquisition must present nothing") { await refresh.callCount }
        await expectEqual("refresh-9", "and it must not have wiped or overwritten the login") {
            try? await store.read()?.refreshToken
        }
    }

    /// ⛔ AND WITH THE LOGIN'S OWN CALLER RIGHT BEHIND IT, THAT PRESENTATION
    /// WOULD HAVE BEEN THE SECOND OF TWO. Only the acquisition the session belongs
    /// to may put its refresh token on the wire; a second one presenting the same
    /// token is the replay the server answers by revoking the entire family.
    func testTheLoginTokenReachesTheWireExactlyOnce() async {
        let store = GatedReadTokenStore(session: AuthFixtures.session())
        let refresh = ScriptedRefreshClient(script: [.success(AuthFixtures.tokens(index: 10))], open: false)
        let coordinator = TokenRefreshCoordinator(store: store, refreshClient: refresh, now: { AuthFixtures.now })

        let stale = Task { await coordinator.accessToken() }
        await waitUntil { await store.readEntered }
        await coordinator.adopt(AuthFixtures.tokens(index: 9, accessLifetime: 0), deviceId: "device-abc")
        let fresh = Task { await coordinator.accessToken() }
        await store.openGate()
        await waitUntil { await refresh.callCount >= 1 }

        await expectEqual(AccessTokenOutcome.retryLater(.sessionReplaced)) { await stale.value }
        await refresh.open()
        await expectEqual(AccessTokenOutcome.available("access-10")) { await fresh.value }
        await expectEqual(["refresh-9"], "once, by the acquisition that owns it") { await refresh.presented }
        await expectEqual("refresh-10") { try? await store.read()?.refreshToken }
    }

    /// ⛔ A LOGIN LANDING INSIDE THE MARKER WRITE SENDS NOTHING. The marker write
    /// is the last suspension before the request, and the request is the one
    /// thing no later fence can take back: once the generation moves, this
    /// acquisition would be presenting a token the replaced session owned.
    func testALoginInsideTheMarkerWriteSendsNothing() async {
        let store = GatedMarkerTokenStore(session: AuthFixtures.session())
        let refresh = NeverRefreshClient()
        let coordinator = TokenRefreshCoordinator(store: store, refreshClient: refresh, now: { AuthFixtures.now })

        let stale = Task { await coordinator.accessToken() }
        await waitUntil { await store.markerEntered }
        await coordinator.adopt(AuthFixtures.tokens(index: 9, accessLifetime: 0), deviceId: "device-abc")
        await store.openGate()

        await expectEqual(AccessTokenOutcome.retryLater(.sessionReplaced)) { await stale.value }
        await expectEqual(0, "the request must not have left the device") { await refresh.callCount }
        await expectEqual("refresh-1", "the marker left behind names the replaced session's token") {
            try? await store.pendingRefreshToken()
        }
        await expectEqual("refresh-9", "and the login's session is untouched") {
            try? await store.read()?.refreshToken
        }
    }

    /// ⚠️ AND A STORE THAT CANNOT SAY WHETHER A REPLACEMENT EXISTS GETS THE SAFE
    /// ANSWER, the one every unreadable store gets: retryable. A locked device's
    /// read must not become a sign-out (see the ⛔ on ``TokenStore/read()``),
    /// least of all for a session that was replaced while its acquisition slept.
    func testASupersededAcquisitionWithAnUnreadableStoreIsRetryable() async {
        let store = GatedMarkerTokenStore(session: AuthFixtures.session())
        let refresh = NeverRefreshClient()
        let coordinator = TokenRefreshCoordinator(store: store, refreshClient: refresh, now: { AuthFixtures.now })

        let stale = Task { await coordinator.accessToken() }
        await waitUntil { await store.markerEntered }
        await coordinator.adopt(AuthFixtures.tokens(index: 9, accessLifetime: 0), deviceId: "device-abc")
        await store.failReads(true)
        await store.openGate()

        await expectEqual(AccessTokenOutcome.retryLater(.storeUnavailable)) { await stale.value }
        await expectEqual(0) { await refresh.callCount }
    }
}

// MARK: - Helpers

/// A store whose session reads fine but whose MARKER read throws, the one
/// combination `SpyTokenStore`'s single `failReads` flag cannot express, and the
/// only way to reach the coordinator's second store-failure branch.
private actor ReadableSessionUnreadableMarkerStore: TokenStore {
    private struct Failure: Error {}
    private let session: PersistedSession

    init(session: PersistedSession) {
        self.session = session
    }

    func read() async throws -> PersistedSession? {
        session
    }

    func write(_: PersistedSession) async throws {}
    func clear() async throws {}
    /// ⚠️ The session is a constant here, so a conditional clear of it has
    /// nothing to do.
    func clear(ifHolding _: String) async throws {}
    func pendingRefreshToken() async throws -> String? {
        throw Failure()
    }

    func markRefreshPending(_: String) async throws {}
    func clearRefreshPending() async throws {}

    /// ⚠️ The revoke outbox is inert here: nothing in this file signs out, and a
    /// store that answered a pending revoke would send this suite's coordinator
    /// down a path it is not testing.
    func pendingRevokeToken() async throws -> String? {
        nil
    }

    func markRevokePending(_: String) async throws {}
    func clearRevokePending() async throws {}
    func clearRevokePending(ifHolding _: String) async throws {}
}

/// A store whose `read()` blocks until released, so the suspension window inside
/// `acquire` can be entered deliberately rather than raced for.
private actor GatedReadTokenStore: TokenStore {
    private var session: PersistedSession?
    private var pending: String?
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private(set) var readEntered = false

    init(session: PersistedSession?) {
        self.session = session
    }

    func openGate() {
        isOpen = true
        let resuming = waiters
        waiters = []
        for waiter in resuming {
            waiter.resume()
        }
    }

    func read() async throws -> PersistedSession? {
        readEntered = true
        if !isOpen {
            await withCheckedContinuation { waiters.append($0) }
        }
        return session
    }

    func write(_ session: PersistedSession) async throws {
        self.session = session
    }

    func clear() async throws {
        session = nil
        pending = nil
    }

    func clear(ifHolding refreshToken: String) async throws {
        guard session?.refreshToken == refreshToken else { return }
        session = nil
        pending = nil
    }

    func pendingRefreshToken() async throws -> String? {
        pending
    }

    func markRefreshPending(_ refreshToken: String) async throws {
        pending = refreshToken
    }

    func clearRefreshPending() async throws {
        pending = nil
    }

    /// ⚠️ Inert, as above: this store exists to gate a `read()`, not to sign out.
    func pendingRevokeToken() async throws -> String? {
        nil
    }

    func markRevokePending(_: String) async throws {}
    func clearRevokePending() async throws {}
    func clearRevokePending(ifHolding _: String) async throws {}
}

/// A store whose `markRefreshPending` parks until released, so the window
/// between the marker write and the request can be entered deliberately rather
/// than raced for.
private actor GatedMarkerTokenStore: TokenStore {
    private struct Failure: Error {}

    private var session: PersistedSession?
    private var pending: String?
    private var failReads = false
    private(set) var markerEntered = false
    private var isOpen = false
    private var waiter: CheckedContinuation<Void, Never>?

    init(session: PersistedSession) {
        self.session = session
    }

    func failReads(_ shouldFail: Bool) {
        failReads = shouldFail
    }

    func openGate() {
        isOpen = true
        waiter?.resume()
        waiter = nil
    }

    func read() async throws -> PersistedSession? {
        if failReads {
            throw Failure()
        }
        return session
    }

    func write(_ session: PersistedSession) async throws {
        self.session = session
    }

    func clear() async throws {
        session = nil
        pending = nil
    }

    func clear(ifHolding refreshToken: String) async throws {
        guard session?.refreshToken == refreshToken else { return }
        session = nil
        pending = nil
    }

    func pendingRefreshToken() async throws -> String? {
        pending
    }

    func markRefreshPending(_ refreshToken: String) async throws {
        markerEntered = true
        if !isOpen {
            await withCheckedContinuation { waiter = $0 }
        }
        pending = refreshToken
    }

    func clearRefreshPending() async throws {
        pending = nil
    }

    /// ⚠️ Inert, as above: this store exists to gate a marker write, not to sign out.
    func pendingRevokeToken() async throws -> String? {
        nil
    }

    func markRevokePending(_: String) async throws {}
    func clearRevokePending() async throws {}
    func clearRevokePending(ifHolding _: String) async throws {}
}
