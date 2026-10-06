@testable import DistrictModel
import Foundation
import XCTest

/// The §4.12 clarifications of the `transcript` v1 contract that touch reading a frame: the
/// retraction's counter (Q2), the envelope `callId` of a call-less error (Q3) and the
/// echoed `op` (Q8). What they mean for the screen is `TranscriptReducer`'s.
final class TranscriptClarificationTests: XCTestCase {
    private func envelope(_ eventType: String, data: String, callId: String = "call_1") throws -> TelemetryEnvelope {
        try JSONDecoder().decode(TelemetryEnvelope.self, from: Data("""
        {"workspaceId":"ws_1","callId":"\(callId)","eventType":"\(eventType)","data":\(data),\
        "timestamp":"2026-10-06T14:30:06.420Z"}
        """.utf8))
    }

    /// Q2. An absent key reads as null, as everywhere in this module: a retraction from a
    /// server older than §4.12 still comes off the screen.
    func testARetractionWithoutAnEpochKeyIsStillRead() throws {
        let read = try envelope(
            "transcript_retracted",
            data: #"{"v":1,"callId":"call_1","all":false,"segmentIds":["item_a1"],"reason":"erased","seq":null}"#
        ).transcriptEvent
        XCTAssertEqual(
            read,
            .retracted(TranscriptRetractedData(
                version: 1, callId: "call_1", epoch: nil, seq: nil, all: false, segmentIds: ["item_a1"],
                reason: .erased
            ))
        )
    }

    /// Q3. A call-less error keeps all five envelope keys, with `callId` the string "",
    /// and is read; "" names no call, so a call's event under it is not.
    func testAnEmptyEnvelopeCallIdNamesNoCall() throws {
        let anonymous = try envelope(
            "transcript_error",
            data: #"{"v":1,"callId":null,"op":"socket.mode","code":"rate_limited","retryAfterMs":1000}"#,
            callId: ""
        )
        XCTAssertEqual(anonymous.callId, "")
        XCTAssertEqual(
            anonymous.transcriptEvent,
            .error(TranscriptErrorData(
                version: 1, callId: nil, op: "socket.mode", code: .rateLimited, retryAfterMs: 1000
            ))
        )

        let unnamed = try envelope(
            "transcript_ended",
            data: #"{"v":1,"callId":"call_1","epoch":1,"seq":1,"lastIndex":null,"reason":"call_ended"}"#,
            callId: ""
        )
        XCTAssertNil(unnamed.transcriptEvent)
    }

    /// Q8. `op` echoes the op string sent, exactly, or is null when the frame had none.
    func testTheOpIsEchoedExactlyOrNull() throws {
        let opless = try envelope(
            "transcript_error",
            data: #"{"v":1,"callId":null,"op":null,"code":"bad_request","retryAfterMs":null}"#,
            callId: ""
        )
        XCTAssertEqual(
            opless.transcriptEvent,
            .error(TranscriptErrorData(version: 1, callId: nil, op: nil, code: .badRequest, retryAfterMs: nil))
        )

        let echoed = try envelope(
            "transcript_error",
            data: #"{"v":1,"callId":null,"op":"transcript.Subscribe ","code":"bad_request","retryAfterMs":null}"#,
            callId: ""
        )
        guard case let .error(data)? = echoed.transcriptEvent else { return XCTFail("not read") }
        XCTAssertEqual(data.op, "transcript.Subscribe ", "kept as sent, case and space included")
    }
}
