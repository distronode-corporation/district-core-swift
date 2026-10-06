@testable import DistrictModel
import Foundation
import XCTest

/// The `transcript` v1 data and the three client ops. The frame-by-frame strict gate is
/// `TranscriptFrameTests`; this file pins what no single frame shows: the open
/// vocabularies, the version and call-id checks, the explicit nulls, the redaction and
/// the exact op frames.
final class TranscriptEventsTests: XCTestCase {
    private let epoch: Int64 = 1_791_297_000_000

    private func envelope(_ eventType: String, data: String, callId: String = "call_1") throws -> TelemetryEnvelope {
        try JSONDecoder().decode(TelemetryEnvelope.self, from: Data("""
        {"workspaceId":"ws_1","callId":"\(callId)","eventType":"\(eventType)","data":\(data),\
        "timestamp":"2026-10-06T14:30:06.420Z"}
        """.utf8))
    }

    private func encodeSorted(_ value: some Encodable) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try XCTUnwrap(String(data: encoder.encode(value), encoding: .utf8))
    }

    /// The §4.11 caller turn, with `speakerName` null as a caller line always has it.
    private var callerSegmentJSON: String {
        #"{"segmentId":"item_b2","index":1,"epoch":1791297000000,"seq":2,"rev":0,"speaker":"caller","#
            + #""speakerName":null,"text":"I'd like to book a cleaning on Thursday.","final":true,"#
            + #""interrupted":false,"language":"en","startedAt":"2026-10-06T14:30:07.200Z","#
            + #""endedAt":"2026-10-06T14:30:10.700Z","mood":"calm"}"#
    }

    // MARK: - Reading each event

    func testASegmentIsReadWithEveryField() throws {
        let read = try envelope(
            "transcript_segment",
            data: #"{"v":1,"callId":"call_1","segment":\#(callerSegmentJSON)}"#
        )
        .transcriptEvent

        guard case let .segment(data) = read
        else { return XCTFail("expected a segment, got \(String(describing: read))") }
        let segment = data.segment
        XCTAssertEqual(segment.segmentId, "item_b2")
        XCTAssertEqual(segment.index, 1)
        XCTAssertEqual(segment.epoch, epoch)
        XCTAssertEqual(segment.seq, 2)
        XCTAssertEqual(segment.rev, 0)
        XCTAssertEqual(segment.speaker, .caller)
        XCTAssertNil(segment.speakerName)
        XCTAssertEqual(segment.text, "I'd like to book a cleaning on Thursday.")
        XCTAssertTrue(segment.final)
        XCTAssertFalse(segment.interrupted)
        XCTAssertEqual(segment.language, "en")
        XCTAssertEqual(segment.startedAt, "2026-10-06T14:30:07.200Z")
        XCTAssertEqual(segment.endedAt, "2026-10-06T14:30:10.700Z")
        XCTAssertEqual(read?.callId, "call_1")
        XCTAssertEqual(read?.version, 1)
    }

    /// ⛔ AN UNKNOWN `data` KEY IS IGNORED, NOT A FAILURE: additive fields do not bump `v`.
    /// (`mood` above is one.) And the nullable keys re-encode as explicit nulls.
    func testUnknownKeysAreIgnoredAndNullsReencodeAsNulls() throws {
        let segment = try JSONDecoder().decode(TranscriptSegment.self, from: Data(callerSegmentJSON.utf8))
        let encoded = try encodeSorted(segment)

        XCTAssertFalse(encoded.contains("mood"))
        XCTAssertTrue(encoded.contains(#""speakerName":null"#), encoded)
        let interim = TranscriptSegment(
            segmentId: "s", index: 0, epoch: 1, seq: 1, rev: 0, speaker: .agent, speakerName: "Ava", text: "Hi",
            final: false, interrupted: false, language: nil, startedAt: "t", endedAt: nil
        )
        let interimText = try encodeSorted(interim)
        XCTAssertTrue(interimText.contains(#""endedAt":null"#), interimText)
        XCTAssertTrue(interimText.contains(#""language":null"#), interimText)
        XCTAssertEqual(try JSONDecoder().decode(TranscriptSegment.self, from: Data(interimText.utf8)), interim)
    }

    func testASnapshotIsReadWithItsNullBaseline() throws {
        let read = try envelope("transcript_snapshot", data: """
        {"v":1,"callId":"call_1","live":true,"complete":false,"epoch":null,"lastSeq":null,"segments":[],\
        "part":0,"more":false}
        """).transcriptEvent

        let expected = TranscriptSnapshotData(
            version: 1, callId: "call_1", live: true, complete: false, epoch: nil, lastSeq: nil, segments: [], part: 0,
            more: false
        )
        XCTAssertEqual(read, .snapshot(expected))
        XCTAssertEqual(
            try encodeSorted(expected),
            #"{"callId":"call_1","complete":false,"epoch":null,"lastSeq":null,"live":true,"more":false,"#
                + #""part":0,"segments":[],"v":1}"#
        )
    }

    func testAnEndIsReadWithEveryReason() throws {
        for (wire, reason) in [
            ("call_ended", TranscriptEndReason.callEnded), ("handed_off", .handedOff), ("agent_error", .agentError),
            ("parked", .other("parked")),
        ] {
            let data = #"{"v":1,"callId":"call_1","epoch":1,"seq":5,"lastIndex":null,"reason":"\#(wire)"}"#
            let read = try envelope("transcript_ended", data: data).transcriptEvent
            let expected = TranscriptEndedData(
                version: 1,
                callId: "call_1",
                epoch: 1,
                seq: 5,
                lastIndex: nil,
                reason: reason
            )
            XCTAssertEqual(read, .ended(expected))
            XCTAssertEqual(reason.wire, wire)
            XCTAssertEqual(
                try encodeSorted(expected),
                #"{"callId":"call_1","epoch":1,"lastIndex":null,"#
                    + #""reason":"\#(wire)","seq":5,"v":1}"#
            )
        }
    }

    /// ⚠️ THE WEBSITE'S RETRACTION CARRIES `seq: null` AND NO EPOCH; an epoch is read when
    /// sent and written back only then.
    func testARetractionIsReadWithAndWithoutAnEpoch() throws {
        let website = try envelope(
            "transcript_retracted",
            data: #"{"v":1,"callId":"call_1","all":true,"segmentIds":[],"reason":"erased","seq":null}"#
        ).transcriptEvent
        let fromWebsite = TranscriptRetractedData(
            version: 1, callId: "call_1", all: true, segmentIds: [], reason: .erased, seq: nil
        )
        XCTAssertEqual(website, .retracted(fromWebsite))
        XCTAssertEqual(
            try encodeSorted(fromWebsite),
            #"{"all":true,"callId":"call_1","reason":"erased","segmentIds":[],"seq":null,"v":1}"#
        )

        let agent = try envelope("transcript_retracted", data: """
        {"v":1,"callId":"call_1","all":false,"segmentIds":["item_a1"],"reason":"policy","seq":6,"epoch":7}
        """).transcriptEvent
        let fromAgent = TranscriptRetractedData(
            version: 1, callId: "call_1", all: false, segmentIds: ["item_a1"], reason: .policy, seq: 6, epoch: 7
        )
        XCTAssertEqual(agent, .retracted(fromAgent))
        XCTAssertTrue(try encodeSorted(fromAgent).contains(#""epoch":7"#))
        XCTAssertEqual(TranscriptRetractReason(wire: "court_order"), .other("court_order"))
        XCTAssertEqual(TranscriptRetractReason.other("court_order").wire, "court_order")
        XCTAssertEqual(TranscriptRetractReason.policy.wire, "policy")
    }

    func testAnErrorIsReadWithEveryCode() throws {
        let codes: [(String, TranscriptErrorCode)] = [
            ("bad_request", .badRequest), ("unsupported_version", .unsupportedVersion), ("not_live", .notLive),
            ("forbidden_role", .forbiddenRole), ("too_many_subscriptions", .tooManySubscriptions),
            ("rate_limited", .rateLimited), ("teapot", .other("teapot")),
        ]
        for (wire, code) in codes {
            let data = #"{"v":1,"callId":"call_1","op":"transcript.subscribe","code":"\#(wire)","retryAfterMs":250}"#
            let read = try envelope("transcript_error", data: data).transcriptEvent
            let expected = TranscriptErrorData(
                version: 1, callId: "call_1", op: "transcript.subscribe", code: code, retryAfterMs: 250
            )
            XCTAssertEqual(read, .error(expected), wire)
            XCTAssertEqual(code.wire, wire)
        }
        let anonymous = TranscriptErrorData(version: 1, callId: nil, op: nil, code: .badRequest, retryAfterMs: nil)
        XCTAssertEqual(
            try encodeSorted(anonymous),
            #"{"callId":null,"code":"bad_request","op":null,"retryAfterMs":null,"v":1}"#
        )
    }

    // MARK: - What is not read

    /// ⛔ AN ERROR THAT NAMES NO CALL IS READ WHATEVER THE ENVELOPE SAYS; any other event
    /// whose data names another call than its envelope is not read at all.
    func testTheCallIdsMustAgreeUnlessTheErrorNamesNone() throws {
        let mismatched = try envelope(
            "transcript_ended",
            data: #"{"v":1,"callId":"call_2","epoch":1,"seq":1,"lastIndex":null,"reason":"call_ended"}"#
        )
        XCTAssertNil(mismatched.transcriptEvent)

        let anonymous = try envelope(
            "transcript_error",
            data: #"{"v":1,"callId":null,"op":"socket.mode","code":"rate_limited","retryAfterMs":1000}"#,
            callId: ""
        )
        XCTAssertEqual(anonymous.transcriptEvent?.callId, nil)
        XCTAssertNotNil(anonymous.transcriptEvent)
    }

    /// ⛔ `version: 2` IS A BREAKING CHANGE THE SERVER SENDS ONLY TO A `version: 2` SUBSCRIBER, so one
    /// that arrives anyway is not read with v1's rules.
    func testAVersionOtherThanOneIsNotRead() throws {
        let frames = [
            (
                "transcript_snapshot",
                #"{"v":2,"callId":"call_1","live":true,"complete":true,"epoch":null,"#
                    + #""lastSeq":null,"segments":[],"part":0,"more":false}"#
            ),
            ("transcript_segment", #"{"v":2,"callId":"call_1","segment":\#(callerSegmentJSON)}"#),
            ("transcript_ended", #"{"v":2,"callId":"call_1","epoch":1,"seq":1,"lastIndex":null,"reason":"x"}"#),
            ("transcript_retracted", #"{"v":2,"callId":"call_1","all":true,"segmentIds":[],"reason":"x","seq":null}"#),
            ("transcript_error", #"{"v":2,"callId":"call_1","op":null,"code":"x","retryAfterMs":null}"#),
        ]
        for (type, data) in frames {
            let read = try envelope(type, data: data)
            XCTAssertTrue(read.eventType.isTranscript, type)
            XCTAssertNil(read.transcriptEvent, type)
        }
    }

    func testMalformedDataAndOtherEventsAreNotRead() throws {
        XCTAssertNil(try envelope("transcript_segment", data: #"{"v":1,"callId":"call_1"}"#).transcriptEvent)
        XCTAssertNil(try envelope("transcript_ended", data: #"[]"#).transcriptEvent)
        XCTAssertNil(try envelope("call_ended", data: #"{"status":"completed"}"#).transcriptEvent)
        XCTAssertNil(try envelope("transcript_paused", data: #"{"v":1,"callId":"call_1"}"#).transcriptEvent)
    }

    /// ⚠️ A NUMBER TOO LARGE FOR AN INTEGER IS CARRIED AS A DOUBLE, which then fails to
    /// read as an epoch: the frame is not read rather than read with a wrong number.
    func testAnEpochThatIsNotAnIntegerIsNotRead() throws {
        let data = #"{"v":1,"callId":"call_1","epoch":1.5,"seq":1,"lastIndex":null,"reason":"call_ended"}"#
        XCTAssertNil(try envelope("transcript_ended", data: data).transcriptEvent)
    }

    // MARK: - Speaker

    /// ⚠️ OPEN: `human_agent` and `supervisor` are reserved for a later v1.x, and any name
    /// this client does not know is kept as `other`.
    func testTheSpeakerIsAnOpenVocabulary() throws {
        for (wire, speaker) in [
            ("caller", TranscriptSpeaker.caller), ("agent", .agent), ("human_agent", .other("human_agent")),
            ("supervisor", .other("supervisor")),
        ] {
            let decoded = try JSONDecoder().decode(TranscriptSpeaker.self, from: Data("\"\(wire)\"".utf8))
            XCTAssertEqual(decoded, speaker)
            XCTAssertEqual(try encodeSorted(decoded), "\"\(wire)\"")
        }
    }

    // MARK: - Redaction

    /// ⛔ WHAT A CALLER SAID NEVER REACHES A STRING, through any of the ways XCTest, `dump`
    /// and interpolation print a value, nor through a container that holds a segment.
    func testTheTextIsLeftOutOfEverythingPrintable() throws {
        let segment = try JSONDecoder().decode(TranscriptSegment.self, from: Data(callerSegmentJSON.utf8))
        let snapshot = TranscriptSnapshotData(
            version: 1, callId: "call_1", live: true, complete: true, epoch: epoch, lastSeq: 2, segments: [segment],
            part: 0, more: false
        )
        let event = TranscriptEvent.snapshot(snapshot)
        var dumped = ""
        dump(event, to: &dumped)

        let printed = [
            String(describing: segment), String(reflecting: segment), "\(segment)", String(describing: snapshot),
            String(describing: event), String(reflecting: event), dumped,
        ]
        for shown in printed {
            XCTAssertFalse(shown.contains("cleaning"), shown)
            XCTAssertTrue(shown.contains("item_b2"), shown)
            XCTAssertTrue(shown.contains("<40 units>"), shown)
        }
    }

    // MARK: - The client ops

    /// ⛔ BYTE FOR BYTE THE CONTRACT'S §4.11 FRAMES, in its key order.
    func testTheOpsAreTheContractsFrames() {
        XCTAssertEqual(
            TranscriptClientOp.socketMode(broadcast: false).text,
            #"{"op":"socket.mode","v":1,"broadcast":false}"#
        )
        XCTAssertEqual(
            TranscriptClientOp.socketMode(broadcast: true).text,
            #"{"op":"socket.mode","v":1,"broadcast":true}"#
        )
        XCTAssertEqual(
            TranscriptClientOp.subscribe(callId: "call_1").text,
            #"{"op":"transcript.subscribe","v":1,"callId":"call_1"}"#
        )
        XCTAssertEqual(
            TranscriptClientOp.unsubscribe(callId: "call_1").text,
            #"{"op":"transcript.unsubscribe","v":1,"callId":"call_1"}"#
        )
    }

    func testEveryOpIsValidJSONWithTheExpectedValues() throws {
        let ops: [TranscriptClientOp] = [
            .subscribe(callId: "c-1_A"), .unsubscribe(callId: "c-1_A"), .socketMode(broadcast: false),
        ]
        for op in ops {
            let text = try XCTUnwrap(op.text)
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
            XCTAssertEqual(object["v"] as? Int, 1)
        }
    }

    /// ⛔ THE 1 KB LIMIT HOLDS BY CONSTRUCTION: the longest call id makes the longest op,
    /// and it is far below the limit. This is why no op is measured at run time.
    func testTheLongestOpIsFarBelowTheFrameLimit() throws {
        let longest = String(repeating: "x", count: 64)
        let frames = try [
            XCTUnwrap(TranscriptClientOp.subscribe(callId: longest).text),
            XCTUnwrap(TranscriptClientOp.unsubscribe(callId: longest).text),
            XCTUnwrap(TranscriptClientOp.socketMode(broadcast: false).text),
        ]
        for frame in frames {
            XCTAssertLessThanOrEqual(frame.utf8.count, 113, "the longest op, measured")
            XCTAssertLessThanOrEqual(frame.utf8.count, TranscriptClientOp.maxFrameBytes)
        }
    }

    /// ⛔ HOSTILE CALL IDS: nothing outside `[A-Za-z0-9_-]{1,64}` becomes a frame, so no
    /// quote, backslash or control character can reach the hand-written JSON.
    func testACallIdTheServerWouldRefuseMakesNoFrame() {
        let refused = [
            "", String(repeating: "x", count: 65), "call 1", #"call"1"#, #"a\b"#, "a\nb", "café", "a/b", "a.b",
            "\u{0}", #"x","op":"socket.mode"#,
        ]
        for callId in refused {
            XCTAssertFalse(TranscriptClientOp.isValidCallId(callId), callId)
            XCTAssertNil(TranscriptClientOp.subscribe(callId: callId).text, callId)
            XCTAssertNil(TranscriptClientOp.unsubscribe(callId: callId).text, callId)
        }
        for callId in ["a", "Z9", "call_1", "cm1x-ABC_def", String(repeating: "0", count: 64)] {
            XCTAssertTrue(TranscriptClientOp.isValidCallId(callId), callId)
        }
    }
}
