@testable import DistrictLive
import DistrictModel
import Foundation
import XCTest

/// This Mac's presence: registered at once, renewed every five minutes, retried a
/// minute after a failure, and withdrawn on sign-out in the order it was asked for.
final class PresenceControllerTests: XCTestCase {
    private let clock = ManualClock()
    private let api = FakePresenceAPI()

    private func makeController() -> PresenceController {
        PresenceController(api: api, clock: clock, token: "install-nonce-1")
    }

    /// ⛔ HALF THE SERVER'S TEN-MINUTE FRESHNESS WINDOW, so one late renewal does not
    /// let a Mac that is awake stop ringing.
    func testTheTimingIsInsideTheServersWindow() {
        XCTAssertEqual(PresenceController.heartbeatMilliseconds, 300_000)
        XCTAssertEqual(PresenceController.retryMilliseconds, 60000)
    }

    func testItRegistersAtOnceAndRenewsEveryFiveMinutes() async {
        let controller = makeController()
        let initial = await controller.status
        XCTAssertEqual(initial, .off)

        await controller.start()
        await controller.start()
        let registering = await controller.status
        XCTAssertEqual(registering, .registering)
        api.registerResults.provide(.success(()))
        await waitUntil { await controller.status == .registered && clock.pendingSleepers == 1 }
        XCTAssertEqual(api.calls, [.register("install-nonce-1")], "a second start does not start a second loop")

        clock.advance(by: PresenceController.heartbeatMilliseconds - 1)
        XCTAssertEqual(api.calls.count, 1)
        clock.advance(by: 1)
        await waitUntil { api.calls.count == 2 }
        api.registerResults.provide(.success(()))
        await waitUntil { clock.pendingSleepers == 1 }
        await controller.stop()
    }

    func testAFailedRegistrationIsReportedAndRetriedAfterAMinute() async {
        let controller = makeController()
        await controller.start()
        api.registerResults.provide(.failure(.transport("offline")))
        await waitUntil { await controller.status == .failed(.transport("offline")) && clock.pendingSleepers == 1 }

        clock.advance(by: PresenceController.retryMilliseconds)
        await waitUntil { api.calls.count == 2 }
        api.registerResults.provide(.success(()))
        await waitUntil { await controller.status == .registered }
        await controller.stop()
    }

    /// ⛔ STOP SENDS NOTHING: an unregister would take the Mac's APNs alert row too.
    func testStopRenewsNoMoreAndSendsNothing() async {
        let controller = makeController()
        await controller.start()
        api.registerResults.provide(.success(()))
        await waitUntil { clock.pendingSleepers == 1 }

        await controller.stop()
        let status = await controller.status
        XCTAssertEqual(status, .off)
        await waitUntil { clock.pendingSleepers == 0 }
        clock.advance(by: PresenceController.heartbeatMilliseconds * 3)
        await Task.yield()
        XCTAssertEqual(api.calls, [.register("install-nonce-1")])
    }

    /// ⛔ A REGISTER ON ITS WAY WHEN THE USER SIGNS OUT FINISHES FIRST, AND ITS RESULT
    /// IS DISCARDED; THE UNREGISTER IS SENT AFTER IT.
    func testSignOutWaitsForTheRegisterInFlightThenUnregisters() async {
        let controller = makeController()
        await controller.start()
        await waitUntil { api.registerResults.waiters == 1 }

        let signingOut = Task { await controller.signOut() }
        await waitUntil { await controller.status == .off }
        XCTAssertEqual(api.calls, [.register("install-nonce-1")], "the unregister waits its turn")

        api.registerResults.provide(.failure(.transport("late")))
        await waitUntil { api.calls.count == 2 }
        api.unregisterResults.provide(.success(()))
        let result = await signingOut.value

        XCTAssertNotNil(try? result.get())
        XCTAssertEqual(api.calls, [.register("install-nonce-1"), .unregister])
        let status = await controller.status
        XCTAssertEqual(status, .off, "the late register's failure is not reported after sign-out")
    }

    /// ⛔ A REGISTER WHOSE TURN COMES AFTER A STOP IS NEVER SENT, so it cannot reach
    /// the server behind the unregister and leave a signed-out Mac ringable.
    func testARegisterQueuedBehindAnUnregisterIsDroppedIfStoppedMeanwhile() async {
        let controller = makeController()
        await controller.start()
        api.registerResults.provide(.success(()))
        await waitUntil { clock.pendingSleepers == 1 }

        let signingOut = Task { await controller.signOut() }
        await waitUntil { api.unregisterResults.waiters == 1 }
        await controller.start()
        await controller.stop()
        api.unregisterResults.provide(.failure(.http(status: 500, message: nil)))

        let result = await signingOut.value
        XCTAssertEqual(result.failureOnly, .http(status: 500, message: nil))
        for _ in 0 ..< 100 {
            await Task.yield()
        }
        XCTAssertEqual(api.calls, [.register("install-nonce-1"), .unregister])
    }
}
