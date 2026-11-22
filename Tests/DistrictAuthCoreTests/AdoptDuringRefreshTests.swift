@testable import DistrictAuthCore
import Foundation
import XCTest

/// A login that lands while a refresh of the outgoing session is on the wire.
///
/// ⛔ THE PROPERTY UNDER TEST IS "THE SESSION THAT REPLACED ONE STAYS THE SESSION
/// ON DISK", the login-side twin of ``SignOutDuringRefreshTests``. ``adopt(_:deviceId:)``
/// trips the same generation fence ``forget()`` does: without the bump, the stale
/// refresh's answer passed the check, and a rejection's `clear()` wiped the login
/// that had just been written, or a success overwrote it with the old session's
/// successor.
final class AdoptDuringRefreshTests: XCTestCase {
    func testARejectionLandingAfterALoginKeepsTheLoginAndItsCachedToken() async {
        let store = SpyTokenStore(session: AuthFixtures.session())
        let refresh = ScriptedRefreshClient(script: [.rejected], open: false)
        let coordinator = TokenRefreshCoordinator(store: store, refreshClient: refresh, now: { AuthFixtures.now })

        let stale = Task { await coordinator.accessToken() }
        await waitUntil { await refresh.callCount >= 1 }

        await coordinator.adopt(AuthFixtures.tokens(index: 5), deviceId: "device-abc")
        await refresh.open()

        await expectEqual(AccessTokenOutcome.retryLater(.sessionReplaced)) { await stale.value }
        await expectEqual("refresh-5", "a stale rejection must not wipe the session that replaced it") {
            await store.session?.refreshToken
        }
        await expectEqual(AccessTokenOutcome.available("access-5"), "nor the login's cached access token") {
            await coordinator.accessToken()
        }
        await expectEqual(1) { await refresh.callCount }
    }

    /// ⛔ AND THE LOGIN'S OWN CALLERS MUST NOT LATCH ONTO THE ABANDONED REFRESH.
    /// ``adopt(_:deviceId:)`` drops the stale in-flight task with the generation, so
    /// the next caller refreshes the NEW session instead of inheriting its verdict.
    func testACallerAfterTheLoginDoesNotInheritTheAbandonedRefresh() async {
        let store = SpyTokenStore(session: AuthFixtures.session())
        let refresh = ScriptedRefreshClient(
            script: [.rejected, .success(AuthFixtures.tokens(index: 6))],
            open: false
        )
        let coordinator = TokenRefreshCoordinator(store: store, refreshClient: refresh, now: { AuthFixtures.now })

        let stale = Task { await coordinator.accessToken() }
        await waitUntil { await refresh.callCount >= 1 }

        // A login whose access token is already due, so the next call has to refresh.
        await coordinator.adopt(AuthFixtures.tokens(index: 5, accessLifetime: 0), deviceId: "device-abc")
        let fresh = Task { await coordinator.accessToken() }
        await waitUntil { await refresh.callCount >= 2 }
        await refresh.open()

        await expectEqual(AccessTokenOutcome.retryLater(.sessionReplaced)) { await stale.value }
        await expectEqual(AccessTokenOutcome.available("access-6")) { await fresh.value }
        await expectEqual(["refresh-1", "refresh-5"]) { await refresh.presented }
        await expectEqual("refresh-6") { await store.session?.refreshToken }
        await expectNil { await store.pending }
    }

    /// ⛔ A STALE SUCCESS OVERTURNS NOTHING EITHER: the fence hands the old session's
    /// live successor to the outbox rather than letting it overwrite the login.
    func testASuccessorLandingAfterALoginIsRevokedNotAdopted() async {
        let store = SpyTokenStore(session: AuthFixtures.session())
        let refresh = ScriptedRefreshClient(script: [.success(AuthFixtures.tokens(index: 2))], open: false)
        let revoke = ScriptedRevokeClient()
        let coordinator = TokenRefreshCoordinator(
            store: store,
            refreshClient: refresh,
            revokeClient: revoke,
            now: { AuthFixtures.now }
        )

        let stale = Task { await coordinator.accessToken() }
        await waitUntil { await refresh.callCount >= 1 }

        await coordinator.adopt(AuthFixtures.tokens(index: 5), deviceId: "device-abc")
        await refresh.open()

        await expectEqual(AccessTokenOutcome.retryLater(.sessionReplaced)) { await stale.value }
        await expectEqual("refresh-5", "the old session's successor must not overwrite the login") {
            await store.session?.refreshToken
        }
        await expectEqual(["refresh-2"], "it is revoked instead") { await revoke.presented }
    }

    /// ⚠️ A RESCUE BELONGS TO THE SESSION IT WAS MINTED FOR. A login drops the
    /// replaced session's unwritten successor rather than letting the next
    /// acquisition repersist it over the login, the same way ``forget()`` drops it.
    func testALoginDropsTheReplacedSessionRescue() async {
        let store = SpyTokenStore(session: AuthFixtures.session())
        await store.failNextWrites(1)
        let refresh = ScriptedRefreshClient(
            script: [.success(AuthFixtures.tokens(index: 2)), .success(AuthFixtures.tokens(index: 6))]
        )
        let coordinator = TokenRefreshCoordinator(store: store, refreshClient: refresh, now: { AuthFixtures.now })

        // The first rotation's write fails, so its successor survives only as the rescue.
        await expectEqual(AccessTokenOutcome.available("access-2")) { await coordinator.accessToken() }

        await coordinator.adopt(AuthFixtures.tokens(index: 5, accessLifetime: 0), deviceId: "device-abc")
        await expectEqual(AccessTokenOutcome.available("access-6")) { await coordinator.accessToken() }

        // ⛔ THE SECOND PRESENTATION IS THE LOGIN'S TOKEN, NOT THE RESCUE'S: without
        // the drop, the rescue repersisted the old session and refreshed THAT.
        await expectEqual(["refresh-1", "refresh-5"]) { await refresh.presented }
        await expectEqual("refresh-6") { await store.session?.refreshToken }
        await expectNil { await store.pending }
    }

    /// ⛔ THE LOGIN HOLDS THE SINGLE-FLIGHT GATE FOR ITS OWN WRITE. The production
    /// store is a struct of synchronous calls that serialises nothing (see the ⛔
    /// on ``TokenStore/clear(ifHolding:)``), so against it a caller arriving
    /// mid-write read the OUTGOING session at the new generation, with no fence
    /// between it and the wire: it presented the old token again, or its
    /// rejection's clear wiped the login's write. Callers now latch onto the
    /// adoption and get its outcome instead.
    func testACallerDuringTheLoginWriteLatchesOntoTheAdoption() async {
        let store = ConcurrentWriteStore(session: AuthFixtures.session())
        let refresh = NeverRefreshClient()
        let coordinator = TokenRefreshCoordinator(store: store, refreshClient: refresh, now: { AuthFixtures.now })

        let login = Task {
            await coordinator.adopt(AuthFixtures.tokens(index: 9, accessLifetime: 0), deviceId: "device-abc")
        }
        await waitUntil { store.writeEntered }

        let raced = Task { await coordinator.accessToken() }
        store.openGate()
        _ = await login.value

        await expectEqual(AccessTokenOutcome.available("access-9")) { await raced.value }
        await expectEqual(0, "nothing may be presented while the login is unwritten") { await refresh.callCount }
        await expectEqual("refresh-9") { try? await store.read()?.refreshToken }
    }

    /// ⚠️ AND A LOGIN THAT EXISTS ONLY AS THE RESCUE COUNTS AS THE REPLACEMENT.
    /// A sign-out's wipe plus a login whose write the store refused leaves the
    /// replacement nowhere on disk, and the superseded caller must not be told its
    /// verdict is terminal while the login's session is alive in memory.
    func testASupersededCallerIsRetryableWhileTheLoginIsOnlyInMemory() async {
        let store = SpyTokenStore(session: AuthFixtures.session())
        await store.failNextWrites(1)
        let refresh = ScriptedRefreshClient(script: [.success(AuthFixtures.tokens(index: 2))], open: false)
        let coordinator = TokenRefreshCoordinator(store: store, refreshClient: refresh, now: { AuthFixtures.now })

        let stale = Task { await coordinator.accessToken() }
        await waitUntil { await refresh.callCount >= 1 }
        await coordinator.forget()
        await coordinator.adopt(AuthFixtures.tokens(index: 9, accessLifetime: 0), deviceId: "device-abc")
        await refresh.open()

        await expectEqual(AccessTokenOutcome.retryLater(.sessionReplaced)) { await stale.value }
    }
}

/// A NON-ACTOR store, the production keychain store's shape: every call is
/// individually safe but nothing serialises them, so a read landing beside a
/// parked write answers with whatever the store holds THEN, before the write
/// applies.
private final class ConcurrentWriteStore: TokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var session: PersistedSession?
    private var pending: String?
    private var isOpen = false
    private var gatedWrite: CheckedContinuation<Void, Never>?
    private var writeEnteredStorage = false

    init(session: PersistedSession?) {
        self.session = session
    }

    var writeEntered: Bool {
        lock.withLock { writeEnteredStorage }
    }

    func openGate() {
        let waiter = lock.withLock {
            isOpen = true
            let waiter = gatedWrite
            gatedWrite = nil
            return waiter
        }
        waiter?.resume()
    }

    func read() async throws -> PersistedSession? {
        lock.withLock { session }
    }

    func write(_ session: PersistedSession) async throws {
        // The continuation is registered and flagged under one lock hold, so the
        // test can observe the write parked without a missed-resume window.
        let gate = lock.withLock {
            if isOpen {
                return false
            }
            writeEnteredStorage = true
            return true
        }
        if gate {
            await withCheckedContinuation { continuation in
                lock.withLock {
                    gatedWrite = continuation
                }
            }
        }
        lock.withLock {
            self.session = session
        }
    }

    func clear() async throws {
        lock.withLock {
            session = nil
            pending = nil
        }
    }

    func clear(ifHolding refreshToken: String) async throws {
        lock.withLock {
            guard session?.refreshToken == refreshToken else { return }
            session = nil
            pending = nil
        }
    }

    func pendingRefreshToken() async throws -> String? {
        lock.withLock { pending }
    }

    func markRefreshPending(_ refreshToken: String) async throws {
        lock.withLock {
            pending = refreshToken
        }
    }

    func clearRefreshPending() async throws {
        lock.withLock {
            pending = nil
        }
    }

    /// ⚠️ Inert: nothing here signs out, and the adoption under test never
    /// touches the outbox.
    func pendingRevokeToken() async throws -> String? {
        nil
    }

    func markRevokePending(_: String) async throws {}
    func clearRevokePending() async throws {}
    func clearRevokePending(ifHolding _: String) async throws {}
}
