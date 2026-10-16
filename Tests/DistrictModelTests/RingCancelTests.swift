@testable import DistrictModel
import XCTest

/// The ring cancel's background push and its reason (3.0.1, `docs/ring_cancel_contract.md`).
final class RingCancelTests: XCTestCase {
    private func payload(_ overrides: [String: String] = [:]) -> [String: String] {
        ["type": "call_ring_cancelled", "workspaceId": "ws_1", "callId": "call_1", "reason": "answered"]
            .merging(overrides) { _, new in new }
    }

    func testEveryReasonReadsByItsWireName() {
        XCTAssertEqual(RingCancelReason.allCases.map(\.wire), ["answered", "timeout", "call_ended", "withdrawn"])
        for reason in RingCancelReason.allCases {
            XCTAssertEqual(RingCancelReason(wire: reason.wire), reason)
        }
    }

    /// ⛔ AN UNKNOWN OR ABSENT REASON IS `withdrawn`, NEVER A FAILURE.
    func testAnUnknownOrAbsentReasonIsWithdrawn() {
        XCTAssertEqual(RingCancelReason(wire: "parked"), .withdrawn)
        XCTAssertEqual(RingCancelReason(wire: "Answered"), .withdrawn)
        XCTAssertEqual(RingCancelReason(wire: nil), .withdrawn)
    }

    func testTheBackgroundPushParses() {
        XCTAssertEqual(
            RingCancel.parse(payload()),
            RingCancel(workspaceId: "ws_1", callId: "call_1", reason: .answered)
        )
        XCTAssertEqual(RingCancel.parse(payload(["reason": " call_ended "]))?.reason, .callEnded)
        XCTAssertEqual(RingCancel.parse(payload(["reason": ""]))?.reason, .withdrawn)
        var noReason = payload()
        noReason["reason"] = nil
        XCTAssertEqual(RingCancel.parse(noReason)?.reason, .withdrawn)
    }

    /// ⛔ ANOTHER TYPE, OR A MISSING ID, IS NOT A CANCEL. A cancel naming no call could only
    /// stop the wrong ring.
    func testAnotherTypeOrAMissingIdIsNotACancel() {
        XCTAssertNil(RingCancel.parse(payload(["type": "incoming_call"])))
        XCTAssertNil(RingCancel.parse(payload(["type": "call_ring_cancelled_v2"])))
        XCTAssertNil(RingCancel.parse(payload(["callId": "  "])))
        XCTAssertNil(RingCancel.parse(payload(["workspaceId": ""])))
        var noType = payload()
        noType["type"] = nil
        XCTAssertNil(RingCancel.parse(noType))
    }

    /// ⚠️ NEVER A TAP ROUTE: the parser people's taps go through still drops the type.
    func testThePushPayloadParserStillDropsIt() {
        XCTAssertNil(PushPayload.parse(payload()))
    }

    /// APNs puts the keys at the top level beside `aps`; non-string values are dropped.
    func testTheApnsUserInfoParses() {
        let userInfo: [AnyHashable: Any] = [
            "aps": ["content-available": 1],
            "type": "call_ring_cancelled",
            "workspaceId": "ws_1",
            "callId": "call_1",
            "reason": "timeout",
            1: "not a key",
        ]
        XCTAssertEqual(
            RingCancel.parse(userInfo: userInfo),
            RingCancel(workspaceId: "ws_1", callId: "call_1", reason: .timeout)
        )
        XCTAssertNil(RingCancel.parse(userInfo: ["type": "call_ring_cancelled", "workspaceId": "ws_1", "callId": 7]))
    }

    func testTheEnvelopeReadsItsReason() {
        let envelope = TelemetryEnvelope(
            workspaceId: "ws_1",
            callId: "call_1",
            eventType: .callRingCancelled,
            data: .object(["callId": .string("call_1"), "reason": .string("call_ended")]),
            timestamp: "t"
        )
        XCTAssertEqual(envelope.ringCancelReason, .callEnded)
        let bare = TelemetryEnvelope(
            workspaceId: "ws_1",
            callId: "call_1",
            eventType: .callRingCancelled,
            data: .object([:]),
            timestamp: "t"
        )
        XCTAssertEqual(bare.ringCancelReason, .withdrawn)
    }
}
