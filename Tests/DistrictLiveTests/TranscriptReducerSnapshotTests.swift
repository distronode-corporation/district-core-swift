@testable import DistrictLive
import DistrictModel
import Foundation
import XCTest

/// Rule 5: snapshots, their parts, and the epochs a snapshot closes (§4.6 step 5, §4.12 Q6
/// and Q7).
final class TranscriptReducerSnapshotTests: XCTestCase {
    private let t0 = Frames.t0
    private let one = Frames.greeting
    private let two = Frames.segment("s2", index: 1, seq: 2)

    // MARK: - Parts

    /// ⛔ PARTS ARE UNIONED AND APPLIED ONLY AT THE LAST, each repeating the header.
    func testASnapshotInPartsIsAppliedWholeAtTheLastPart() {
        var reducer = TranscriptReducer(callId: "call_1")

        XCTAssertEqual(reducer.apply(Frames.snapshot([one], lastSeq: 2, more: true), atMilliseconds: t0), [])
        XCTAssertEqual(reducer.phase, .subscribing)
        XCTAssertTrue(reducer.lines.isEmpty, "nothing is applied before the last part")

        XCTAssertEqual(reducer.apply(Frames.snapshot([two], lastSeq: 2, part: 1), atMilliseconds: t0), [])

        XCTAssertEqual(reducer.phase, .live)
        XCTAssertEqual(reducer.lines, [one, two])
        XCTAssertEqual(reducer.apply(Frames.live(two), atMilliseconds: t0), [], "at or below lastSeq")
    }

    /// ⚠️ A PART OUT OF ORDER BREAKS THE SNAPSHOT, and it is asked for again only once its
    /// last part has arrived: two heals are never in flight.
    func testAPartOutOfOrderAsksForAWholeSnapshotAfterTheLastPart() {
        var reducer = TranscriptReducer(callId: "call_1")

        XCTAssertEqual(reducer.apply(Frames.snapshot([one], lastSeq: 2, more: true), atMilliseconds: t0), [])
        XCTAssertEqual(reducer.apply(Frames.snapshot([], lastSeq: 2, part: 2, more: true), atMilliseconds: t0), [])
        XCTAssertEqual(
            reducer.apply(Frames.snapshot([two], lastSeq: 2, part: 3), atMilliseconds: t0),
            [.resubscribe(afterMilliseconds: 0)]
        )

        XCTAssertTrue(reducer.lines.isEmpty)
        XCTAssertEqual(reducer.phase, .subscribing)
    }

    /// §4.12 Q6: `live`, `endedReason`, `complete`, `epoch` and `lastSeq` are identical on
    /// every part. A part that disagrees, or one with no part 0 before it, breaks the
    /// snapshot.
    func testAPartWhoseHeaderChangedOrWithNoPartZeroBreaksTheSnapshot() {
        let changes: [TranscriptEvent] = [
            Frames.snapshot([two], lastSeq: 3, part: 1),
            Frames.snapshot([two], lastSeq: 2, live: false, part: 1),
            Frames.snapshot([two], lastSeq: 2, complete: false, part: 1),
            Frames.snapshot([two], epoch: Frames.epoch + 1, lastSeq: 2, part: 1),
            Frames.snapshot([two], lastSeq: 2, endedReason: .agentError, part: 1),
        ]
        for change in changes {
            var reducer = TranscriptReducer(callId: "call_1")
            _ = reducer.apply(Frames.snapshot([one], lastSeq: 2, more: true), atMilliseconds: t0)
            XCTAssertEqual(reducer.apply(change, atMilliseconds: t0), [.resubscribe(afterMilliseconds: 0)])
            XCTAssertTrue(reducer.lines.isEmpty)
        }

        var stray = TranscriptReducer(callId: "call_1")
        XCTAssertEqual(
            stray.apply(Frames.snapshot([two], lastSeq: 2, part: 1), atMilliseconds: t0),
            [.resubscribe(afterMilliseconds: 0)]
        )
    }

    /// A part 0 starts again: only the parts since the last part 0 count.
    func testAPartZeroStartsAgain() {
        var reducer = TranscriptReducer(callId: "call_1")
        _ = reducer.apply(Frames.snapshot([one], lastSeq: 2, more: true), atMilliseconds: t0)
        _ = reducer.apply(Frames.snapshot([two], lastSeq: 2, more: true), atMilliseconds: t0)

        _ = reducer.apply(Frames.snapshot([], lastSeq: 2, part: 1), atMilliseconds: t0)

        XCTAssertEqual(reducer.lines, [two])
    }

    /// ⛔ §4.12 Q6: NO OTHER FRAME ARRIVES BETWEEN PARTS, so a line between them means the
    /// rest of the snapshot was lost: it is dropped and asked for again, and the line is
    /// applied as any other.
    func testALineBetweenPartsDropsTheSnapshotAndAsksAgain() {
        var reducer = Frames.liveReducer()
        reducer.reconnected()
        _ = reducer.apply(Frames.snapshot([one, two], lastSeq: 3, more: true), atMilliseconds: t0)

        XCTAssertEqual(
            reducer.apply(Frames.live(two), atMilliseconds: t0),
            [.resubscribe(afterMilliseconds: 0)]
        )
        XCTAssertEqual(reducer.lines, [one, two])
        _ = reducer.apply(Frames.snapshot([], lastSeq: 3, part: 1), atMilliseconds: t0)
        XCTAssertEqual(reducer.lines, [one, two], "the dropped part 0 is not completed by a part 1")
    }

    /// ⚠️ AN ERROR IS NOT PART OF THE FLOW: one between parts leaves the snapshot alone.
    func testAnErrorBetweenPartsLeavesTheSnapshotAlone() {
        var reducer = Frames.liveReducer()
        reducer.reconnected()
        _ = reducer.apply(Frames.snapshot([one], lastSeq: 2, more: true), atMilliseconds: t0)

        XCTAssertEqual(
            reducer.apply(Frames.error(.rateLimited, retryAfterMs: 7), atMilliseconds: t0),
            [.resubscribe(afterMilliseconds: 7)]
        )
        XCTAssertEqual(reducer.apply(Frames.snapshot([two], lastSeq: 2, part: 1), atMilliseconds: t0), [])
        XCTAssertEqual(reducer.lines, [one, two])
    }

    /// A reconnect drops a half-received snapshot: the new socket's subscribe brings a whole
    /// one. The screen keeps what it had meanwhile.
    func testAReconnectDropsAHalfSnapshot() {
        var reducer = Frames.liveReducer()
        reducer.reconnected()
        _ = reducer.apply(Frames.snapshot([one, two], lastSeq: 2, more: true), atMilliseconds: t0)

        reducer.reconnected()

        XCTAssertEqual(reducer.lines, [one])
        _ = reducer.apply(Frames.snapshot([two], lastSeq: 2), atMilliseconds: t0)
        XCTAssertEqual(reducer.lines, [two])
    }

    // MARK: - What a snapshot says

    /// ⛔ D3: A SNAPSHOT THAT DOES NOT REACH BACK TO THE FIRST LINE SAYS SO.
    func testAnIncompleteSnapshotIsReported() {
        var reducer = TranscriptReducer(callId: "call_1")
        XCTAssertTrue(reducer.complete)

        _ = reducer.apply(Frames.snapshot([one], lastSeq: 1, complete: false), atMilliseconds: t0)

        XCTAssertFalse(reducer.complete)
        XCTAssertEqual(reducer.phase, .live)
    }

    /// ⛔ §4.12 Q12: AFTER AN `all: true` PURGE THE SNAPSHOT HAS NO BASELINE. The state and the
    /// missing set are cleared, and the next frame of any epoch sets that epoch's mark with
    /// no earlier seq counted missing; after it, a skip is a gap again.
    func testAPurgedSnapshotLetsTheNextFrameOfAnyEpochSetTheBaseline() {
        var reducer = Frames.liveReducer()
        _ = reducer.apply(Frames.live(Frames.segment("s4", index: 3, seq: 4)), atMilliseconds: t0)
        _ = reducer.apply(Frames.retracted(all: true), atMilliseconds: t0)
        reducer.reconnected()

        _ = reducer.apply(Frames.snapshot([], epoch: nil, lastSeq: nil, complete: false), atMilliseconds: t0)
        XCTAssertTrue(reducer.lines.isEmpty)
        XCTAssertFalse(reducer.complete)
        XCTAssertEqual(reducer.phase, .live)
        XCTAssertEqual(reducer.gapCheck(atMilliseconds: t0 + 5000), [], "the old gap went with the state")

        let s9 = Frames.segment("s9", index: 8, seq: 9)
        XCTAssertEqual(reducer.apply(Frames.live(s9), atMilliseconds: t0), [], "seq 9 sets the mark")
        let n5 = Frames.segment("n5", index: 4, seq: 5, epoch: Frames.epoch + 60000)
        XCTAssertEqual(reducer.apply(Frames.live(n5), atMilliseconds: t0), [], "so does another epoch's first")
        XCTAssertEqual(reducer.lines, [s9, n5])
        XCTAssertEqual(
            reducer.apply(Frames.live(Frames.segment("s11", index: 10, seq: 11)), atMilliseconds: t0),
            [.checkGap(afterMilliseconds: 2000)],
            "after the mark, seq 10 is missing"
        )
    }

    /// A snapshot with a baseline ends the purge: an epoch first seen after it counts from 0.
    func testASnapshotWithAnEpochEndsThePurge() {
        var reducer = TranscriptReducer(callId: "call_1")
        _ = reducer.apply(Frames.snapshot([], epoch: nil, lastSeq: nil, complete: false), atMilliseconds: t0)
        reducer.reconnected()
        _ = reducer.apply(Frames.snapshot([one], lastSeq: 1), atMilliseconds: t0)

        let n3 = Frames.segment("n3", index: 2, seq: 3, epoch: Frames.epoch + 60000)
        XCTAssertEqual(reducer.apply(Frames.live(n3), atMilliseconds: t0), [.checkGap(afterMilliseconds: 2000)])
    }

    /// ⛔ §4.12 Q7: `lastSeq` COVERS THE SNAPSHOT'S EPOCH ONLY, AND OLDER EPOCHS ARE CLOSED.
    /// Their lines stay for display; a late segment or end of one is dropped, and a
    /// retraction of one still takes its lines off the screen without being counted.
    func testASnapshotClosesOlderEpochsAndMarksItsOwn() {
        let newer = Frames.epoch + 60000
        let fresh = Frames.segment("n1", index: 0, seq: 1, epoch: newer)
        var reducer = TranscriptReducer(callId: "call_1")
        _ = reducer.apply(Frames.snapshot([one, fresh], epoch: newer, lastSeq: 1), atMilliseconds: t0)
        XCTAssertEqual(reducer.lines, [one, fresh])

        XCTAssertEqual(reducer.apply(Frames.live(two), atMilliseconds: t0), [])
        XCTAssertEqual(reducer.apply(Frames.ended(seq: 3), atMilliseconds: t0), [])
        XCTAssertEqual(reducer.phase, .live, "a closed epoch's end ends nothing")
        XCTAssertEqual(reducer.lines, [one, fresh], "a closed epoch's late line is not shown")

        XCTAssertEqual(
            reducer.apply(Frames.retracted(["item_a1"], seq: 4, epoch: Frames.epoch), atMilliseconds: t0),
            []
        )
        XCTAssertEqual(reducer.lines, [fresh])

        let next = Frames.segment("n2", index: 1, seq: 2, epoch: newer)
        XCTAssertEqual(reducer.apply(Frames.live(next), atMilliseconds: t0), [], "seq 2 follows the mark: no gap")
        XCTAssertEqual(reducer.apply(Frames.live(fresh), atMilliseconds: t0), [])
        XCTAssertEqual(reducer.lines, [fresh, next])
    }

    /// ⚠️ A RETRACTED LINE STAYS GONE EVEN WHEN A SNAPSHOT TAKEN BEFORE THE RETRACTION HAS IT.
    func testASnapshotDoesNotBringBackARetractedLine() {
        var reducer = Frames.liveReducer()
        _ = reducer.apply(Frames.retracted(["item_a1"], seq: 2, epoch: Frames.epoch), atMilliseconds: t0)

        _ = reducer.apply(Frames.snapshot([one, two], lastSeq: 2), atMilliseconds: t0)

        XCTAssertEqual(reducer.lines, [two])
    }
}
