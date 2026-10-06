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
    /// bring it back.
    func testARetractedSegmentIsRemovedAndCannotComeBack() {
        var reducer = Frames.liveReducer()
        _ = reducer.apply(Frames.live(Frames.segment("s1", index: 0, seq: 1)), atMilliseconds: t0)
        _ = reducer.apply(Frames.live(Frames.segment("s2", index: 1, seq: 2)), atMilliseconds: t0)

        XCTAssertEqual(reducer.apply(Frames.retracted(["s1"], seq: 3, epoch: Frames.epoch), atMilliseconds: t0), [])
        XCTAssertEqual(reducer.lines.map(\.segmentId), ["s2"])

        _ = reducer.apply(Frames.live(Frames.segment("s1", index: 0, seq: 4, rev: 1)), atMilliseconds: t0)
        XCTAssertEqual(reducer.lines.map(\.segmentId), ["s2"], "a later revision of a retracted line")
        _ = reducer.apply(
            Frames.snapshot(
                [Frames.segment("s1", index: 0, seq: 1), Frames.segment("s2", index: 1, seq: 2)],
                lastSeq: 4
            ),
            atMilliseconds: t0
        )
        XCTAssertEqual(reducer.lines.map(\.segmentId), ["s2"], "a snapshot taken before the retraction")
    }

    /// The website's retraction carries no seq: it is applied, and nothing is counted.
    func testARetractionOfEverythingFromTheWebsiteClearsTheCall() {
        var reducer = Frames.liveReducer()
        _ = reducer.apply(Frames.live(Frames.segment("s1", index: 0, seq: 1)), atMilliseconds: t0)

        XCTAssertEqual(reducer.apply(Frames.retracted(all: true), atMilliseconds: t0), [])

        XCTAssertTrue(reducer.lines.isEmpty)
        _ = reducer.apply(Frames.live(Frames.segment("s1", index: 0, seq: 2, rev: 1)), atMilliseconds: t0)
        XCTAssertTrue(reducer.lines.isEmpty, "the cleared lines are tombstoned too")
        _ = reducer.apply(Frames.live(Frames.segment("s3", index: 2, seq: 3)), atMilliseconds: t0)
        XCTAssertEqual(reducer.lines.map(\.segmentId), ["s3"], "a new line after the retraction is shown")
    }

    /// ⚠️ THE v1 RETRACTION HAS NO EPOCH, so its seq is counted against the newest epoch:
    /// the counter then shows no gap where the retraction used a number.
    func testARetractionsSeqWithoutAnEpochCountsAgainstTheNewestEpoch() {
        var reducer = Frames.liveReducer()
        _ = reducer.apply(Frames.live(Frames.segment("s1", index: 0, seq: 1)), atMilliseconds: t0)
        _ = reducer.apply(Frames.retracted(["s1"], seq: 2), atMilliseconds: t0)

        XCTAssertEqual(reducer.apply(Frames.live(Frames.segment("s3", index: 1, seq: 3)), atMilliseconds: t0), [])
        XCTAssertEqual(reducer.gapCheck(atMilliseconds: t0 + 5000), [])
    }

    /// Before any frame there is no epoch to count against, and a seen retraction is still
    /// applied: dropping a line twice is harmless.
    func testARetractionIsAppliedWithNoEpochKnownAndWhenItsSeqWasSeen() {
        var reducer = TranscriptReducer(callId: "call_1")
        _ = reducer.apply(Frames.retracted(["s1"], seq: 1), atMilliseconds: t0)
        _ = reducer.apply(Frames.snapshot([Frames.segment("s1", index: 0, seq: 1)], lastSeq: 1), atMilliseconds: t0)
        XCTAssertTrue(reducer.lines.isEmpty)

        var seen = Frames.liveReducer()
        _ = seen.apply(Frames.live(Frames.segment("s1", index: 0, seq: 1)), atMilliseconds: t0)
        _ = seen.apply(Frames.retracted([], seq: 2, epoch: Frames.epoch), atMilliseconds: t0)
        _ = seen.apply(Frames.retracted(["s1"], seq: 2, epoch: Frames.epoch), atMilliseconds: t0)
        XCTAssertTrue(seen.lines.isEmpty)
    }

    // MARK: - The server's refusals

    func testRateLimitedWaitsAndSubscribesAgain() {
        var reducer = TranscriptReducer(callId: "call_1")

        XCTAssertEqual(
            reducer.apply(Frames.error(.rateLimited, retryAfterMs: 4500), atMilliseconds: t0),
            [.resubscribe(afterMilliseconds: 4500)]
        )
        XCTAssertEqual(
            reducer.apply(Frames.error(.rateLimited, op: nil), atMilliseconds: t0),
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
    /// the call): an ended transcript stays ended, with its lines.
    func testNotLiveAfterTheEndChangesNothing() {
        var reducer = Frames.liveReducer()
        _ = reducer.callEnded()

        XCTAssertEqual(reducer.apply(Frames.error(.notLive), atMilliseconds: t0), [])
        XCTAssertEqual(reducer.phase, .ended(.callEnded))
    }

    /// ⛔ A REFUSED UNSUBSCRIBE NEEDS NO ANSWER, and re-subscribing after a rate-limited
    /// one would undo it.
    func testARefusalOfAnotherOpIsIgnored() {
        var reducer = Frames.liveReducer()

        XCTAssertEqual(
            reducer.apply(
                Frames.error(.rateLimited, op: "transcript.unsubscribe", retryAfterMs: 10),
                atMilliseconds: t0
            ),
            []
        )
        XCTAssertEqual(reducer.apply(Frames.error(.badRequest, op: "socket.mode"), atMilliseconds: t0), [])
        XCTAssertEqual(reducer.phase, .live)
    }

    /// A refusal that arrives while a snapshot is still arriving is held with the live
    /// frames and applied after it.
    func testARefusalBehindAHalfSnapshotIsAppliedAfterIt() {
        var reducer = TranscriptReducer(callId: "call_1")
        _ = reducer.apply(Frames.snapshot([], lastSeq: 0, more: true), atMilliseconds: t0)
        XCTAssertEqual(reducer.apply(Frames.error(.rateLimited, retryAfterMs: 7), atMilliseconds: t0), [])

        XCTAssertEqual(
            reducer.apply(Frames.snapshot([], lastSeq: 0, part: 1), atMilliseconds: t0),
            [.resubscribe(afterMilliseconds: 7)]
        )
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
