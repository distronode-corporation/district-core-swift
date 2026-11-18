@testable import DistrictAuthCore
import Foundation
import XCTest

/// A sign-out that lands while a rotated successor is being written to the store.
///
/// ⛔ THE PROPERTY UNDER TEST IS "SIGNED OUT STAYS SIGNED OUT", ONE AWAIT LATER THAN
/// ``SignOutDuringRefreshTests``. The refresh's answer passed the generation check, then
/// the store write suspended and ``TokenRefreshCoordinator/forget()`` ran inside it.
/// Without a second check the adoption went on to cache the successor's access token
/// and hand it back, and a write that landed after the sign-out's wipe left the
/// successor on disk for the next cold start.
final class AdoptDuringSignOutTests: XCTestCase {
    private func makeCoordinator(_ store: GatedWriteTokenStore) -> TokenRefreshCoordinator {
        TokenRefreshCoordinator(
            store: store,
            refreshClient: ScriptedRefreshClient(script: [.success(AuthFixtures.tokens(index: 2))]),
            now: { AuthFixtures.now }
        )
    }

    func testASignOutDuringTheWriteCachesNothingAndUndoesTheWrite() async {
        let store = GatedWriteTokenStore(session: AuthFixtures.session())
        let coordinator = makeCoordinator(store)

        let request = Task { await coordinator.accessToken() }
        await waitUntil { await store.writeEntered }
        await coordinator.forget()
        await store.openGate()

        await expectEqual(AccessTokenOutcome.reauthRequired(.noSession)) { await request.value }
        await expectNil("the successor written after the wipe is wiped too") { await store.session }
        await expectEqual(AccessTokenOutcome.reauthRequired(.noSession), "nor is it cached") {
            await coordinator.accessToken()
        }
        await expectEqual("refresh-2", "the live successor goes to the outbox") { await store.revokePending }
    }

    /// ⚠️ A REFUSED WRITE KEEPS THE SUCCESSOR IN MEMORY, which a sign-out must also end: the
    /// next request would otherwise rescue it and sign the previous user back in.
    func testASignOutDuringAFailedWriteDropsTheRescuedSuccessor() async {
        let store = GatedWriteTokenStore(session: AuthFixtures.session(), failWrites: true)
        let coordinator = makeCoordinator(store)

        let request = Task { await coordinator.accessToken() }
        await waitUntil { await store.writeEntered }
        await coordinator.forget()
        await store.openGate()

        await expectEqual(AccessTokenOutcome.reauthRequired(.noSession)) { await request.value }
        await expectEqual(AccessTokenOutcome.reauthRequired(.noSession)) { await coordinator.accessToken() }
        await expectNil { await store.session }
        await expectEqual("refresh-2") { await store.revokePending }
    }

    /// ⚠️ A LOGIN SINCE THE SIGN-OUT KEEPS ITS OWN SESSION: only this successor is wiped.
    func testALoginAfterTheSignOutIsNotWiped() async {
        let store = GatedWriteTokenStore(session: AuthFixtures.session(), applyGatedWrites: false)
        let coordinator = makeCoordinator(store)

        let request = Task { await coordinator.accessToken() }
        await waitUntil { await store.writeEntered }
        await coordinator.forget()
        await store.seed(AuthFixtures.session(refreshToken: "refresh-login"))
        await store.openGate()

        await expectEqual(AccessTokenOutcome.reauthRequired(.noSession)) { await request.value }
        await expectEqual("refresh-login") { await store.session?.refreshToken }
    }

    /// ⛔ AND A LOGIN THAT LANDS DURING THE UNDO ITSELF IS NOT WIPED EITHER. The store writes
    /// the login as soon as the undo starts touching it, which is after any snapshot the
    /// undo could have taken; only a clear that compares in the same step keeps it.
    func testALoginDuringTheUndoIsNotWiped() async {
        let store = GatedWriteTokenStore(
            session: AuthFixtures.session(),
            loginDuringUndo: AuthFixtures.session(refreshToken: "refresh-login")
        )
        let coordinator = makeCoordinator(store)

        let request = Task { await coordinator.accessToken() }
        await waitUntil { await store.writeEntered }
        await coordinator.forget()
        await store.openGate()

        await expectEqual(AccessTokenOutcome.reauthRequired(.noSession)) { await request.value }
        await expectEqual("refresh-login") { await store.session?.refreshToken }
        await expectEqual("refresh-2", "the successor still goes to the outbox") { await store.revokePending }
    }
}

/// A store whose first `write` parks until released, so a sign-out can be put inside it.
private actor GatedWriteTokenStore: TokenStore {
    private struct Failure: Error {}

    private(set) var session: PersistedSession?
    private(set) var revokePending: String?
    private(set) var writeEntered = false
    private var pending: String?
    private var isOpen = false
    private var waiter: CheckedContinuation<Void, Never>?
    private let failWrites: Bool
    /// False to drop the parked write, standing in for a newer write that landed after it.
    private let applyGatedWrites: Bool
    /// A login written the first time anything reads or clears the session once the gated
    /// write has finished: the undo, after it has started.
    private var loginDuringUndo: PersistedSession?
    private var gatedWriteDone = false

    init(
        session: PersistedSession?,
        failWrites: Bool = false,
        applyGatedWrites: Bool = true,
        loginDuringUndo: PersistedSession? = nil
    ) {
        self.session = session
        self.failWrites = failWrites
        self.applyGatedWrites = applyGatedWrites
        self.loginDuringUndo = loginDuringUndo
    }

    private func landLoginIfDue() {
        guard gatedWriteDone, let login = loginDuringUndo else { return }
        loginDuringUndo = nil
        session = login
    }

    func openGate() {
        isOpen = true
        waiter?.resume()
        waiter = nil
    }

    func seed(_ session: PersistedSession) {
        self.session = session
    }

    func read() async throws -> PersistedSession? {
        let snapshot = session
        landLoginIfDue()
        return snapshot
    }

    func write(_ session: PersistedSession) async throws {
        writeEntered = true
        if !isOpen {
            await withCheckedContinuation { waiter = $0 }
        }
        if failWrites {
            throw Failure()
        }
        if applyGatedWrites {
            self.session = session
        }
        gatedWriteDone = true
    }

    func clear() async throws {
        session = nil
        pending = nil
    }

    func clear(ifHolding refreshToken: String) async throws {
        landLoginIfDue()
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

    func pendingRevokeToken() async throws -> String? {
        revokePending
    }

    func markRevokePending(_ refreshToken: String) async throws {
        revokePending = refreshToken
    }

    func clearRevokePending() async throws {
        revokePending = nil
    }
}
