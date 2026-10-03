@testable import DistrictLive
import DistrictModel
import Foundation
import XCTest

/// When this Mac rings, and every way a ring ends.
final class DesktopRingGateTests: XCTestCase {
    private let t0: Int64 = 1_790_433_000_000

    private func event(
        _ type: TelemetryEventType,
        call: String = "call_1",
        workspace: String = "ws_1",
        data: WireJSON = .object([:])
    ) -> TelemetryEnvelope {
        TelemetryEnvelope(workspaceId: workspace, callId: call, eventType: type, data: data, timestamp: "t")
    }

    private func ringing(call: String = "call_1", users: [String] = ["user_me"]) -> TelemetryEnvelope {
        event(
            .callRinging,
            call: call,
            data: .object(["callId": .string(call), "userIds": .array(users.map { .string($0) })])
        )
    }

    private func updated(_ status: String?, call: String = "call_1") -> TelemetryEnvelope {
        event(.callUpdated, call: call, data: .object(status.map { ["status": .string($0)] } ?? [:]))
    }

    private func ringingGate() -> DesktopRingGate {
        var gate = DesktopRingGate(userId: "user_me")
        _ = gate.handle(ringing(), atMilliseconds: t0)
        return gate
    }

    func testTheTimeoutIsTheServersLongestHold() {
        XCTAssertEqual(DesktopRingGate.ringTimeoutMilliseconds, 30000)
        XCTAssertEqual(DesktopRingGate.answerableStatuses, ["in-progress", "ringing"])
    }

    func testARingForThisMemberStartsAndArmsTheTimeout() {
        var gate = DesktopRingGate(userId: "user_me")
        XCTAssertEqual(
            gate.handle(ringing(users: ["user_other", "user_me"]), atMilliseconds: t0),
            [.startRinging(workspaceId: "ws_1", callId: "call_1"), .scheduleTimeout(afterMilliseconds: 30000)]
        )
        XCTAssertEqual(gate.ring, DesktopRing(workspaceId: "ws_1", callId: "call_1", startedAtMilliseconds: t0))
        XCTAssertEqual(gate.userId, "user_me")
    }

    /// ⛔ A RING FOR A COLLEAGUE, OR ONE NAMING NOBODY READABLY, DOES NOT RING HERE.
    func testARingForSomebodyElseOrForNobodyIsIgnored() {
        var gate = DesktopRingGate(userId: "user_me")
        XCTAssertEqual(gate.handle(ringing(users: ["user_other"]), atMilliseconds: t0), [])
        XCTAssertEqual(gate.handle(ringing(users: []), atMilliseconds: t0), [])
        XCTAssertEqual(
            gate.handle(event(.callRinging, data: .object(["userIds": .string("user_me")])), atMilliseconds: t0),
            []
        )
        XCTAssertNil(gate.ring)
    }

    /// ⛔ ONE RING AT A TIME: a second call, or the same one again, changes nothing.
    func testASecondRingWhileRingingIsIgnored() {
        var gate = ringingGate()
        XCTAssertEqual(gate.handle(ringing(call: "call_2"), atMilliseconds: t0 + 1000), [])
        XCTAssertEqual(gate.handle(ringing(), atMilliseconds: t0 + 1000), [])
        XCTAssertEqual(gate.ring?.callId, "call_1")
        XCTAssertEqual(gate.ring?.startedAtMilliseconds, t0)
    }

    func testCallEndedStopsTheRing() {
        var gate = ringingGate()
        XCTAssertEqual(
            gate.handle(event(.callEnded), atMilliseconds: t0 + 5000),
            [.stopRinging(workspaceId: "ws_1", callId: "call_1", reason: .callEnded)]
        )
        XCTAssertNil(gate.ring)
    }

    /// ⛔ `in-progress` IS ANSWERABLE: a receptionist handing a caller over keeps the call
    /// `in-progress`, and its transcript updates must not end the ring.
    func testAnUpdateEndsTheRingOnlyWhenTheCallCanNoLongerBeAnswered() {
        var gate = ringingGate()
        XCTAssertEqual(gate.handle(updated("in-progress"), atMilliseconds: t0 + 1000), [])
        XCTAssertEqual(gate.handle(updated("ringing"), atMilliseconds: t0 + 1000), [])
        XCTAssertEqual(gate.handle(updated(nil), atMilliseconds: t0 + 1000), [])
        XCTAssertEqual(
            gate.handle(updated("completed"), atMilliseconds: t0 + 2000),
            [.stopRinging(workspaceId: "ws_1", callId: "call_1", reason: .noLongerAnswerable(status: "completed"))]
        )
    }

    func testEventsForAnotherCallOrWorkspaceDoNotEndTheRing() {
        var gate = ringingGate()
        XCTAssertEqual(gate.handle(event(.callEnded, call: "call_2"), atMilliseconds: t0), [])
        XCTAssertEqual(gate.handle(event(.callEnded, workspace: "ws_2"), atMilliseconds: t0), [])
        XCTAssertEqual(gate.handle(updated("completed", call: "call_2"), atMilliseconds: t0), [])
        XCTAssertNotNil(gate.ring)
    }

    func testAnEndWithNothingRingingDoesNothing() {
        var gate = DesktopRingGate(userId: "user_me")
        XCTAssertEqual(gate.handle(event(.callEnded), atMilliseconds: t0), [])
        XCTAssertEqual(gate.expire(atMilliseconds: t0 + 60000), [])
        XCTAssertEqual(gate.clear(), [])
        XCTAssertFalse(gate.ringHasExpired(atMilliseconds: t0 + 60000))
    }

    func testOtherEventTypesNeverRingOrStop() {
        var gate = ringingGate()
        for type in [
            TelemetryEventType.callStarted,
            .toolOutcome,
            .messageReceived,
            .messageSent,
            .unknown("call_parked"),
        ] {
            XCTAssertEqual(
                gate.handle(event(type, data: .object(["status": .string("completed")])), atMilliseconds: t0),
                [],
                "\(type)"
            )
        }
        XCTAssertNotNil(gate.ring)
    }

    /// ⛔ THE TIMEOUT RE-CHECKS THE FACT: not one millisecond early.
    func testTheRingTimesOutOnTheBoundAndNotBefore() {
        var gate = ringingGate()
        XCTAssertFalse(gate.ringHasExpired(atMilliseconds: t0 + 29999))
        XCTAssertEqual(gate.expire(atMilliseconds: t0 + 29999), [])
        XCTAssertTrue(gate.ringHasExpired(atMilliseconds: t0 + 30000))
        XCTAssertEqual(
            gate.expire(atMilliseconds: t0 + 30000),
            [.stopRinging(workspaceId: "ws_1", callId: "call_1", reason: .timedOut)]
        )
        XCTAssertNil(gate.ring)
    }

    func testClearSilencesTheRing() {
        var gate = ringingGate()
        XCTAssertEqual(gate.clear(), [.stopRinging(workspaceId: "ws_1", callId: "call_1", reason: .cleared)])
        XCTAssertNil(gate.ring)
        // A new ring can start once the last one is over.
        XCTAssertEqual(gate.handle(ringing(call: "call_2"), atMilliseconds: t0).count, 2)
    }
}
