@testable import DistrictLive
import DistrictModel
import Foundation
import XCTest

/// The reducer's rules, one at a time, as states and command lists on an injected time.
/// The shuffled and duplicated runs are `TranscriptReducerPropertyTests`.
final class TranscriptReducerTests: XCTestCase {
    private let t0 = Frames.t0

    // MARK: - The contract's example, end to end

    /// ⛔ §4.11, FRAME BY FRAME: the opening snapshot, two finals, a redelivery that is
    /// dropped, a reconnect and its snapshot, the end, and the full transcript fetched once
    /// it is written.
    func testTheContractsShortInboundCall() {
        var reducer = TranscriptReducer(callId: "call_1")
        XCTAssertEqual(reducer.phase, .subscribing)

        XCTAssertEqual(reducer.apply(Frames.snapshot([], lastSeq: 0), atMilliseconds: t0), [])
        XCTAssertEqual(reducer.phase, .live)
        XCTAssertTrue(reducer.lines.isEmpty)

        let greeting = Frames.segment("item_a1", index: 0, seq: 1, speaker: .agent)
        let booking = Frames.segment("item_b2", index: 1, seq: 2)
        XCTAssertEqual(reducer.apply(Frames.live(greeting), atMilliseconds: t0 + 4000), [])
        XCTAssertEqual(reducer.apply(Frames.live(booking), atMilliseconds: t0 + 8000), [])
        XCTAssertEqual(reducer.lines, [greeting, booking])

        let before = reducer
        XCTAssertEqual(reducer.apply(Frames.live(booking), atMilliseconds: t0 + 9000), [], "seq 2 again")
        XCTAssertEqual(reducer, before, "a redelivered frame changes nothing")

        reducer.reconnected()
        let interrupted = Frames.segment("item_c3", index: 2, seq: 3, speaker: .agent)
        let morning = Frames.segment("item_d4", index: 3, seq: 4)
        let all = [greeting, booking, interrupted, morning]
        XCTAssertEqual(reducer.apply(Frames.snapshot(all, lastSeq: 4), atMilliseconds: t0 + 39000), [])
        XCTAssertEqual(reducer.lines, all)

        XCTAssertEqual(
            reducer.apply(Frames.ended(seq: 5), atMilliseconds: t0 + 63000),
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

    // MARK: - Rule 1: stale frames

    /// ⛔ A FRAME THAT ARRIVES AFTER A LATER ONE FILLS ITS GAP: a bare high-water mark would
    /// drop it as stale and lose the line for good.
    func testALateFrameFillsItsGapAndClosesIt() {
        var reducer = Frames.liveReducer()
        let third = Frames.segment("s3", index: 2, seq: 3)
        let second = Frames.segment("s2", index: 1, seq: 2)
        let first = Frames.segment("s1", index: 0, seq: 1)

        XCTAssertEqual(
            reducer.apply(Frames.live(third), atMilliseconds: t0),
            [.checkGap(afterMilliseconds: 2000)],
            "seq 3 after 0 skips two"
        )
        XCTAssertEqual(reducer.apply(Frames.live(second), atMilliseconds: t0 + 10), [], "the gap is already timed")
        XCTAssertEqual(reducer.apply(Frames.live(first), atMilliseconds: t0 + 20), [])
        XCTAssertEqual(reducer.lines, [first, second, third])
        XCTAssertEqual(reducer.gapCheck(atMilliseconds: t0 + 2000), [], "the gap closed before its check")
        XCTAssertEqual(reducer.apply(Frames.live(second), atMilliseconds: t0 + 30), [], "a filled seq is seen")
    }

    /// Anything at or below the high-water mark that is not a known gap is a duplicate.
    func testASeenSeqIsDroppedEvenWithANewRevision() {
        var reducer = Frames.liveReducer()
        _ = reducer.apply(Frames.live(Frames.segment("s1", index: 0, seq: 1, final: false)), atMilliseconds: t0)
        let replay = Frames.segment("s1", index: 0, seq: 1, rev: 9, final: true)

        _ = reducer.apply(Frames.live(replay), atMilliseconds: t0)

        XCTAssertEqual(reducer.lines.first?.rev, 0, "seq decides first; a seen seq is never applied")
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
            let segment = Frames.segment("s1", index: 0, seq: offset + 1, rev: step.rev, final: step.final)
            _ = reducer.apply(Frames.live(segment), atMilliseconds: t0)
            XCTAssertEqual(reducer.lines.count, 1)
            XCTAssertEqual(reducer.lines.first?.rev, step.keptRev, "step \(offset)")
            XCTAssertEqual(reducer.lines.first?.final, step.keptFinal, "step \(offset)")
        }
    }

    // MARK: - Rule 3: order

    func testLinesAreOrderedByEpochThenIndexThenId() {
        var reducer = Frames.liveReducer()
        let later = Frames.epoch + 60000
        let frames = [
            Frames.segment("b", index: 0, seq: 1, epoch: later),
            Frames.segment("z", index: 5, seq: 1),
            Frames.segment("a", index: 0, seq: 2, epoch: later),
            Frames.segment("y", index: 1, seq: 2),
        ]
        for frame in frames {
            _ = reducer.apply(Frames.live(frame), atMilliseconds: t0)
        }

        XCTAssertEqual(reducer.lines.map(\.segmentId), ["y", "z", "a", "b"])
    }

    // MARK: - Rule 4: gaps

    /// ⛔ A GAP STILL OPEN AFTER TWO SECONDS ASKS FOR A SNAPSHOT, which then replaces the
    /// state, and the check before then asks only to be called again.
    func testAGapThatPersistsTwoSecondsResubscribesAndTheSnapshotHealsIt() {
        var reducer = Frames.liveReducer()
        let third = Frames.segment("s3", index: 2, seq: 3)
        XCTAssertEqual(reducer.apply(Frames.live(third), atMilliseconds: t0), [.checkGap(afterMilliseconds: 2000)])

        XCTAssertEqual(reducer.gapCheck(atMilliseconds: t0 + 1500), [.checkGap(afterMilliseconds: 500)])
        XCTAssertEqual(reducer.gapCheck(atMilliseconds: t0 + 2000), [.resubscribe(afterMilliseconds: 0)])
        XCTAssertEqual(reducer.gapCheck(atMilliseconds: t0 + 4000), [], "asked once")

        let healed = [Frames.segment("s1", index: 0, seq: 1), Frames.segment("s2", index: 1, seq: 2), third]
        _ = reducer.apply(Frames.snapshot(healed, lastSeq: 3), atMilliseconds: t0 + 2100)
        XCTAssertEqual(reducer.lines, healed)
        XCTAssertEqual(reducer.apply(Frames.live(healed[0]), atMilliseconds: t0 + 2200), [], "at or below lastSeq")
        XCTAssertEqual(reducer.lines, healed)
    }

    /// A jump too large to track seq by seq is a gap only a snapshot heals: filling one of
    /// its holes does not close it.
    func testAnOverflowingJumpIsHealedOnlyByASnapshot() {
        var reducer = Frames.liveReducer()
        let far = TranscriptReducer.trackedGapLimit + 2
        XCTAssertEqual(
            reducer.apply(Frames.live(Frames.segment("far", index: 9, seq: far)), atMilliseconds: t0),
            [.checkGap(afterMilliseconds: 2000)]
        )
        _ = reducer.apply(Frames.live(Frames.segment("s1", index: 0, seq: 1)), atMilliseconds: t0)
        XCTAssertEqual(reducer.lines.map(\.segmentId), ["far"], "an untracked hole is not a known gap")

        XCTAssertEqual(reducer.gapCheck(atMilliseconds: t0 + 2000), [.resubscribe(afterMilliseconds: 0)])
    }

    /// The largest jump still tracked seq by seq.
    func testAJumpAtTheLimitIsTrackedSeqBySeq() {
        var reducer = Frames.liveReducer()
        let limit = TranscriptReducer.trackedGapLimit
        _ = reducer.apply(Frames.live(Frames.segment("edge", index: 9, seq: limit + 1)), atMilliseconds: t0)
        for seq in 1 ... limit {
            _ = reducer.apply(Frames.live(Frames.segment("s\(seq)", index: 0, seq: seq)), atMilliseconds: t0)
        }

        XCTAssertEqual(reducer.lines.count, limit + 1)
        XCTAssertEqual(reducer.gapCheck(atMilliseconds: t0 + 2000), [], "every hole was filled")
    }

    /// ⚠️ NO GAP BEFORE THE FIRST SNAPSHOT, WHICH SETS THE BASELINE, and none for the first
    /// frame of an epoch older than one already seen: a late copy, not a lost frame.
    func testNoGapOpensBeforeTheFirstSnapshotOrForALateOlderEpoch() {
        var waiting = TranscriptReducer(callId: "call_1")
        XCTAssertEqual(waiting.apply(Frames.live(Frames.segment("s5", index: 4, seq: 5)), atMilliseconds: t0), [])

        var reducer = Frames.liveReducer()
        let newer = Frames.epoch + 60000
        _ = reducer.apply(Frames.live(Frames.segment("n1", index: 0, seq: 1, epoch: newer)), atMilliseconds: t0)
        let older = Frames.epoch - 60000
        XCTAssertEqual(
            reducer.apply(Frames.live(Frames.segment("o7", index: 3, seq: 7, epoch: older)), atMilliseconds: t0),
            []
        )
        XCTAssertEqual(reducer.lines.map(\.segmentId), ["o7", "n1"])
    }

    /// A newer epoch's first frame that is not its first seq does open a gap: the new
    /// assistant's opening lines were lost.
    func testANewEpochsMissingOpeningLinesAreAGap() {
        var reducer = Frames.liveReducer()
        let newer = Frames.epoch + 60000

        XCTAssertEqual(
            reducer.apply(Frames.live(Frames.segment("n3", index: 2, seq: 3, epoch: newer)), atMilliseconds: t0),
            [.checkGap(afterMilliseconds: 2000)]
        )
    }

    // MARK: - Rule 5: snapshots

    /// ⛔ PARTS ARE UNIONED AND APPLIED ONLY AT THE LAST, and a live frame arriving between
    /// them is held and applied after, where one at or below `lastSeq` is a duplicate.
    func testASnapshotInPartsIsAppliedWholeWithTheFramesHeldBehindIt() {
        var reducer = TranscriptReducer(callId: "call_1")
        let one = Frames.segment("s1", index: 0, seq: 1)
        let two = Frames.segment("s2", index: 1, seq: 2)
        let three = Frames.segment("s3", index: 2, seq: 3)

        XCTAssertEqual(reducer.apply(Frames.snapshot([one], lastSeq: 2, more: true), atMilliseconds: t0), [])
        XCTAssertEqual(reducer.phase, .subscribing)
        XCTAssertEqual(reducer.apply(Frames.live(two), atMilliseconds: t0), [])
        XCTAssertEqual(reducer.apply(Frames.live(three), atMilliseconds: t0), [])
        XCTAssertTrue(reducer.lines.isEmpty, "nothing is applied before the last part")

        _ = reducer.apply(Frames.snapshot([two], lastSeq: 2, part: 1), atMilliseconds: t0)

        XCTAssertEqual(reducer.phase, .live)
        XCTAssertEqual(reducer.lines, [one, two, three])
    }

    func testAPartOutOfOrderAsksForAWholeSnapshotAndPartZeroStartsAgain() {
        var reducer = TranscriptReducer(callId: "call_1")
        let one = Frames.segment("s1", index: 0, seq: 1)

        XCTAssertEqual(
            reducer.apply(Frames.snapshot([one], lastSeq: 1, part: 1), atMilliseconds: t0),
            [.resubscribe(afterMilliseconds: 0)]
        )
        _ = reducer.apply(Frames.snapshot([one], lastSeq: 1, more: true), atMilliseconds: t0)
        _ = reducer.apply(Frames.snapshot([], lastSeq: 1, more: true), atMilliseconds: t0)
        XCTAssertEqual(reducer.lines, [], "a new part 0 started again")
        _ = reducer.apply(Frames.snapshot([], lastSeq: 1, part: 1), atMilliseconds: t0)
        XCTAssertEqual(reducer.lines, [], "only the parts since the last part 0 count")
    }

    /// ⛔ D3: A SNAPSHOT THAT DOES NOT REACH BACK TO THE FIRST LINE SAYS SO, and the client
    /// says the earlier lines will be in the full transcript.
    func testAnIncompleteSnapshotIsReported() {
        var reducer = TranscriptReducer(callId: "call_1")
        XCTAssertTrue(reducer.complete)

        _ = reducer.apply(Frames.snapshot([], epoch: nil, lastSeq: nil, complete: false), atMilliseconds: t0)

        XCTAssertFalse(reducer.complete)
        XCTAssertEqual(reducer.phase, .live)
    }

    func testASnapshotOfAnEndedTranscriptEndsItAndFetchesTheFullOne() {
        var reducer = TranscriptReducer(callId: "call_1")

        XCTAssertEqual(
            reducer.apply(Frames.snapshot([], lastSeq: 3, live: false), atMilliseconds: t0),
            [.fetchFinal(afterMilliseconds: 2000)]
        )
        XCTAssertEqual(reducer.phase, .ended(.callEnded))
    }

    /// A reconnect drops a half-received snapshot and the frames held behind it, and closes
    /// any gap: the new subscribe's snapshot replaces the state anyway.
    func testAReconnectDropsAHalfSnapshotAndClosesGaps() {
        var reducer = Frames.liveReducer()
        _ = reducer.apply(Frames.live(Frames.segment("s3", index: 2, seq: 3)), atMilliseconds: t0)
        _ = reducer.apply(Frames.snapshot([], lastSeq: 3, more: true), atMilliseconds: t0)
        _ = reducer.apply(Frames.live(Frames.segment("s4", index: 3, seq: 4)), atMilliseconds: t0)

        reducer.reconnected()

        XCTAssertEqual(reducer.gapCheck(atMilliseconds: t0 + 5000), [])
        XCTAssertEqual(reducer.lines.map(\.segmentId), ["s3"], "the screen keeps what it had")
        _ = reducer.apply(Frames.snapshot([], lastSeq: 9, part: 1), atMilliseconds: t0)
        XCTAssertEqual(reducer.lines.map(\.segmentId), ["s3"], "the dropped part 0 is not completed by a part 1")
    }

    // MARK: - Rule 6: the end

    func testACallEndedEndsTheTranscriptOnceAndFetchesOnce() {
        var reducer = Frames.liveReducer()

        XCTAssertEqual(reducer.callEnded(), [.fetchFinal(afterMilliseconds: 2000)])
        XCTAssertEqual(reducer.phase, .ended(.callEnded))
        XCTAssertEqual(reducer.apply(Frames.ended(seq: 1, reason: .handedOff), atMilliseconds: t0), [])
        XCTAssertEqual(reducer.phase, .ended(.handedOff), "the reason is updated, the fetch is not repeated")
    }

    /// ⚠️ A NEWER EPOCH AFTER AN END IS A RE-DISPATCHED ASSISTANT; a late line of the ended
    /// epoch is shown but does not revive the call.
    func testANewerEpochRevivesAnEndedTranscriptAndALateLineDoesNot() {
        var reducer = Frames.liveReducer()
        _ = reducer.apply(Frames.live(Frames.segment("s1", index: 0, seq: 1)), atMilliseconds: t0)
        _ = reducer.apply(Frames.ended(seq: 3, reason: .agentError), atMilliseconds: t0)

        _ = reducer.apply(Frames.live(Frames.segment("s2", index: 1, seq: 2)), atMilliseconds: t0)
        XCTAssertEqual(reducer.phase, .ended(.agentError))
        XCTAssertEqual(reducer.lines.count, 2)

        let newer = Frames.epoch + 60000
        _ = reducer.apply(Frames.live(Frames.segment("n1", index: 0, seq: 1, epoch: newer)), atMilliseconds: t0)
        XCTAssertEqual(reducer.phase, .live)
    }

    func testAnEndedSnapshotsEpochIsTheOneANewerEpochRevives() {
        var reducer = TranscriptReducer(callId: "call_1")
        _ = reducer.apply(Frames.snapshot([], lastSeq: 2, live: false), atMilliseconds: t0)

        _ = reducer.apply(
            Frames.live(Frames.segment("n1", index: 0, seq: 1, epoch: Frames.epoch + 1)),
            atMilliseconds: t0
        )

        XCTAssertEqual(reducer.phase, .live)
    }

    func testARepeatedEndIsADuplicate() {
        var reducer = Frames.liveReducer()
        _ = reducer.apply(Frames.ended(seq: 1), atMilliseconds: t0)

        XCTAssertEqual(reducer.apply(Frames.ended(seq: 1, reason: .handedOff), atMilliseconds: t0), [])
        XCTAssertEqual(reducer.phase, .ended(.callEnded))
    }

    func testEventsForAnotherCallChangeNothing() {
        var reducer = Frames.liveReducer()
        let before = reducer

        XCTAssertEqual(
            reducer.apply(Frames.live(Frames.segment("x", index: 0, seq: 1), callId: "call_2"), atMilliseconds: t0),
            []
        )
        XCTAssertEqual(reducer.apply(Frames.error(.notLive, callId: "call_2"), atMilliseconds: t0), [])
        XCTAssertEqual(reducer, before)
    }
}
