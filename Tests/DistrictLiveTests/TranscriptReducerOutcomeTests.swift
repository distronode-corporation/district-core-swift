@testable import DistrictLive
import DistrictModel
import Foundation
import XCTest

/// The reducer's other outcomes: retractions, the server's refusals, and fetching the
/// full transcript after the end.
final class TranscriptReducerOutcomeTests: XCTestCase {
    private let t0 = Frames.t0

    // MARK: - Retraction

    /// ⛔ A RETRACTED LINE STAYS GONE: neither a late copy nor a later revision of it can
    /// bring it back. The assistant's retraction carries `epoch` with `seq` and is counted.
    func testARetractedSegmentIsRemovedAndCannotComeBack() {
        var reducer = Frames.liveReducer()
        _ = reducer.apply(Frames.live(Frames.segment("s2", index: 1, seq: 2)), atMilliseconds: t0)
        _ = reducer.apply(Frames.live(Frames.segment("s3", index: 2, seq: 3)), atMilliseconds: t0)

        XCTAssertEqual(reducer.apply(Frames.retracted(["s2"], seq: 4, epoch: Frames.epoch), atMilliseconds: t0), [])
        XCTAssertEqual(reducer.lines.map(\.segmentId), ["item_a1", "s3"])

        _ = reducer.apply(Frames.live(Frames.segment("s2", index: 1, seq: 5, rev: 1)), atMilliseconds: t0)
        XCTAssertEqual(reducer.lines.map(\.segmentId), ["item_a1", "s3"], "a later revision of a retracted line")
        XCTAssertEqual(reducer.gapCheck(atMilliseconds: t0 + 5000), [], "the retraction's seq left no gap")
    }

    /// The website's retraction carries neither `epoch` nor `seq` (§4.12 Q2): it bypasses
    /// the counter, and is applied however often it arrives.
    func testARetractionOfEverythingFromTheWebsiteClearsTheCall() {
        var reducer = Frames.liveReducer()
        _ = reducer.apply(Frames.live(Frames.segment("s2", index: 1, seq: 2)), atMilliseconds: t0)

        XCTAssertEqual(reducer.apply(Frames.retracted(all: true), atMilliseconds: t0), [])
        XCTAssertEqual(reducer.apply(Frames.retracted(all: true), atMilliseconds: t0), [])

        XCTAssertTrue(reducer.lines.isEmpty)
        _ = reducer.apply(Frames.live(Frames.segment("s2", index: 1, seq: 3, rev: 1)), atMilliseconds: t0)
        XCTAssertTrue(reducer.lines.isEmpty, "the cleared lines are tombstoned too")
        XCTAssertEqual(reducer.apply(Frames.live(Frames.segment("s4", index: 3, seq: 4)), atMilliseconds: t0), [])
        XCTAssertEqual(reducer.lines.map(\.segmentId), ["s4"], "a new line after the retraction is shown")
    }

    /// Hostile input: a `seq` without its `epoch` (or the other way round) cannot be
    /// counted, since a seq belongs to one epoch. The lines still come off; the seq it used
    /// then shows as a gap, which a snapshot heals.
    func testARetractionWithHalfACounterIsAppliedButNotCounted() {
        var reducer = Frames.liveReducer()
        XCTAssertEqual(reducer.apply(Frames.retracted(["item_a1"], seq: 2), atMilliseconds: t0), [])
        XCTAssertEqual(reducer.apply(Frames.retracted(["nothing"], epoch: Frames.epoch), atMilliseconds: t0), [])
        XCTAssertTrue(reducer.lines.isEmpty)

        XCTAssertEqual(
            reducer.apply(Frames.live(Frames.segment("s3", index: 2, seq: 3)), atMilliseconds: t0),
            [.checkGap(afterMilliseconds: 2000)]
        )
    }

    /// A retraction whose seq was seen is still applied: dropping a line twice is harmless.
    func testARetractionIsAppliedWhenItsSeqWasSeen() {
        var reducer = Frames.liveReducer()
        _ = reducer.apply(Frames.retracted([], seq: 2, epoch: Frames.epoch), atMilliseconds: t0)

        _ = reducer.apply(Frames.retracted(["item_a1"], seq: 2, epoch: Frames.epoch), atMilliseconds: t0)

        XCTAssertTrue(reducer.lines.isEmpty)
    }

    // MARK: - The server's refusals

    /// ⚠️ A RATE-LIMITED SUBSCRIBE BRINGS NO SNAPSHOT, so it is sent again after the wait,
    /// and that one is the heal in flight.
    func testRateLimitedWaitsAndSubscribesAgain() {
        var reducer = TranscriptReducer(callId: "call_1")

        XCTAssertEqual(
            reducer.apply(Frames.error(.rateLimited, retryAfterMs: 4500), atMilliseconds: t0),
            [.resubscribe(afterMilliseconds: 4500)]
        )
        XCTAssertEqual(
            reducer.apply(Frames.error(.rateLimited), atMilliseconds: t0),
            [.resubscribe(afterMilliseconds: 2000)]
        )
        XCTAssertEqual(reducer.phase, .subscribing)
    }

    /// ⛔ NOT LIVE (OR ANY OTHER REFUSAL): the client falls back to the transcript after the
    /// call and stops asking.
    func testEveryOtherRefusalMakesTheLiveTranscriptUnavailable() {
        let codes: [TranscriptErrorCode] = [
            .notLive, .badRequest, .unsupportedVersion, .forbiddenRole, .tooManySubscriptions, .other("teapot"),
        ]
        for code in codes {
            var reducer = TranscriptReducer(callId: "call_1")
            XCTAssertEqual(reducer.apply(Frames.error(code), atMilliseconds: t0), [.unsubscribe], code.wire)
            XCTAssertEqual(reducer.phase, .unavailable(code), code.wire)
        }
    }

    /// ⚠️ `not_live` ALSO ANSWERS A SUBSCRIBE TWO MINUTES AFTER THE END (a reconnect after
    /// the call): an ended transcript stays ended, with its lines. One waiting for a fresh
    /// assistant that never came is unavailable.
    func testNotLiveAfterTheEndChangesNothingAndWhileReconnectingGivesUp() {
        var ended = Frames.liveReducer()
        _ = ended.callEnded()
        XCTAssertEqual(ended.apply(Frames.error(.notLive), atMilliseconds: t0), [])
        XCTAssertEqual(ended.phase, .ended(.callEnded))

        var reconnecting = Frames.liveReducer()
        _ = reconnecting.apply(Frames.ended(seq: 2, reason: .agentError), atMilliseconds: t0)
        reconnecting.reconnected()
        XCTAssertEqual(reconnecting.apply(Frames.error(.notLive), atMilliseconds: t0), [.unsubscribe])
        XCTAssertEqual(reconnecting.phase, .unavailable(.notLive))
    }

    /// ⛔ §4.12 Q8: `op` ECHOES THE OP SENT, so only an error whose `op` is exactly
    /// `transcript.subscribe` is about the subscribe. A refused unsubscribe needs no answer
    /// (re-subscribing after it would undo it), and a frame with no op is no op of ours.
    func testARefusalOfAnythingButTheSubscribeIsIgnored() {
        var reducer = Frames.liveReducer()

        XCTAssertEqual(
            reducer.apply(
                Frames.error(.rateLimited, op: "transcript.unsubscribe", retryAfterMs: 10),
                atMilliseconds: t0
            ),
            []
        )
        XCTAssertEqual(reducer.apply(Frames.error(.badRequest, op: "socket.mode"), atMilliseconds: t0), [])
        XCTAssertEqual(reducer.apply(Frames.error(.notLive, op: nil), atMilliseconds: t0), [])
        XCTAssertEqual(reducer.apply(Frames.error(.notLive, op: "Transcript.Subscribe"), atMilliseconds: t0), [])
        XCTAssertEqual(reducer.phase, .live)
    }

    // MARK: - Call-status signals

    /// ⛔ §4.12 Q4: `not_live` IS FINAL FOR THAT SUBSCRIBE. Only a call-status change
    /// subscribes again, once per change; a repeated status asks for nothing, and so does
    /// one while the transcript is anything but `not_live`.
    func testOnlyAStatusChangeSubscribesAgainAfterNotLive() {
        var reducer = TranscriptReducer(callId: "call_1")
        XCTAssertEqual(reducer.callStatusChanged(to: "ringing"), [], "subscribing: nothing to do")
        _ = reducer.apply(Frames.error(.notLive), atMilliseconds: t0)

        XCTAssertEqual(reducer.callStatusChanged(to: "ringing"), [], "the same status is no signal")
        XCTAssertEqual(reducer.phase, .unavailable(.notLive))
        XCTAssertEqual(reducer.callStatusChanged(to: "in-progress"), [.subscribe])
        XCTAssertEqual(reducer.phase, .subscribing)
        XCTAssertEqual(reducer.gapCheck(atMilliseconds: t0), [])

        _ = reducer.apply(Frames.snapshot([Frames.greeting], lastSeq: 1), atMilliseconds: t0)
        XCTAssertEqual(reducer.phase, .live)
        XCTAssertEqual(reducer.callStatusChanged(to: "on-hold"), [], "live: nothing to do")
    }

    /// The first status reported is a signal too, when the subscribe already ended in
    /// `not_live`; another refusal is not undone by any status.
    func testTheFirstStatusIsASignalAndOtherRefusalsStay() {
        var notLive = TranscriptReducer(callId: "call_1")
        _ = notLive.apply(Frames.error(.notLive), atMilliseconds: t0)
        XCTAssertEqual(notLive.callStatusChanged(to: "in-progress"), [.subscribe])

        var refused = TranscriptReducer(callId: "call_1")
        _ = refused.apply(Frames.error(.forbiddenRole), atMilliseconds: t0)
        XCTAssertEqual(refused.callStatusChanged(to: "in-progress"), [])
        XCTAssertEqual(refused.phase, .unavailable(.forbiddenRole))
    }

    /// ⚠️ THE CALL'S END CHANGES NOTHING FOR A CALL WITH NO LIVE TRANSCRIPT: the screen
    /// already offers the transcript after the call.
    func testTheCallsEndLeavesAnUnavailableTranscriptAlone() {
        var reducer = TranscriptReducer(callId: "call_1")
        _ = reducer.apply(Frames.error(.notLive), atMilliseconds: t0)

        XCTAssertEqual(reducer.callEnded(), [])
        XCTAssertEqual(reducer.phase, .unavailable(.notLive))
        XCTAssertEqual(reducer.finalTranscript, .notRequested)
    }

    // MARK: - The full transcript

    func testTheFetchBacksOffFromTwoSecondsToThirty() {
        let delays = (0 ... 9).map(TranscriptReducer.finalFetchDelayMilliseconds(attempt:))
        XCTAssertEqual(delays, [2000, 2000, 4000, 8000, 16000, 30000, 30000, 30000, 30000, 30000])
        XCTAssertEqual(TranscriptReducer.finalFetchDelayMilliseconds(attempt: .max), 30000)
    }

    /// ⛔ STILL EMPTY AFTER EVERY ATTEMPT IS `empty`, NOT A FAILURE: nothing was said, or the
    /// transcript was never written.
    func testAnEmptyTranscriptIsRetriedThenReportedEmpty() {
        var reducer = Frames.liveReducer()
        _ = reducer.callEnded()
        for attempt in 1 ..< TranscriptReducer.finalFetchAttempts {
            XCTAssertEqual(
                reducer.finalFetched(.success("")),
                [.fetchFinal(afterMilliseconds: TranscriptReducer.finalFetchDelayMilliseconds(attempt: attempt + 1))]
            )
        }

        XCTAssertEqual(reducer.finalFetched(.success("")), [.unsubscribe])
        XCTAssertEqual(reducer.finalTranscript, .empty)
    }

    func testATransientFailureIsRetriedAndAFinalOneIsNot() {
        var reducer = Frames.liveReducer()
        _ = reducer.callEnded()

        XCTAssertEqual(
            reducer.finalFetched(.failure(.http(status: 503, message: nil))),
            [.fetchFinal(afterMilliseconds: 4000)]
        )
        XCTAssertEqual(reducer.finalFetched(.failure(.http(status: 403, message: nil))), [.unsubscribe])
        XCTAssertEqual(reducer.finalTranscript, .failed(.http(status: 403, message: nil)))
    }

    func testATransientFailureOnTheLastAttemptIsReportedAsTheFailure() {
        var reducer = Frames.liveReducer()
        _ = reducer.callEnded()
        for _ in 1 ..< TranscriptReducer.finalFetchAttempts {
            _ = reducer.finalFetched(.failure(.transport("offline")))
        }

        XCTAssertEqual(reducer.finalFetched(.failure(.transport("offline"))), [.unsubscribe])
        XCTAssertEqual(reducer.finalTranscript, .failed(.transport("offline")))
    }

    func testNothingIsFetchedBeforeTheEnd() {
        var reducer = Frames.liveReducer()

        XCTAssertEqual(reducer.finalFetched(.success("early")), [])
        XCTAssertEqual(reducer.finalTranscript, .notRequested)
    }
}
