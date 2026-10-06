import ContractGateSupport
import DistrictModel
import Foundation
import XCTest

/// The five `transcript_*` events, each frame in `Tests/TranscriptFrames/` through the
/// strict gate (no unlisted null, decode, re-encode, equal key sets at every level) and
/// read as the event its type names.
///
/// ⛔ THE FRAMES ARE HAND-WRITTEN UNTIL THE SERVICE SHIPS ITS OWN, and this file is written
/// so that swapping them in is a file copy: it asserts only what holds for any frame the
/// contract allows (see `Tests/TranscriptFrames/README.md`), never a value typed by hand.
/// The values are pinned by `TranscriptEventsTests` and the reducer's tests instead.
///
/// ⚠️ SIX FILES, AN EXACT COUNT AND AN EXPLICIT MAP, the desktop suite's two guards, so a
/// frame that vanished or one nobody verifies is red rather than skipped.
final class TranscriptFrameTests: XCTestCase {
    static let expectedFrameCount = 6

    /// Each frame and the event type it must carry.
    private static let frames: [String: TelemetryEventType] = [
        "telemetry-event-transcript-ended.json": .transcriptEnded,
        "telemetry-event-transcript-error.json": .transcriptError,
        "telemetry-event-transcript-retracted.json": .transcriptRetracted,
        "telemetry-event-transcript-segment-interim.json": .transcriptSegment,
        "telemetry-event-transcript-segment.json": .transcriptSegment,
        "telemetry-event-transcript-snapshot.json": .transcriptSnapshot,
    ]

    /// `<repo>/Tests/TranscriptFrames`, walked up from this file (this file, its directory,
    /// then `Tests`, which is kept).
    private static var directory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("TranscriptFrames", isDirectory: true)
    }

    private static func read(_ name: String) throws -> Data {
        try Data(contentsOf: directory.appendingPathComponent(name))
    }

    /// The keys the contract allows to be null in each event's data, as strict-gate paths.
    ///
    /// ⚠️ A SNAPSHOT'S SEGMENTS ARE LISTED BY INDEX, so the paths are derived from the frame
    /// itself: a server frame with more segments than the hand-written one needs no edit.
    private static func allowedNulls(_ name: String, json: Data) throws -> Set<String> {
        let segmentKeys = ["speakerName", "language", "endedAt"]
        switch frames[name] {
        case .transcriptSegment:
            return Set(segmentKeys.map { "$.data.segment.\($0)" })
        case .transcriptSnapshot:
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: json) as? [String: Any])
            let data = try XCTUnwrap(object["data"] as? [String: Any])
            let count = try XCTUnwrap(data["segments"] as? [Any]).count
            let segments = (0 ..< count).flatMap { index in segmentKeys.map { "$.data.segments[\(index)].\($0)" } }
            return Set(segments + ["$.data.epoch", "$.data.lastSeq"])
        case .transcriptEnded:
            return ["$.data.lastIndex"]
        case .transcriptRetracted:
            return ["$.data.epoch", "$.data.seq"]
        case .transcriptError:
            return ["$.data.callId", "$.data.op", "$.data.retryAfterMs"]
        default:
            return []
        }
    }

    private static func gate(_ name: String) throws -> TelemetryEnvelope {
        let json = try read(name)
        return try StrictDecodeVerifier.verify(
            name: name,
            json: json,
            as: TelemetryEnvelope.self,
            allowingExplicitNulls: allowedNulls(name, json: json)
        )
    }

    private static func gateData(_ name: String, as type: (some Codable).Type) throws {
        let json = try read(name)
        // ⚠️ THROUGH `WireJSON`, NOT `JSONSerialization`, which can turn a boolean into a
        // number on Linux's Foundation.
        let data = try JSONEncoder().encode(JSONDecoder().decode(TelemetryEnvelope.self, from: json).data)
        let allowed = try allowedNulls(name, json: json).map { $0.replacingOccurrences(of: "$.data", with: "$") }
        try StrictDecodeVerifier.verify(name: name, json: data, as: type, allowingExplicitNulls: Set(allowed))
    }

    // MARK: - The guards

    func testTheFrameDirectoryHoldsExactlySixFrames() throws {
        let names = try FileManager.default.contentsOfDirectory(atPath: Self.directory.path)
            .filter { $0.hasSuffix(".json") }
            .sorted()
        XCTAssertEqual(names.count, Self.expectedFrameCount, "on disk: \(names.joined(separator: ", "))")
        XCTAssertEqual(Set(names), Set(Self.frames.keys))
    }

    // MARK: - Every frame

    /// ⛔ THE ENVELOPE IS UNCHANGED: five keys, everything new inside `data`.
    func testEveryFramePassesTheStrictGateAsAnEnvelope() throws {
        for (name, type) in Self.frames {
            let envelope = try Self.gate(name)
            XCTAssertEqual(envelope.eventType, type, name)
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Self.read(name)) as? [String: Any])
            XCTAssertEqual(Set(object.keys), ["workspaceId", "callId", "eventType", "data", "timestamp"], name)
        }
    }

    /// The typed data, through the strict gate too: every key the server sends is modelled,
    /// and every key the model writes is one the server sends.
    func testEveryFramesDataPassesTheStrictGateAsItsType() throws {
        for (name, type) in Self.frames {
            switch type {
            case .transcriptSnapshot: try Self.gateData(name, as: TranscriptSnapshotData.self)
            case .transcriptSegment: try Self.gateData(name, as: TranscriptSegmentData.self)
            case .transcriptEnded: try Self.gateData(name, as: TranscriptEndedData.self)
            case .transcriptRetracted: try Self.gateData(name, as: TranscriptRetractedData.self)
            default: try Self.gateData(name, as: TranscriptErrorData.self)
            }
        }
    }

    func testEveryFrameIsReadAsTheEventItsTypeNames() throws {
        for (name, type) in Self.frames {
            let envelope = try Self.gate(name)
            let event = try XCTUnwrap(envelope.transcriptEvent, name)
            XCTAssertEqual(event.version, TranscriptClientOp.version, name)
            XCTAssertEqual(event.callId, envelope.callId, name)
            switch (type, event) {
            case (.transcriptSnapshot, .snapshot), (.transcriptSegment, .segment), (.transcriptEnded, .ended),
                 (.transcriptRetracted, .retracted), (.transcriptError, .error):
                break
            default:
                XCTFail("\(name) read as \(event)")
            }
        }
    }

    /// The contract's invariants on a segment, whatever frame carries it.
    func testEverySegmentKeepsTheContractsInvariants() throws {
        var segments: [TranscriptSegment] = []
        for name in Self.frames.keys {
            switch try Self.gate(name).transcriptEvent {
            case let .segment(data)?: segments.append(data.segment)
            case let .snapshot(data)?: segments += data.segments
            default: break
            }
        }
        XCTAssertFalse(segments.isEmpty)
        for segment in segments {
            XCTAssertLessThanOrEqual(segment.segmentId.count, 64)
            XCTAssertTrue((1 ... 2000).contains(segment.text.utf16.count))
            XCTAssertGreaterThanOrEqual(segment.seq, 1)
            XCTAssertGreaterThanOrEqual(segment.rev, 0)
            XCTAssertGreaterThanOrEqual(segment.index, 0)
            if segment.speaker == .caller {
                XCTAssertNil(segment.speakerName, "a caller line never repeats the caller's name")
                XCTAssertFalse(segment.interrupted)
            }
            if !segment.final {
                XCTAssertNil(segment.endedAt, "an interim segment has not ended")
            }
        }
        XCTAssertTrue(segments.contains { !$0.final }, "the interim frame carries an interim segment")
    }

    /// The §4.12 clarifications, whatever frame carries them.
    func testEveryFrameKeepsTheClarifiedInvariants() throws {
        for name in Self.frames.keys {
            let envelope = try Self.gate(name)
            switch envelope.transcriptEvent {
            case let .snapshot(data)?:
                // Q4 and Q7: a mark for one epoch, and never an empty opening snapshot.
                XCTAssertEqual(data.epoch == nil, data.lastSeq == nil, name)
                XCTAssertNotEqual(data.lastSeq, 0, name)
                XCTAssertTrue(data.segments.allSatisfy { $0.epoch <= data.epoch ?? $0.epoch }, name)
            case let .retracted(data)?:
                // Q2: `epoch` whenever `seq`.
                XCTAssertEqual(data.epoch == nil, data.seq == nil, name)
            case let .error(data)?:
                // Q3: a call-less error keeps a string envelope `callId`, "".
                XCTAssertEqual(envelope.callId, data.callId ?? "", name)
                // Q8: `not_live` answers a subscribe and says so.
                if data.code == .notLive {
                    XCTAssertEqual(data.op, "transcript.subscribe", name)
                }
            default:
                break
            }
        }
    }
}
