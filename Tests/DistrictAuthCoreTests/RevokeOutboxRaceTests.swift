@testable import DistrictAuthCore
import Foundation
import XCTest

/// Two revokes on the wire at once, sharing the store's one outbox slot.
///
/// ⛔ THE PROPERTY UNDER TEST IS "AN ACCEPTANCE CLEARS ONLY WHAT IT ACKNOWLEDGES". A
/// launch drain presents token A and waits; a sign-out meanwhile drains A itself,
/// records B and has B deferred. When the first answer for A arrives, an unconditional
/// clear wiped B's entry, and B stayed live on the server with nothing left to retry it.
final class RevokeOutboxRaceTests: XCTestCase {
    func testALateAcceptanceOfAnOlderTokenKeepsTheNewerOne() async {
        let store = SpyTokenStore(revokePending: "refresh-A")
        let client = HeldFirstRevokeClient(script: [.accepted, .deferred(.serverUnavailable)])
        let outbox = RevokeOutbox(store: store, client: client)

        let drain = Task { await outbox.drain() }
        await waitUntil { await client.held }
        await outbox.revoke("refresh-B")
        await expectEqual("refresh-B", "the deferred sign-out holds the slot") { await store.revokePending }

        await client.release()
        await drain.value

        await expectEqual("refresh-B", "and the older answer must not clear it") { await store.revokePending }
        await expectEqual(["refresh-A", "refresh-A", "refresh-B"]) { await client.presented }
    }

    /// ⚠️ THE ORDINARY CASE STILL CLEARS: the slot holds the token just accepted.
    func testAnAcceptanceOfTheHeldTokenClearsTheSlot() async {
        let store = SpyTokenStore(revokePending: "refresh-A")
        let outbox = RevokeOutbox(store: store, client: ScriptedRevokeClient())

        await outbox.drain()

        await expectNil { await store.revokePending }
    }
}

/// A ``RevokeClient`` whose first call parks until released and then accepts; later calls
/// answer from `script`.
private actor HeldFirstRevokeClient: RevokeClient {
    private(set) var presented: [String] = []
    private(set) var held = false
    private var script: [RevokeOutcome]
    private var waiter: CheckedContinuation<Void, Never>?

    init(script: [RevokeOutcome]) {
        self.script = script
    }

    func release() {
        waiter?.resume()
        waiter = nil
    }

    func revoke(refreshToken: String) async -> RevokeOutcome {
        presented.append(refreshToken)
        guard held else {
            held = true
            await withCheckedContinuation { waiter = $0 }
            return .accepted
        }
        return script.isEmpty ? .accepted : script.removeFirst()
    }
}
