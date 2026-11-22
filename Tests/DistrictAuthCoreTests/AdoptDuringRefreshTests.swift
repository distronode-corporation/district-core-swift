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
}
