@testable import DistrictLive
import DistrictModel
import Foundation
import XCTest

/// The reducer's rules 1 to 4, one at a time, as states and command lists on an injected
/// time. Snapshots and epochs are `TranscriptReducerSnapshotTests`, the end
/// `TranscriptReducerEndTests`, and the shuffled and duplicated runs
/// `TranscriptReducerPropertyTests`.
final class TranscriptReducerTests: XCTestCase {
    private let t0 = Frames.t0

    // MARK: - The contract's example, end to end

    /// ⛔ §4.11, FRAME BY FRAME: the subscribe held until the greeting exists and answered
    /// with a snapshot that has it, a final, a redelivery that is dropped, a reconnect and
    /// its snapshot, the end, and the full transcript fetched once it is written.
    func testTheContractsShortInboundCall() {
        var reducer = TranscriptReducer(callId: "call_1")
        XCTAssertEqual(reducer.phase, .subscribing)

        XCTAssertEqual(reducer.apply(Frames.snapshot([Frames.greeting], lastSeq: 1), atMilliseconds: t0 + 4410), [])
        XCTAssertEqual(reducer.phase, .live)
        XCTAssertEqual(reducer.lines, [Frames.greeting])

        let booking = Frames.segment("item_b2", index: 1, seq: 2)
        XCTAssertEqual(reducer.apply(Frames.live(booking), atMilliseconds: t0 + 8940), [])
        XCTAssertEqual(reducer.lines, [Frames.greeting, booking])

        let before = reducer
        XCTAssertEqual(reducer.apply(Frames.live(booking), atMilliseconds: t0 + 9000), [], "seq 2 again")
        XCTAssertEqual(reducer, before, "a redelivered frame changes nothing")

        reducer.reconnected()
        let interrupted = Frames.segment("item_c3", index: 2, seq: 3, speaker: .agent)
        let morning = Frames.segment("item_d4", index: 3, seq: 4)
        let all = [Frames.greeting, booking, interrupted, morning]
        XCTAssertEqual(reducer.apply(Frames.snapshot(all, lastSeq: 4), atMilliseconds: t0 + 38990), [])
        XCTAssertEqual(reducer.lines, all)

        XCTAssertEqual(
            reducer.apply(Frames.ended(seq: 5), atMilliseconds: t0 + 63290),
            [.fetchFinal(afterMilliseconds: 2000)]
        )
        XCTAssertEqual(reducer.phase, .ended(.callEnded))
        XCTAssertEqual(reducer.lines, all, "the lines stay on screen")
        XCTAssertEqual(reducer.finalTranscript, .fetching(attempt: 1))

        XCTAssertEqual(reducer.finalFetched(.success("  \n")), [.fetchFinal(afterMilliseconds: 4000)])
        XCTAssertEqual(reducer.finalTranscript, .fetching(attempt: 2))
        XCTAssertEqual(reducer.finalFetched(.success("Ava: Good afternoon")), [.unsubscribe])
        XCTAssertEqual(reducer.finalTranscript, .loaded("Ava: Good afternoon"))
        XCTAssertEqual(reducer.finalFetched(.success("again")), [], "nothing is being fetched any more")
    }

    // MARK: - Rule 1: the high-water mark and the missing set

    /// ⛔ §4.12 Q1: A FRAME THAT ARRIVES AFTER A LATER ONE FILLS ITS GAP. A bare high-water
    /// mark would drop it as stale and lose the line for good.
    func testALateFrameFillsItsGapAndClosesIt() {
        var reducer = Frames.liveReducer()
        let fourth = Frames.segment("s4", index: 3, seq: 4)
        let third = Frames.segment("s3", index: 2, seq: 3)
        let second = Frames.segment("s2", index: 1, seq: 2)

        XCTAssertEqual(
            reducer.apply(Frames.live(fourth), atMilliseconds: t0),
            [.checkGap(afterMilliseconds: 2000)],
            "seq 4 after 1 skips two"
        )
        XCTAssertEqual(reducer.apply(Frames.live(third), atMilliseconds: t0 + 10), [], "the gap is already timed")
        XCTAssertEqual(reducer.apply(Frames.live(second), atMilliseconds: t0 + 20), [])
        XCTAssertEqual(reducer.lines, [Frames.greeting, second, third, fourth])
        XCTAssertEqual(reducer.gapCheck(atMilliseconds: t0 + 2000), [], "the gap closed before its check")
        XCTAssertEqual(reducer.apply(Frames.live(third), atMilliseconds: t0 + 30), [], "a filled seq is seen")
    }

    /// The missing set splits around each seq that fills it, from either end or the middle,
    /// and a seq filled once is a duplicate after.
    func testTheMissingSetSplitsAroundEveryFill() {
        var reducer = Frames.liveReducer()
        XCTAssertEqual(
            reducer.apply(Frames.live(Frames.segment("s7", index: 6, seq: 7)), atMilliseconds: t0),
            [.checkGap(afterMilliseconds: 2000)]
        )
        for seq in [4, 6, 2, 5] {
            _ = reducer.apply(Frames.live(Frames.segment("s\(seq)", index: seq - 1, seq: seq)), atMilliseconds: t0)
        }
        let replay = Frames.segment("s4", index: 3, seq: 4, rev: 1)
        _ = reducer.apply(Frames.live(replay), atMilliseconds: t0)
        XCTAssertEqual(reducer.lines.first { $0.segmentId == "s4" }?.rev, 0, "seq 4 was filled already")
        XCTAssertEqual(reducer.gapCheck(atMilliseconds: t0 + 2000), [.resubscribe(afterMilliseconds: 0)], "3 is open")

        _ = reducer.apply(Frames.live(Frames.segment("s3", index: 2, seq: 3)), atMilliseconds: t0)

        XCTAssertEqual(reducer.lines.map(\.segmentId), ["item_a1", "s2", "s3", "s4", "s5", "s6", "s7"])
    }

    /// ⚠️ A JUMP OF ANY SIZE IS TRACKED EXACTLY, as one range: a seq inside it fills it.
    func testAJumpOfAnySizeIsTrackedSeqBySeq() {
        var reducer = Frames.liveReducer()
        _ = reducer.apply(Frames.live(Frames.segment("far", index: 9, seq: 1_000_000)), atMilliseconds: t0)

        _ = reducer.apply(Frames.live(Frames.segment("s2", index: 1, seq: 2)), atMilliseconds: t0)
        _ = reducer.apply(Frames.live(Frames.segment("late", index: 8, seq: 999_999)), atMilliseconds: t0)

        XCTAssertEqual(reducer.lines.map(\.segmentId), ["item_a1", "s2", "late", "far"])
        XCTAssertEqual(reducer.gapCheck(atMilliseconds: t0 + 2000), [.resubscribe(afterMilliseconds: 0)])
    }

    /// Hostile input: a seq the server never sends (below 1) is dropped and opens nothing,
    /// and the largest one is a mark like any other.
    func testASeqBelowOneIsDroppedAndTheLargestIsAMark() {
        var reducer = Frames.liveReducer()
        let before = reducer
        for seq in [0, -5, Int.min] {
            XCTAssertEqual(
                reducer.apply(Frames.live(Frames.segment("bad", index: 1, seq: seq)), atMilliseconds: t0),
                [],
                "seq \(seq)"
            )
        }
        XCTAssertEqual(reducer, before)

        XCTAssertEqual(
            reducer.apply(Frames.live(Frames.segment("max", index: 1, seq: .max)), atMilliseconds: t0),
            [.checkGap(afterMilliseconds: 2000)]
        )
        XCTAssertEqual(
            reducer.apply(Frames.live(Frames.segment("max", index: 1, seq: .max, rev: 1)), atMilliseconds: t0),
            []
        )
        XCTAssertEqual(reducer.lines.last?.rev, 0, "the largest seq again is a duplicate")
    }

    /// Anything at or below the high-water mark that is not missing is a duplicate.
    func testASeenSeqIsDroppedEvenWithANewRevision() {
        var reducer = Frames.liveReducer()
        _ = reducer.apply(Frames.live(Frames.segment("s2", index: 1, seq: 2, final: false)), atMilliseconds: t0)
        let replay = Frames.segment("s2", index: 1, seq: 2, rev: 9, final: true)

        _ = reducer.apply(Frames.live(replay), atMilliseconds: t0)

        XCTAssertEqual(reducer.lines.last?.rev, 0, "seq decides first; a seen seq is never applied")
    }

    // MARK: - Rule 2: revisions

    func testTheLatestRevisionWinsAndAFinalBeatsAnyInterim() {
        var reducer = Frames.liveReducer()
        struct Step {
            let rev: Int
            let final: Bool
            let keptRev: Int
            let keptFinal: Bool
        }
        let steps = [
            Step(rev: 1, final: false, keptRev: 1, keptFinal: false), // first sight
            Step(rev: 0, final: false, keptRev: 1, keptFinal: false), // lower interim: ignored
            Step(rev: 2, final: false, keptRev: 2, keptFinal: false), // higher interim: wins
            Step(rev: 0, final: true, keptRev: 0, keptFinal: true), // a final beats an interim at any rev
            Step(rev: 5, final: false, keptRev: 0, keptFinal: true), // no interim beats a final
            Step(rev: 1, final: true, keptRev: 1, keptFinal: true), // a later final revision wins
            Step(rev: 0, final: true, keptRev: 1, keptFinal: true), // a lower final does not
        ]
        for (offset, step) in steps.enumerated() {
            let segment = Frames.segment("s2", index: 1, seq: offset + 2, rev: step.rev, final: step.final)
            _ = reducer.apply(Frames.live(segment), atMilliseconds: t0)
            XCTAssertEqual(reducer.lines.count, 2)
            XCTAssertEqual(reducer.lines.last?.rev, step.keptRev, "step \(offset)")
            XCTAssertEqual(reducer.lines.last?.final, step.keptFinal, "step \(offset)")
        }
    }

    // MARK: - Rule 3: order

    func testLinesAreOrderedByEpochThenIndexThenId() {
        var reducer = Frames.liveReducer()
        let later = Frames.epoch + 60000
        let frames = [
            Frames.segment("b", index: 0, seq: 1, epoch: later),
            Frames.segment("z", index: 5, seq: 2),
            Frames.segment("a", index: 0, seq: 2, epoch: later),
            Frames.segment("y", index: 1, seq: 3),
        ]
        for frame in frames {
            _ = reducer.apply(Frames.live(frame), atMilliseconds: t0)
        }

        XCTAssertEqual(reducer.lines.map(\.segmentId), ["item_a1", "y", "z", "a", "b"])
    }

    // MARK: - Rule 4: gaps, one heal in flight

    /// ⛔ A GAP STILL OPEN AFTER TWO SECONDS ASKS FOR A SNAPSHOT, which then replaces the
    /// state; the check before then asks only to be called again.
    func testAGapThatPersistsTwoSecondsResubscribesAndTheSnapshotHealsIt() {
        var reducer = Frames.liveReducer()
        let third = Frames.segment("s3", index: 2, seq: 3)
        XCTAssertEqual(reducer.apply(Frames.live(third), atMilliseconds: t0), [.checkGap(afterMilliseconds: 2000)])

        XCTAssertEqual(reducer.gapCheck(atMilliseconds: t0 + 1500), [.checkGap(afterMilliseconds: 500)])
        XCTAssertEqual(reducer.gapCheck(atMilliseconds: t0 + 2000), [.resubscribe(afterMilliseconds: 0)])

        let healed = [Frames.greeting, Frames.segment("s2", index: 1, seq: 2), third]
        _ = reducer.apply(Frames.snapshot(healed, lastSeq: 3), atMilliseconds: t0 + 2100)
        XCTAssertEqual(reducer.lines, healed)
        XCTAssertEqual(reducer.apply(Frames.live(healed[1]), atMilliseconds: t0 + 2200), [], "at or below lastSeq")
        XCTAssertEqual(reducer.lines, healed)
    }

    /// ⛔ §4.6 STEP 4: NO NEW HEAL UNTIL THE LAST ONE'S SNAPSHOT HAS ARRIVED WHOLE, however
    /// often the check runs; after it, a new gap heals again.
    func testOnlyOneHealIsInFlight() {
        var reducer = Frames.liveReducer()
        _ = reducer.apply(Frames.live(Frames.segment("s3", index: 2, seq: 3)), atMilliseconds: t0)
        XCTAssertEqual(reducer.gapCheck(atMilliseconds: t0 + 2000), [.resubscribe(afterMilliseconds: 0)])

        XCTAssertEqual(reducer.gapCheck(atMilliseconds: t0 + 4000), [], "the first heal is unanswered")
        _ = reducer.apply(Frames.live(Frames.segment("s5", index: 4, seq: 5)), atMilliseconds: t0 + 4100)
        XCTAssertEqual(reducer.gapCheck(atMilliseconds: t0 + 9000), [], "still unanswered")
        _ = reducer.apply(Frames.snapshot([Frames.greeting], lastSeq: 5, more: true), atMilliseconds: t0 + 9100)
        XCTAssertEqual(reducer.gapCheck(atMilliseconds: t0 + 9200), [], "a part is not the answer, the last part is")
        _ = reducer.apply(Frames.snapshot([], lastSeq: 5, part: 1), atMilliseconds: t0 + 9300)

        XCTAssertEqual(
            reducer.apply(Frames.live(Frames.segment("s7", index: 6, seq: 7)), atMilliseconds: t0 + 9400),
            [.checkGap(afterMilliseconds: 2000)]
        )
        XCTAssertEqual(reducer.gapCheck(atMilliseconds: t0 + 11400), [.resubscribe(afterMilliseconds: 0)])
    }

    /// ⚠️ THE MISSING SET LASTS UNTIL THE SNAPSHOT CLEARS IT: a late frame that arrives while
    /// the heal is in flight still fills its gap and is shown.
    func testALateFrameDuringAHealIsStillApplied() {
        var reducer = Frames.liveReducer()
        _ = reducer.apply(Frames.live(Frames.segment("s3", index: 2, seq: 3)), atMilliseconds: t0)
        _ = reducer.gapCheck(atMilliseconds: t0 + 2000)

        _ = reducer.apply(Frames.live(Frames.segment("s2", index: 1, seq: 2)), atMilliseconds: t0 + 2050)

        XCTAssertEqual(reducer.lines.map(\.segmentId), ["item_a1", "s2", "s3"])
    }

    /// The first subscribe is a heal in flight too, and so is the one a reconnect sends: a
    /// gap that opens before either is answered asks for nothing.
    func testNoHealWhileTheFirstSubscribeOrAReconnectsIsUnanswered() {
        var waiting = TranscriptReducer(callId: "call_1")
        XCTAssertEqual(
            waiting.apply(Frames.live(Frames.segment("s3", index: 2, seq: 3)), atMilliseconds: t0),
            [.checkGap(afterMilliseconds: 2000)]
        )
        XCTAssertEqual(waiting.gapCheck(atMilliseconds: t0 + 5000), [])
        XCTAssertEqual(waiting.phase, .subscribing)

        var reducer = Frames.liveReducer()
        _ = reducer.apply(Frames.live(Frames.segment("s3", index: 2, seq: 3)), atMilliseconds: t0)
        reducer.reconnected()
        XCTAssertEqual(reducer.gapCheck(atMilliseconds: t0 + 5000), [])
    }

    /// A newer epoch's first frame that is not its first seq opens a gap: the new
    /// assistant's opening lines were lost.
    func testANewEpochsMissingOpeningLinesAreAGap() {
        var reducer = Frames.liveReducer()
        let newer = Frames.epoch + 60000

        XCTAssertEqual(
            reducer.apply(Frames.live(Frames.segment("n3", index: 2, seq: 3, epoch: newer)), atMilliseconds: t0),
            [.checkGap(afterMilliseconds: 2000)]
        )
    }

    func testEventsForAnotherCallChangeNothing() {
        var reducer = Frames.liveReducer()
        let before = reducer

        XCTAssertEqual(
            reducer.apply(Frames.live(Frames.segment("x", index: 0, seq: 2), callId: "call_2"), atMilliseconds: t0),
            []
        )
        XCTAssertEqual(reducer.apply(Frames.error(.notLive, callId: "call_2"), atMilliseconds: t0), [])
        XCTAssertEqual(reducer, before)
    }
}
