@testable import DistrictLive
import DistrictModel
import Foundation
import XCTest

/// The reducer against delivery as Pub/Sub really makes it: at least once and in any
/// order. Each test builds a random call (two assistant sessions, interim revisions before
/// each final), delivers it shuffled and duplicated, and checks the screen ends where an
/// orderly delivery would have put it.
///
/// ⚠️ SEEDED, so a failure names its seed and fails the same way on every run and on both
/// Foundations. Two hundred seeds per property.
final class TranscriptReducerPropertyTests: XCTestCase {
    private let seeds: [UInt64] = Array(1 ... 200)
    private let t0 = Frames.t0

    /// One random call: every frame the assistants publish, in publication order, and the
    /// final revision of every segment.
    private struct Call {
        var frames: [TranscriptSegment] = []
        var finals: [TranscriptSegment] = []
        /// The highest seq of each epoch.
        var lastSeq: [Int64: Int] = [:]
    }

    private func randomCall(
        _ random: inout SplitMix64,
        epochs: [Int64] = [Frames.epoch, Frames.epoch + 90000]
    ) -> Call {
        var call = Call()
        for epoch in epochs {
            var seq = 0
            for index in 0 ..< Int.random(in: 1 ... 6, using: &random) {
                let interims = Int.random(in: 0 ... 3, using: &random)
                for rev in 0 ... interims {
                    seq += 1
                    let segment = Frames.segment(
                        "\(epoch)-\(index)",
                        index: index,
                        seq: seq,
                        epoch: epoch,
                        rev: rev,
                        final: rev == interims,
                        speaker: index.isMultiple(of: 2) ? .agent : .caller
                    )
                    call.frames.append(segment)
                    if segment.final {
                        call.finals.append(segment)
                    }
                }
            }
            call.lastSeq[epoch] = seq
        }
        call.finals.sort { ($0.epoch, $0.index) < ($1.epoch, $1.index) }
        return call
    }

    /// The frames shuffled, with about a third delivered twice.
    private func delivery(_ frames: [TranscriptSegment], _ random: inout SplitMix64) -> [TranscriptSegment] {
        let duplicates = frames.filter { _ in Int.random(in: 0 ... 2, using: &random) == 0 }
        return (frames + duplicates).shuffled(using: &random)
    }

    // MARK: - Properties

    /// ⛔ SHUFFLED, DUPLICATED, INTERIM AND FINAL IN ANY ORDER, ACROSS AN EPOCH CHANGE: every
    /// segment ends at its final, in order, with no gap left open.
    func testAnyOrderAndAnyDuplicationEndsAtTheFinals() {
        for seed in seeds {
            var random = SplitMix64(seed: seed)
            let call = randomCall(&random)
            var reducer = Frames.liveReducer()

            for (offset, segment) in delivery(call.frames, &random).enumerated() {
                _ = reducer.apply(Frames.live(segment), atMilliseconds: t0 + Int64(offset))
            }

            XCTAssertEqual(reducer.lines, call.finals, "seed \(seed)")
            XCTAssertTrue(reducer.lines.allSatisfy(\.final), "seed \(seed)")
            XCTAssertEqual(reducer.gapCheck(atMilliseconds: t0 + 60000), [], "seed \(seed): a gap stayed open")
            XCTAssertEqual(reducer.phase, .live, "seed \(seed)")
        }
    }

    /// ⛔ A LOST FRAME IS A GAP, AND THE SNAPSHOT IT ASKS FOR HEALS IT: two seconds after the
    /// loss is noticed the call is subscribed again, and the snapshot (built here from the
    /// orderly state, as the server's memory holds it) puts the screen right.
    func testALostFrameIsHealedByTheSnapshotItAsksFor() {
        for seed in seeds {
            var random = SplitMix64(seed: seed)
            let call = randomCall(&random, epochs: [Frames.epoch])
            guard call.frames.count > 1 else { continue }
            // ⚠️ NOT THE LAST FRAME: a loss nothing after it reveals cannot be noticed.
            let lost = Int.random(in: 0 ..< call.frames.count - 1, using: &random)
            var reducer = Frames.liveReducer()
            var asked: [TranscriptCommand] = []
            var kept = call.frames
            kept.remove(at: lost)

            for segment in delivery(kept, &random) {
                asked += reducer.apply(Frames.live(segment), atMilliseconds: t0)
            }

            XCTAssertTrue(asked.contains(.checkGap(afterMilliseconds: 2000)), "seed \(seed)")
            XCTAssertEqual(
                reducer.gapCheck(atMilliseconds: t0 + 2000),
                [.resubscribe(afterMilliseconds: 0)],
                "seed \(seed)"
            )
            let snapshot = Frames.snapshot(call.finals, lastSeq: call.lastSeq[Frames.epoch])
            _ = reducer.apply(snapshot, atMilliseconds: t0 + 2100)
            XCTAssertEqual(reducer.lines, call.finals, "seed \(seed)")
            for segment in delivery(call.frames, &random) {
                _ = reducer.apply(Frames.live(segment), atMilliseconds: t0 + 2200)
            }
            XCTAssertEqual(reducer.lines, call.finals, "seed \(seed): a late copy after the snapshot")
        }
    }

    /// ⛔ RETRACTED LINES STAY GONE THROUGH ANY REDELIVERY, and the rest are untouched.
    func testRetractedLinesStayGoneThroughAnyRedelivery() {
        for seed in seeds {
            var random = SplitMix64(seed: seed)
            let call = randomCall(&random)
            var reducer = Frames.liveReducer()
            for segment in delivery(call.frames, &random) {
                _ = reducer.apply(Frames.live(segment), atMilliseconds: t0)
            }

            let gone = Set(call.finals.map(\.segmentId).filter { _ in Bool.random(using: &random) })
            let newest = Frames.epoch + 90000
            let seq = call.lastSeq[newest, default: 0] + 1
            _ = reducer.apply(Frames.retracted(gone.sorted(), seq: seq, epoch: newest), atMilliseconds: t0)
            for segment in delivery(call.frames, &random) {
                _ = reducer.apply(Frames.live(segment), atMilliseconds: t0)
            }

            XCTAssertEqual(reducer.lines, call.finals.filter { !gone.contains($0.segmentId) }, "seed \(seed)")
            XCTAssertEqual(reducer.gapCheck(atMilliseconds: t0 + 60000), [], "seed \(seed)")
        }
    }

    /// ⛔ A SNAPSHOT IN PARTS WITH THE LIVE FRAMES ARRIVING BETWEEN THEM, IN ANY ORDER, ends
    /// where the frames say: the snapshot holds the first half of the call and the live
    /// frames the rest, some of both delivered twice.
    func testASnapshotInPartsWithLiveFramesBetweenThemEndsAtTheFinals() {
        for seed in seeds {
            var random = SplitMix64(seed: seed)
            let call = randomCall(&random, epochs: [Frames.epoch])
            let cut = Int.random(in: 0 ... call.frames.count, using: &random)
            let before = Array(call.frames[..<cut])
            var latest: [String: TranscriptSegment] = [:]
            for segment in before {
                latest[segment.segmentId] = segment
            }
            let summary = latest.values.sorted { $0.index < $1.index }
            let half = summary.count / 2
            var reducer = TranscriptReducer(callId: "call_1")
            let lastSeq = cut == 0 ? nil : cut

            _ = reducer.apply(
                Frames.snapshot(Array(summary[..<half]), lastSeq: lastSeq, more: true),
                atMilliseconds: t0
            )
            var between = delivery(Array(call.frames[cut...]) + before.suffix(2), &random)
            let early = between.prefix(between.count / 2)
            between.removeFirst(early.count)
            for segment in early {
                _ = reducer.apply(Frames.live(segment), atMilliseconds: t0)
            }
            _ = reducer.apply(Frames.snapshot(Array(summary[half...]), lastSeq: lastSeq, part: 1), atMilliseconds: t0)
            for segment in between {
                _ = reducer.apply(Frames.live(segment), atMilliseconds: t0)
            }

            XCTAssertEqual(reducer.lines, call.finals, "seed \(seed)")
            XCTAssertEqual(reducer.gapCheck(atMilliseconds: t0 + 60000), [], "seed \(seed)")
        }
    }
}
