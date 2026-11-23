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

    /// ⛔ THE MARKER CLEAR IS ONE MORE SUSPENSION a sign-out can land inside: the
    /// write resolved and the first fence passed, and without a second check the
    /// successor's access token was cached and answered .available for a session
    /// that had just been signed out, with the successor left live and unowned.
    /// The clear is fenced again, so the sign-out's answer arrives through
    /// ``discard(_:)``, which revokes the successor (CodeRabbit, 2026-11-23).
    func testASignOutInsideTheMarkerClearIsAnsweredByDiscardNotAToken() async {
        let store = GatedWriteTokenStore(session: AuthFixtures.session())
        await store.openGate()
        await store.closeClearGate()
        let coordinator = makeCoordinator(store)

        let request = Task { await coordinator.accessToken() }
        await waitUntil { await store.clearEntered }
        await coordinator.forget()
        await store.openClearGate()

        await expectEqual(AccessTokenOutcome.reauthRequired(.noSession)) { await request.value }
        await expectEqual(AccessTokenOutcome.reauthRequired(.noSession), "nor is it cached") {
            await coordinator.accessToken()
        }
        await expectEqual("refresh-2", "the live successor goes to the outbox") { await store.revokePending }
    }

    /// ⚠️ A LOGIN SINCE THE SIGN-OUT KEEPS ITS OWN SESSION: only this successor is
    /// wiped. The login goes through ``TokenRefreshCoordinator/adopt(_:deviceId:)``, so
    /// its write queues behind the abandoned one and the undo's one-step clear must
    /// compare against what the store holds THEN, which is the login's session.
    func testALoginAfterTheSignOutIsNotWiped() async {
        let store = GatedWriteTokenStore(session: AuthFixtures.session())
        let coordinator = makeCoordinator(store)

        let request = Task { await coordinator.accessToken() }
        await waitUntil { await store.writeEntered }
        await coordinator.forget()
        let login = Task { await coordinator.adopt(AuthFixtures.tokens(index: 9), deviceId: "device-abc") }
        await store.openGate()
        _ = await login.value

        await expectEqual(AccessTokenOutcome.retryLater(.sessionReplaced)) { await request.value }
        await expectEqual("refresh-9", "the real login keeps its own session") { await store.session?.refreshToken }
        await expectEqual("refresh-2", "and only the abandoned successor is revoked") { await store.revokePending }
    }

    /// ⛔ A SIGN-OUT LANDING INSIDE THE LOGIN'S WRITE ENDS THE LOGIN. The adoption's
    /// write can land after the wipe, exactly a rotation's can, and it is undone the
    /// same way: cleared if the store still holds this successor, revoked through
    /// the outbox, nothing cached.
    func testASignOutDuringTheLoginWriteUndoesTheAdoption() async {
        let store = GatedWriteTokenStore(session: AuthFixtures.session())
        let coordinator = TokenRefreshCoordinator(
            store: store,
            refreshClient: NeverRefreshClient(),
            now: { AuthFixtures.now }
        )

        let login = Task { await coordinator.adopt(AuthFixtures.tokens(index: 9), deviceId: "device-abc") }
        await waitUntil { await store.writeEntered }
        await coordinator.forget()
        await store.openGate()
        _ = await login.value

        await expectNil("the login's write, landed after the wipe, is undone") { await store.session }
        await expectEqual("refresh-9", "and its live token goes to the outbox") { await store.revokePending }
        await expectEqual(AccessTokenOutcome.reauthRequired(.noSession)) { await coordinator.accessToken() }
    }

    /// ⛔ A SIGN-OUT LANDING INSIDE THE RESCUE WRITE ENDS THE RESCUE. The rescue
    /// belongs to the session that minted it, and the retried write can land after
    /// the wipe: without the fence after it, the old user's session was back on
    /// disk with the sign-out already answered.
    func testASignOutDuringTheRescueWriteUndoesIt() async {
        let store = GatedWriteTokenStore(session: AuthFixtures.session())
        await store.failNextWrites(1)
        let refresh = ScriptedRefreshClient(script: [.success(AuthFixtures.tokens(index: 2, accessLifetime: 0))])
        let coordinator = TokenRefreshCoordinator(store: store, refreshClient: refresh, now: { AuthFixtures.now })

        // The rotation's write is refused, so its successor survives only as the rescue.
        let first = Task { await coordinator.accessToken() }
        await waitUntil { await store.writeCount == 1 }
        await store.openGate()
        await expectEqual(AccessTokenOutcome.available("access-2")) { await first.value }

        // The next acquisition retries the rescue's write, and the sign-out lands inside it.
        await store.closeGate()
        let rescue = Task { await coordinator.accessToken() }
        await waitUntil { await store.writeCount == 2 }
        await coordinator.forget()
        await store.openGate()

        await expectEqual(AccessTokenOutcome.reauthRequired(.noSession)) { await rescue.value }
        await expectNil("the rescued successor the wipe missed is cleared") { await store.session }
        await expectEqual("refresh-2", "and its live token goes to the outbox") { await store.revokePending }
    }

    /// ⛔ AND THE SAME FOR THE QUIT'S OWN RETRY OF THAT WRITE.
    /// ``TokenRefreshCoordinator/finishRefreshInFlight()`` repersists the rescue
    /// too, and a sign-out landing inside that write must not leave the rescued
    /// session on disk with its token nowhere.
    func testASignOutDuringTheQuitsRescueWriteUndoesIt() async {
        let store = GatedWriteTokenStore(session: AuthFixtures.session())
        await store.failNextWrites(1)
        let refresh = ScriptedRefreshClient(script: [.success(AuthFixtures.tokens(index: 2, accessLifetime: 0))])
        let coordinator = TokenRefreshCoordinator(store: store, refreshClient: refresh, now: { AuthFixtures.now })

        // The rotation's write is refused, so its successor survives only as the rescue.
        let first = Task { await coordinator.accessToken() }
        await waitUntil { await store.writeCount == 1 }
        await store.openGate()
        await expectEqual(AccessTokenOutcome.available("access-2")) { await first.value }

        // The quit retries the rescue's write, and the sign-out lands inside it.
        await store.closeGate()
        let quit = Task { await coordinator.finishRefreshInFlight() }
        await waitUntil { await store.writeCount == 2 }
        await coordinator.forget()
        await store.openGate()
        _ = await quit.value

        await expectNil("the rescued successor the wipe missed is cleared") { await store.session }
        await expectEqual("refresh-2", "and its live token goes to the outbox") { await store.revokePending }
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

        await expectEqual(AccessTokenOutcome.retryLater(.sessionReplaced)) { await request.value }
        await expectEqual("refresh-login") { await store.session?.refreshToken }
        await expectEqual("refresh-2", "the successor still goes to the outbox") { await store.revokePending }
    }
}

/// A store whose writes park until released, so a sign-out or a login can be put inside one.
private actor GatedWriteTokenStore: TokenStore {
    private struct Failure: Error {}

    private(set) var session: PersistedSession?
    private(set) var revokePending: String?
    private(set) var writeEntered = false
    /// Every write this store has taken, gated or not, so a test can await the
    /// SECOND write rather than a sticky "some write happened" flag.
    private(set) var writeCount = 0
    private var pending: String?
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    /// The marker clear's own gate: open by default, so only a test that names
    /// it parks inside the clear (CodeRabbit, 2026-11-23).
    private(set) var clearEntered = false
    private var clearIsOpen = true
    private var clearWaiters: [CheckedContinuation<Void, Never>] = []
    private let failWrites: Bool
    /// Number of remaining `write` calls that should throw; `failWrites` is the
    /// "always" form.
    private var failingWrites = 0
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
        let resuming = waiters
        waiters = []
        for waiter in resuming {
            waiter.resume()
        }
    }

    func closeGate() {
        isOpen = false
    }

    func failNextWrites(_ count: Int) {
        failingWrites = count
    }

    func read() async throws -> PersistedSession? {
        let snapshot = session
        landLoginIfDue()
        return snapshot
    }

    func write(_ session: PersistedSession) async throws {
        writeEntered = true
        writeCount += 1
        if !isOpen {
            await withCheckedContinuation { waiters.append($0) }
        }
        if failWrites {
            throw Failure()
        }
        if failingWrites > 0 {
            failingWrites -= 1
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
        clearEntered = true
        if !clearIsOpen {
            await withCheckedContinuation { clearWaiters.append($0) }
        }
        pending = nil
    }

    func closeClearGate() {
        clearIsOpen = false
    }

    func openClearGate() {
        clearIsOpen = true
        let resuming = clearWaiters
        clearWaiters = []
        for waiter in resuming {
            waiter.resume()
        }
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

    func clearRevokePending(ifHolding refreshToken: String) async throws {
        guard revokePending == refreshToken else { return }
        revokePending = nil
    }
}
