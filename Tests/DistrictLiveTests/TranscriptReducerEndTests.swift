@testable import DistrictLive
import DistrictModel
import Foundation
import XCTest

/// Rule 6: the end, and the one end that is not final (§4.12 Q7). `call_ended` and
/// `handed_off` are terminal; `agent_error` may be followed by a fresh assistant's epoch,
/// and until then the screen says "reconnecting".
final class TranscriptReducerEndTests: XCTestCase {
    private let t0 = Frames.t0
    private let newer = Frames.epoch + 60000

    // MARK: - Final ends

    func testACallEndedEndsTheTranscriptOnceAndFetchesOnce() {
        var reducer = Frames.liveReducer()

        XCTAssertEqual(reducer.callEnded(), [.fetchFinal(afterMilliseconds: 2000)])
        XCTAssertEqual(reducer.phase, .ended(.callEnded))
        XCTAssertEqual(reducer.apply(Frames.ended(seq: 2, reason: .handedOff), atMilliseconds: t0), [])
        XCTAssertEqual(reducer.phase, .ended(.handedOff), "the reason is updated, the fetch is not repeated")
    }

    /// An end reason this client does not know is read as final.
    func testAnUnknownReasonIsFinal() {
        var reducer = Frames.liveReducer()

        XCTAssertEqual(
            reducer.apply(Frames.ended(seq: 2, reason: .other("parked")), atMilliseconds: t0),
            [.fetchFinal(afterMilliseconds: 2000)]
        )
        XCTAssertEqual(reducer.phase, .ended(.other("parked")))
    }

    /// ⛔ A FINAL END STAYS FINAL: no `agent_error`, no newer epoch and no snapshot brings
    /// the call back, and a snapshot does not rewrite why it ended.
    func testAFinalEndCannotBeUndone() {
        var reducer = Frames.liveReducer()
        _ = reducer.apply(Frames.ended(seq: 2, reason: .handedOff), atMilliseconds: t0)

        XCTAssertEqual(reducer.apply(Frames.ended(seq: 3, reason: .agentError), atMilliseconds: t0), [])
        _ = reducer.apply(Frames.live(Frames.segment("n1", index: 0, seq: 1, epoch: newer)), atMilliseconds: t0)
        reducer.reconnected()
        XCTAssertEqual(reducer.apply(Frames.snapshot([], epoch: newer, lastSeq: 1), atMilliseconds: t0), [])
        reducer.reconnected()
        XCTAssertEqual(
            reducer.apply(Frames.snapshot([], epoch: newer, lastSeq: 1, live: false), atMilliseconds: t0),
            []
        )

        XCTAssertEqual(reducer.phase, .ended(.handedOff))
        XCTAssertEqual(reducer.finalTranscript, .fetching(attempt: 1))
    }

    func testARepeatedEndIsADuplicate() {
        var reducer = Frames.liveReducer()
        _ = reducer.apply(Frames.ended(seq: 2), atMilliseconds: t0)

        XCTAssertEqual(reducer.apply(Frames.ended(seq: 2, reason: .handedOff), atMilliseconds: t0), [])
        XCTAssertEqual(reducer.phase, .ended(.callEnded))
    }

    /// ⚠️ ONLY THE NEWEST EPOCH'S END ENDS ANYTHING: a late end of an older one is counted
    /// and changes nothing on screen.
    func testALateEndOfAnOlderEpochChangesNothing() {
        var reducer = Frames.liveReducer()
        _ = reducer.apply(Frames.live(Frames.segment("n1", index: 0, seq: 1, epoch: newer)), atMilliseconds: t0)

        XCTAssertEqual(reducer.apply(Frames.ended(seq: 2), atMilliseconds: t0), [])

        XCTAssertEqual(reducer.phase, .live)
        XCTAssertEqual(reducer.finalTranscript, .notRequested)
    }

    // MARK: - agent_error: reconnecting

    /// ⛔ AGENT_ERROR IS NOT THE END: the screen says "reconnecting", nothing is fetched, a
    /// late line of the failed epoch is still shown, and a fresh assistant's first line
    /// makes it live again until its own final end.
    func testAnAgentErrorReconnectsUntilANewEpoch() {
        var reducer = Frames.liveReducer()
        XCTAssertEqual(reducer.apply(Frames.ended(seq: 3, reason: .agentError), atMilliseconds: t0), [
            .checkGap(afterMilliseconds: 2000),
        ])
        XCTAssertEqual(reducer.phase, .reconnecting)
        XCTAssertEqual(reducer.finalTranscript, .notRequested)

        _ = reducer.apply(Frames.live(Frames.segment("s2", index: 1, seq: 2)), atMilliseconds: t0)
        XCTAssertEqual(reducer.phase, .reconnecting, "a late line of the same epoch")
        XCTAssertEqual(reducer.lines.count, 2)

        _ = reducer.apply(Frames.live(Frames.segment("n1", index: 0, seq: 1, epoch: newer)), atMilliseconds: t0)
        XCTAssertEqual(reducer.phase, .live)
        XCTAssertEqual(reducer.lines.map(\.segmentId), ["item_a1", "s2", "n1"])

        XCTAssertEqual(
            reducer.apply(Frames.ended(seq: 2, epoch: newer), atMilliseconds: t0),
            [.fetchFinal(afterMilliseconds: 2000)]
        )
        XCTAssertEqual(reducer.phase, .ended(.callEnded))
    }

    /// ⚠️ A SNAPSHOT THAT SAYS ONLY "NOT LIVE" FOR THE FAILED EPOCH keeps the screen
    /// reconnecting (it carries no reason); one that is live with a newer epoch is the
    /// fresh assistant.
    func testASnapshotWhileReconnecting() {
        var reducer = Frames.liveReducer()
        _ = reducer.apply(Frames.ended(seq: 2, reason: .agentError), atMilliseconds: t0)

        reducer.reconnected()
        XCTAssertEqual(
            reducer.apply(Frames.snapshot([Frames.greeting], lastSeq: 2, live: false), atMilliseconds: t0),
            []
        )
        XCTAssertEqual(reducer.phase, .reconnecting)

        reducer.reconnected()
        let fresh = Frames.segment("n1", index: 0, seq: 1, epoch: newer)
        XCTAssertEqual(
            reducer.apply(Frames.snapshot([Frames.greeting, fresh], epoch: newer, lastSeq: 1), atMilliseconds: t0),
            []
        )
        XCTAssertEqual(reducer.phase, .live)
    }

    /// While reconnecting, a "not live" snapshot of a newer epoch is an end (the fresh
    /// assistant ended too), and the call's own end is final.
    func testAReconnectingCallEnds() {
        var snapshotEnded = Frames.liveReducer()
        _ = snapshotEnded.apply(Frames.ended(seq: 2, reason: .agentError), atMilliseconds: t0)
        snapshotEnded.reconnected()
        XCTAssertEqual(
            snapshotEnded.apply(Frames.snapshot([], epoch: newer, lastSeq: 4, live: false), atMilliseconds: t0),
            [.fetchFinal(afterMilliseconds: 2000)]
        )
        XCTAssertEqual(snapshotEnded.phase, .ended(.callEnded))

        var callEnded = Frames.liveReducer()
        _ = callEnded.apply(Frames.ended(seq: 2, reason: .agentError), atMilliseconds: t0)
        XCTAssertEqual(callEnded.callEnded(), [.fetchFinal(afterMilliseconds: 2000)])
        XCTAssertEqual(callEnded.phase, .ended(.callEnded))
    }

    /// ⚠️ A "NOT LIVE" SNAPSHOT DOES NOT SAY WHY, so the end it causes is undone by a newer
    /// epoch (only `agent_error` is followed by one), and the fetch it started is dropped.
    func testAnEndedSnapshotIsUndoneByANewerEpoch() {
        var reducer = TranscriptReducer(callId: "call_1")
        XCTAssertEqual(
            reducer.apply(Frames.snapshot([Frames.greeting], lastSeq: 3, live: false), atMilliseconds: t0),
            [.fetchFinal(afterMilliseconds: 2000)]
        )
        XCTAssertEqual(reducer.phase, .ended(.callEnded))

        _ = reducer.apply(Frames.live(Frames.segment("s4", index: 3, seq: 4)), atMilliseconds: t0)
        XCTAssertEqual(reducer.phase, .ended(.callEnded), "a line of the ended epoch")
        _ = reducer.apply(Frames.live(Frames.segment("n1", index: 0, seq: 1, epoch: newer)), atMilliseconds: t0)

        XCTAssertEqual(reducer.phase, .live)
        XCTAssertEqual(reducer.finalTranscript, .notRequested)
        XCTAssertEqual(reducer.finalFetched(.success("too early")), [], "the fetch it started is not wanted")
    }

    /// A "not live" snapshot with no epoch names none to compare, so any line undoes it.
    func testAnEndedSnapshotWithNoEpochIsUndoneByAnyLine() {
        var reducer = TranscriptReducer(callId: "call_1")
        _ = reducer.apply(Frames.snapshot([], epoch: nil, lastSeq: nil, live: false), atMilliseconds: t0)

        _ = reducer.apply(Frames.live(Frames.greeting), atMilliseconds: t0)

        XCTAssertEqual(reducer.phase, .live)
    }
}
