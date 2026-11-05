import DistrictModel
import Foundation
import XCTest

/// The `whisper_applied` receipt, read off a telemetry envelope.
///
/// ⚠️ THE FRAMES ARE THE VOICE AGENT'S OWN (`district-voice-agent/src/__tests__/
/// test_live_transcript.py`, `publish_event("whisper_applied", …)`) until the website
/// records `telemetry-event-whisper-applied.json`.
final class WhisperReceiptTests: XCTestCase {
    private func envelope(_ data: String, type: String = "whisper_applied") throws -> TelemetryEnvelope {
        let json = #"{"workspaceId":"ws_1","callId":"call_1","eventType":""# + type
            + #"","data":"# + data + #","timestamp":"2026-11-03T14:00:00.000Z"}"#
        return try JSONDecoder().decode(TelemetryEnvelope.self, from: Data(json.utf8))
    }

    func testTheEventTypeIsKnownAndWorkspaceWide() throws {
        let event = try envelope(#"{"applied":true,"firstWords":"Of course"}"#)
        XCTAssertEqual(event.eventType, .whisperApplied)
        XCTAssertFalse(TelemetryEventType.whisperApplied.isTranscript)
        XCTAssertEqual(TelemetryEventType(wire: "whisper_applied"), .whisperApplied)
    }

    func testAnAppliedNoteCarriesItsFirstWords() throws {
        let receipt = try XCTUnwrap(envelope(#"{"applied":true,"firstWords":"Of course"}"#).whisperReceipt)
        XCTAssertEqual(receipt, WhisperReceipt(applied: true, firstWords: "Of course", reason: nil))
    }

    func testAnAppliedNoteWithNoWordsReadsAsEmpty() throws {
        let receipt = try XCTUnwrap(envelope(#"{"applied":true,"firstWords":""}"#).whisperReceipt)
        XCTAssertEqual(receipt.firstWords, "")
        XCTAssertEqual(try XCTUnwrap(envelope(#"{"applied":true}"#).whisperReceipt).firstWords, "")
    }

    func testAHeldBackNoteSaysWhy() throws {
        let transfer = try XCTUnwrap(envelope(#"{"applied":false,"reason":"transfer"}"#).whisperReceipt)
        XCTAssertEqual(transfer.reason, .transfer)
        XCTAssertFalse(transfer.applied)

        let held = try XCTUnwrap(envelope(#"{"applied":false,"reason":"taken_over"}"#).whisperReceipt)
        XCTAssertEqual(held.reason, .takenOver)
        XCTAssertEqual(held.reason?.isTakenOver, true)
    }

    /// ⚠️ AN UNKNOWN REASON IS KEPT BY NAME, and is not the taken-over sentence.
    func testAnUnknownReasonIsKeptByName() throws {
        let receipt = try XCTUnwrap(envelope(#"{"applied":false,"reason":"queued"}"#).whisperReceipt)
        XCTAssertEqual(receipt.reason, .unknown("queued"))
        XCTAssertEqual(receipt.reason?.wire, "queued")
        XCTAssertEqual(receipt.reason?.isTakenOver, false)
        for reason in [WhisperReceipt.Reason.transfer, .takenOver] {
            XCTAssertEqual(WhisperReceipt.Reason(wire: reason.wire), reason)
        }
    }

    /// ⛔ STRICT ABOUT `applied`: a guess would tell a supervisor their note was ignored.
    func testAMalformedAppliedIsNoReceipt() throws {
        XCTAssertNil(try envelope(#"{"firstWords":"Of course"}"#).whisperReceipt)
        XCTAssertNil(try envelope(#"{"applied":"true"}"#).whisperReceipt)
    }

    func testAnotherEventIsNoReceipt() throws {
        XCTAssertNil(try envelope(#"{"applied":true}"#, type: "tool_outcome").whisperReceipt)
    }

    /// ⛔ THE ASSISTANT'S WORDS TO A CUSTOMER STAY OUT OF LOGS.
    func testTheFirstWordsAreNeverPrinted() {
        let receipt = WhisperReceipt(applied: true, firstWords: "Your card ends 4242", reason: nil)
        XCTAssertFalse(String(describing: receipt).contains("4242"))
        XCTAssertFalse(String(reflecting: receipt).contains("4242"))
        XCTAssertFalse(Mirror(reflecting: receipt).children.contains { "\($0.value)".contains("4242") })
    }
}
