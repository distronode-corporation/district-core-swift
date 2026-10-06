import DistrictLive
import DistrictModel
import Foundation

/// Builders for the reducer's tests, in the shapes of the contract's §4.11 example.
enum Frames {
    static let callId = "call_1"
    static let epoch: Int64 = 1_791_297_000_000
    static let t0: Int64 = 1_791_297_002_010

    static func segment(
        _ segmentId: String,
        index: Int,
        seq: Int,
        epoch: Int64 = epoch,
        rev: Int = 0,
        final: Bool = true,
        speaker: TranscriptSpeaker = .caller,
        text: String? = nil
    ) -> TranscriptSegment {
        TranscriptSegment(
            segmentId: segmentId,
            index: index,
            epoch: epoch,
            seq: seq,
            rev: rev,
            speaker: speaker,
            speakerName: speaker == .agent ? "Ava" : nil,
            text: text ?? "\(segmentId) rev \(rev)",
            final: final,
            interrupted: false,
            language: "en",
            startedAt: "2026-10-06T14:30:03.100Z",
            endedAt: final ? "2026-10-06T14:30:06.300Z" : nil
        )
    }

    static func live(_ segment: TranscriptSegment, callId: String = callId) -> TranscriptEvent {
        .segment(TranscriptSegmentData(version: 1, callId: callId, segment: segment))
    }

    static func snapshot(
        _ segments: [TranscriptSegment],
        epoch: Int64? = epoch,
        lastSeq: Int?,
        live: Bool = true,
        complete: Bool = true,
        part: Int = 0,
        more: Bool = false
    ) -> TranscriptEvent {
        .snapshot(TranscriptSnapshotData(
            version: 1,
            callId: callId,
            live: live,
            complete: complete,
            epoch: epoch,
            lastSeq: lastSeq,
            segments: segments,
            part: part,
            more: more
        ))
    }

    static func ended(seq: Int, epoch: Int64 = epoch, reason: TranscriptEndReason = .callEnded) -> TranscriptEvent {
        .ended(TranscriptEndedData(version: 1, callId: callId, epoch: epoch, seq: seq, lastIndex: nil, reason: reason))
    }

    static func retracted(
        _ segmentIds: [String] = [],
        all: Bool = false,
        seq: Int? = nil,
        epoch: Int64? = nil
    ) -> TranscriptEvent {
        .retracted(TranscriptRetractedData(
            version: 1,
            callId: callId,
            all: all,
            segmentIds: segmentIds,
            reason: .erased,
            seq: seq,
            epoch: epoch
        ))
    }

    static func error(
        _ code: TranscriptErrorCode,
        op: String? = "transcript.subscribe",
        retryAfterMs: Int64? = nil,
        callId: String = callId
    ) -> TranscriptEvent {
        .error(TranscriptErrorData(version: 1, callId: callId, op: op, code: code, retryAfterMs: retryAfterMs))
    }

    /// A reducer that has had the §4.11 opening snapshot: live, nothing said, `lastSeq` 0.
    static func liveReducer() -> TranscriptReducer {
        var reducer = TranscriptReducer(callId: callId)
        _ = reducer.apply(snapshot([], lastSeq: 0), atMilliseconds: t0)
        return reducer
    }
}

/// A seeded generator, so a property test that fails fails the same way on every run and
/// on both Foundations.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        return mixed ^ (mixed >> 31)
    }
}
