import ContractGateSupport
import DistrictModel
import Foundation
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

    // MARK: - Whether the assistant is on the call

    /// ⛔ THE FEED, THE OVERVIEW AND THE DETAIL SAY THE SAME THING PER CALL. Three rows have
    /// the assistant on them; the two team-member softphone calls do not, and a screen offers
    /// those Listen only.
    func testEverySurfaceSaysWhichCallsHaveTheAssistantOnThem() throws {
        let expected = [
            "call_contract_answered": true, "call_contract_missed": true, "call_contract_outbound": true,
            "call_contract_outbound_unanswered": false, "call_contract_busy": false,
        ]
        let feed = try StrictDecodeVerifier.verify(fixture: "district-calls.json", as: [CallSummary].self)
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: feed.map { ($0.id, $0.hasReceptionist) }), expected)
        XCTAssertEqual(feed.map(\.receptionistOnCall), [true, true, true, false, false])

        let overview = try StrictDecodeVerifier.verify(fixture: "district-overview.json", as: OverviewResponse.self)
        XCTAssertEqual(
            Dictionary(uniqueKeysWithValues: overview.recentCalls.map { ($0.id, $0.hasReceptionist) }),
            expected
        )

        let detail = try StrictDecodeVerifier.verify(fixture: "district-call-detail.json", as: CallDetailResponse.self)
        XCTAssertEqual(detail.call?.receptionistOnCall, true)
    }

    /// ⚠️ A SERVER FROM BEFORE LIVE SUPERVISE OMITS THE KEY: it reads as `true` (the
    /// website's default), and stays absent on re-encode, which the strict gate requires.
    func testAnAbsentReceptionistFlagReadsAsTrueAndStaysAbsent() throws {
        let rows = try XCTUnwrap(
            JSONSerialization.jsonObject(with: ContractFixtures.read("district-calls.json")) as? [[String: Any]]
        )
        var row = try XCTUnwrap(rows.first)
        row.removeValue(forKey: "receptionistOnCall")
        let call = try JSONDecoder().decode(CallSummary.self, from: JSONSerialization.data(withJSONObject: row))
        XCTAssertNil(call.receptionistOnCall)
        XCTAssertTrue(call.hasReceptionist)
        let encoded = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(call)) as? [String: Any]
        )
        XCTAssertNil(encoded["receptionistOnCall"])
    }

    private static func receipt(_ name: String) throws -> WhisperReceipt? {
        try StrictDecodeVerifier.verify(fixture: name, as: TelemetryEnvelope.self).whisperReceipt
    }
}
