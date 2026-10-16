@testable import DistrictAuthCore
import Foundation
import XCTest

/// ``TokenRefreshCoordinator/finishRefreshInFlight()``: what a quitting app waits for.
///
/// ⛔ THE FAILURE IT EXISTS FOR IS A SIGN-OUT NOBODY ASKED FOR. A quit that lands between
/// the server's rotation and the store's write leaves the spent token on disk with the
/// marker naming it, and the next launch has to report an interrupted refresh.
final class TokenRefreshQuitTests: XCTestCase {
    func testWithNothingInFlightItReturnsAndSendsNothing() async {
        let store = SpyTokenStore(session: AuthFixtures.session())
        let client = NeverRefreshClient()
        let coordinator = TokenRefreshCoordinator(store: store, refreshClient: client, now: { AuthFixtures.now })

        await coordinator.finishRefreshInFlight()

        await expectEqual(0) { await client.callCount }
        await expectEqual(0) { await store.reads }
        await expectEqual(AuthFixtures.session()) { await store.session }
    }

    func testItWaitsForTheSuccessorToBeWrittenBeforeReturning() async {
        let store = SpyTokenStore(session: AuthFixtures.session())
        let client = ScriptedRefreshClient(script: [.success(AuthFixtures.tokens(index: 2))], open: false)
        let coordinator = TokenRefreshCoordinator(store: store, refreshClient: client, now: { AuthFixtures.now })

        let refresh = Task { await coordinator.accessToken() }
        await waitUntil { await client.callCount == 1 }

        let finished = Flag()
        let quit = Task {
            await coordinator.finishRefreshInFlight()
            await finished.raise()
        }
        for _ in 0 ..< 500 {
            await Task.yield()
        }

        // The server has not answered: the quit is still waiting, and the disk still
        // holds the token on the wire with the marker naming it.
        await expectFalse { await finished.isRaised }
        await expectEqual("refresh-1") { await store.session?.refreshToken }
        await expectEqual("refresh-1") { await store.pending }

        await client.open()
        await quit.value

        // ⛔ BY THE TIME THE QUIT MAY PROCEED, THE SUCCESSOR IS ON DISK AND THE MARKER IS GONE.
        await expectTrue { await finished.isRaised }
        await expectEqual("refresh-2") { await store.session?.refreshToken }
        await expectNil { await store.pending }
        let outcome = await refresh.value
        XCTAssertEqual(outcome, .available("access-2"))
        // It started nothing of its own: one token was presented, once.
        await expectEqual(["refresh-1"]) { await client.presented }
    }

    func testItDoesNotStartARefreshWhenTheAccessTokenHasExpired() async {
        let clock = TestClock(AuthFixtures.now)
        let store = SpyTokenStore(session: AuthFixtures.session())
        let client = ScriptedRefreshClient(script: [.success(AuthFixtures.tokens(index: 2))])
        let coordinator = TokenRefreshCoordinator(store: store, refreshClient: client, now: clock.now)
        _ = await coordinator.accessToken()
        clock.advance(by: 11 * 60 * 1000)

        await coordinator.finishRefreshInFlight()

        // ⚠️ ONE refresh, the one before the clock moved: a quit asks for nothing.
        await expectEqual(["refresh-1"]) { await client.presented }
        await expectEqual("refresh-2") { await store.session?.refreshToken }
    }

    /// ⛔ A SUCCESSOR THE KEYCHAIN REFUSED IS WRITTEN AT QUIT, so the next launch does not
    /// find the spent predecessor and its marker.
    func testASuccessorTheStoreRefusedIsWrittenBeforeTheQuit() async {
        let store = SpyTokenStore(session: AuthFixtures.session())
        await store.failNextWrites(1)
        let client = ScriptedRefreshClient(script: [.success(AuthFixtures.tokens(index: 2))])
        let coordinator = TokenRefreshCoordinator(store: store, refreshClient: client, now: { AuthFixtures.now })
        let outcome = await coordinator.accessToken()
        XCTAssertEqual(outcome, .available("access-2"))
        await expectEqual("refresh-1") { await store.session?.refreshToken }
        await expectEqual("refresh-1") { await store.pending }

        await coordinator.finishRefreshInFlight()

        await expectEqual("refresh-2") { await store.session?.refreshToken }
        await expectNil { await store.pending }
        await expectEqual(["refresh-1"]) { await client.presented }
    }
}

/// A one-way flag a test can read across tasks.
private actor Flag {
    private(set) var isRaised = false

    func raise() {
        isRaised = true
    }
}
