import ContractGateSupport
import DistrictModel
import XCTest

/// Live supervise's five recorded shapes, read the way the apps read them. The strict gate
/// (`ImplementedFixtures.supervise`) proves the keys; this proves the values a screen uses.
final class SuperviseContractTests: XCTestCase {
    func testTheListenSeatIsAJoinableCredential() throws {
        let seat = try StrictDecodeVerifier.verify(
            fixture: "district-call-monitor-token.json", as: CallMonitorResponse.self
        )
        XCTAssertTrue(seat.success)
        XCTAssertFalse(seat.token.isEmpty)
        XCTAssertTrue(seat.url.hasPrefix("wss://"))
    }

    /// ⚠️ THE COACH SEAT NAMES THE CALL'S ROOM, which is the assistant's (`call_`), never a
    /// team member's own softphone room (`direct_`): the route refuses that one with 409
    /// `call_has_no_receptionist`.
    func testTheCoachSeatJoinsTheCallsRoom() throws {
        let seat = try StrictDecodeVerifier.verify(
            fixture: "district-call-takeover.json", as: CallTakeoverResponse.self
        )
        XCTAssertTrue(seat.success)
        XCTAssertFalse(seat.token.isEmpty)
        XCTAssertTrue(seat.url.hasPrefix("wss://"))
        XCTAssertTrue(seat.roomName.hasPrefix("call_"))
    }

    func testTheWhisperAnswersOnlySuccess() throws {
        let answer = try StrictDecodeVerifier.verify(fixture: "district-call-whisper.json", as: SuccessResponse.self)
        XCTAssertTrue(answer.success)
    }

    func testAnAppliedReceiptQuotesTheAssistant() throws {
        let receipt = try XCTUnwrap(Self.receipt("telemetry-event-whisper-applied.json"))
        XCTAssertTrue(receipt.applied)
        XCTAssertFalse(receipt.firstWords.isEmpty)
        XCTAssertNil(receipt.reason)
    }

    /// ⚠️ A NOTE HELD BACK CARRIES ITS REASON, `transfer` OR `taken_over`, BOTH NAMED HERE.
    func testANotAppliedReceiptCarriesAReasonThisClientNames() throws {
        let receipt = try XCTUnwrap(Self.receipt("telemetry-event-whisper-not-applied.json"))
        XCTAssertFalse(receipt.applied)
        XCTAssertEqual(receipt.firstWords, "")
        XCTAssertEqual(receipt.reason, .takenOver)
        XCTAssertTrue(receipt.reason?.isTakenOver == true)
        XCTAssertEqual(WhisperReceipt.Reason(wire: "transfer"), .transfer)
    }

    private static func receipt(_ name: String) throws -> WhisperReceipt? {
        try StrictDecodeVerifier.verify(fixture: name, as: TelemetryEnvelope.self).whisperReceipt
    }
}
