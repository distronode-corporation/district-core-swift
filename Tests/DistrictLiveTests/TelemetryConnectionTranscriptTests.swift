@testable import DistrictLive
import DistrictModel
import Foundation
import XCTest

/// The connection's transcript ops: what is sent on every open, and what a subscribe,
/// an unsubscribe and a resubscribe send while open and while not.
final class TelemetryConnectionTranscriptTests: TelemetryConnectionTestCase {
    private let mode = #"{"op":"socket.mode","v":1,"broadcast":false}"#

    private func subscribe(_ callId: String) -> String {
        #"{"op":"transcript.subscribe","v":1,"callId":"\#(callId)"}"#
    }

    private func unsubscribe(_ callId: String) -> String {
        #"{"op":"transcript.unsubscribe","v":1,"callId":"\#(callId)"}"#
    }

    /// The commands an open sends after the three every open emits.
    private func sends(_ commands: [TelemetryConnectionCommand]) -> [String] {
        commands.compactMap {
            guard case let .send(text, _) = $0 else { return nil }
            return text
        }
    }

    private func open(_ connection: inout TelemetryConnection, attempt: Int, at now: Int64) -> [String] {
        sends(connection.handle(
            .opened(selectedSubprotocol: "distronode.telemetry.v1", attempt: attempt),
            atMilliseconds: now,
            jitter: 0
        ))
    }

    // MARK: - On open

    /// ⛔ THE PHONE'S SOCKET: `socket.mode` FIRST, then every subscription, on the first open.
    func testAnOpenSendsTheModeThenEverySubscriptionInCallIdOrder() {
        var connection = TelemetryConnection(workspaceId: "ws_1", broadcast: false)
        XCTAssertFalse(connection.broadcast)
        _ = connection.handle(.subscribeTranscript(callId: "call_b"), atMilliseconds: t0, jitter: 0)
        _ = connection.handle(.subscribeTranscript(callId: "call_a"), atMilliseconds: t0, jitter: 0)
        _ = connection.handle(.start, atMilliseconds: t0, jitter: 0)
        _ = connection.handle(.minted(.success(grant()), attempt: 1), atMilliseconds: t0, jitter: 0)

        let commands = connection.handle(
            .opened(selectedSubprotocol: "distronode.telemetry.v1", attempt: 1),
            atMilliseconds: t0,
            jitter: 0
        )

        XCTAssertEqual(commands, [
            .emit(.connected),
            .schedule(.renewal, afterMilliseconds: lifetime - 60000, attempt: 1),
            .schedule(.silence, afterMilliseconds: 90000, attempt: 1),
            .send(mode, attempt: 1),
            .send(subscribe("call_a"), attempt: 1),
            .send(subscribe("call_b"), attempt: 1),
        ])
    }

    /// ⛔ THE MAC'S SOCKET RINGS, SO IT NEVER SAYS `broadcast: false`: the default sends no
    /// mode at all, only the subscriptions.
    func testABroadcastingSocketSendsNoMode() {
        var connection = TelemetryConnection(workspaceId: "ws_1")
        XCTAssertTrue(connection.broadcast)
        _ = connection.handle(.subscribeTranscript(callId: "call_1"), atMilliseconds: t0, jitter: 0)
        _ = connection.handle(.start, atMilliseconds: t0, jitter: 0)
        _ = connection.handle(.minted(.success(grant()), attempt: 1), atMilliseconds: t0, jitter: 0)

        XCTAssertEqual(open(&connection, attempt: 1, at: t0), [subscribe("call_1")])
    }

    /// ⛔ SUBSCRIPTIONS ARE PER SOCKET, so the renewal's new socket gets them all again,
    /// without a mint (the credential still has time) and without a backoff.
    func testARenewalSendsTheModeAndTheSubscriptionsAgain() {
        var connection = TelemetryConnection(workspaceId: "ws_1", broadcast: false)
        _ = connection.handle(.subscribeTranscript(callId: "call_1"), atMilliseconds: t0, jitter: 0)
        _ = connection.handle(.start, atMilliseconds: t0, jitter: 0)
        _ = connection.handle(.minted(.success(grant()), attempt: 1), atMilliseconds: t0, jitter: 0)
        XCTAssertEqual(open(&connection, attempt: 1, at: t0), [mode, subscribe("call_1")])

        let renewAt = t0 + lifetime - 60000
        _ = connection.handle(.timerFired(.renewal, attempt: 1), atMilliseconds: renewAt, jitter: 0)
        XCTAssertEqual(
            connection.handle(.timerFired(.backoff, attempt: 1), atMilliseconds: renewAt, jitter: 0).first,
            .mint(attempt: 2),
            "the renewal replaces the credential"
        )
        _ = connection.handle(
            .minted(.success(grant(expiresIn: 2 * lifetime)), attempt: 2),
            atMilliseconds: renewAt,
            jitter: 0
        )

        XCTAssertEqual(open(&connection, attempt: 2, at: renewAt), [mode, subscribe("call_1")])
    }

    /// ⛔ 4401: A NEW CREDENTIAL, A NEW SOCKET, AND THE SUBSCRIPTIONS AGAIN.
    func testAReconnectAfterAnUnauthorizedCloseSubscribesAgain() {
        var connection = openConnection()
        _ = connection.handle(.subscribeTranscript(callId: "call_1"), atMilliseconds: t0, jitter: 0)
        _ = connection.handle(
            .received(.closed(code: 4401, reason: "Session expired"), attempt: 1),
            atMilliseconds: t0 + 1000,
            jitter: 0
        )
        let backoffEnds = t0 + 1000 + 1000
        XCTAssertEqual(
            connection.handle(.timerFired(.backoff, attempt: 1), atMilliseconds: backoffEnds, jitter: 0),
            [.mint(attempt: 2)]
        )
        _ = connection.handle(
            .minted(.success(grant(expiresIn: 2 * lifetime)), attempt: 2),
            atMilliseconds: backoffEnds,
            jitter: 0
        )

        XCTAssertEqual(open(&connection, attempt: 2, at: backoffEnds), [subscribe("call_1")])
    }

    // MARK: - While open

    func testASubscribeWhileOpenIsSentAtOnceAndOnlyOnce() {
        var connection = openConnection()

        XCTAssertEqual(
            connection.handle(.subscribeTranscript(callId: "call_1"), atMilliseconds: t0, jitter: 0),
            [.send(subscribe("call_1"), attempt: 1)]
        )
        XCTAssertEqual(
            connection.handle(.subscribeTranscript(callId: "call_1"), atMilliseconds: t0, jitter: 0),
            [],
            "a second subscribe to the same call sends nothing"
        )
        XCTAssertEqual(connection.transcriptSubscriptions, ["call_1"])
    }

    func testAnUnsubscribeIsSentAndForgotten() {
        var connection = openConnection()
        _ = connection.handle(.subscribeTranscript(callId: "call_1"), atMilliseconds: t0, jitter: 0)

        XCTAssertEqual(
            connection.handle(.unsubscribeTranscript(callId: "call_1"), atMilliseconds: t0, jitter: 0),
            [.send(unsubscribe("call_1"), attempt: 1)]
        )
        XCTAssertEqual(connection.transcriptSubscriptions, [])
        XCTAssertEqual(
            connection.handle(.unsubscribeTranscript(callId: "call_1"), atMilliseconds: t0, jitter: 0),
            [],
            "nothing to unsubscribe from"
        )
    }

    /// The gap heal: the same subscribe again, for a fresh snapshot. ⚠️ Only for a call
    /// that is subscribed, so a late heal after an unsubscribe cannot subscribe again.
    func testAResubscribeSendsTheSubscribeAgainOnlyForASubscribedCall() {
        var connection = openConnection()
        XCTAssertEqual(connection.handle(.resubscribeTranscript(callId: "call_1"), atMilliseconds: t0, jitter: 0), [])
        _ = connection.handle(.subscribeTranscript(callId: "call_1"), atMilliseconds: t0, jitter: 0)

        XCTAssertEqual(
            connection.handle(.resubscribeTranscript(callId: "call_1"), atMilliseconds: t0, jitter: 0),
            [.send(subscribe("call_1"), attempt: 1)]
        )
    }

    // MARK: - While not open

    /// While the socket is down nothing is sent: the next open sends what is subscribed
    /// then, and a call unsubscribed meanwhile is not among it.
    func testNothingIsSentWhileClosedAndTheNextOpenSendsTheCurrentSet() {
        var connection = TelemetryConnection(workspaceId: "ws_1")
        _ = connection.handle(.start, atMilliseconds: t0, jitter: 0)

        XCTAssertEqual(connection.handle(.subscribeTranscript(callId: "call_1"), atMilliseconds: t0, jitter: 0), [])
        XCTAssertEqual(connection.handle(.subscribeTranscript(callId: "call_2"), atMilliseconds: t0, jitter: 0), [])
        XCTAssertEqual(connection.handle(.unsubscribeTranscript(callId: "call_2"), atMilliseconds: t0, jitter: 0), [])
        XCTAssertEqual(connection.handle(.resubscribeTranscript(callId: "call_1"), atMilliseconds: t0, jitter: 0), [])
        _ = connection.handle(.minted(.success(grant()), attempt: 1), atMilliseconds: t0, jitter: 0)

        XCTAssertEqual(open(&connection, attempt: 1, at: t0), [subscribe("call_1")])
    }

    /// ⛔ HOSTILE CALL IDS ARE NEVER RECORDED: one the server would refuse would otherwise be
    /// re-sent on every open, earning a `bad_request` each time.
    func testACallIdTheServerWouldRefuseIsNeitherSentNorRecorded() {
        var connection = openConnection()
        for callId in ["", "call 1", #"x","op":"socket.mode"#, String(repeating: "x", count: 65)] {
            XCTAssertEqual(connection.handle(.subscribeTranscript(callId: callId), atMilliseconds: t0, jitter: 0), [])
        }
        XCTAssertEqual(connection.transcriptSubscriptions, [])
    }

    /// The ops are not events of the socket: none changes the phase, the attempt or the
    /// failure count, and a stopped connection keeps its set but sends nothing.
    func testTheOpsChangeNothingButTheSet() {
        var connection = openConnection()
        let phase = connection.phase
        _ = connection.handle(.subscribeTranscript(callId: "call_1"), atMilliseconds: t0, jitter: 0)
        XCTAssertEqual(connection.phase, phase)
        XCTAssertEqual(connection.attempt, 1)
        XCTAssertEqual(connection.failures, 0)

        _ = connection.handle(.stop, atMilliseconds: t0, jitter: 0)
        XCTAssertEqual(connection.handle(.resubscribeTranscript(callId: "call_1"), atMilliseconds: t0, jitter: 0), [])
        XCTAssertEqual(connection.handle(.subscribeTranscript(callId: "call_2"), atMilliseconds: t0, jitter: 0), [])
    }
}
