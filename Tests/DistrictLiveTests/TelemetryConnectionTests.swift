@testable import DistrictLive
import DistrictModel
import Foundation
import XCTest

/// The fixtures both halves of the connection's tests share.
///
/// ⚠️ A BASE CLASS RATHER THAN ONE TEST CLASS, ONLY FOR SwiftLint's 300-LINE
/// `type_body_length`; it declares no tests of its own.
class TelemetryConnectionTestCase: XCTestCase {
    let t0: Int64 = 1_790_433_000_000
    let lifetime: Int64 = 900_000
    let url = URL(string: "wss://telemetry.example.com/ws/telemetry?workspaceId=ws_1")!
    let offer = ["distronode.telemetry.v1", "distronode.token.a.b.c"]

    func grant(
        expiresIn: Int64? = nil,
        token: String = "a.b.c",
        wsUrl: String? = "wss://telemetry.example.com/ws/telemetry"
    ) -> TelemetryTokenResponse {
        .grant(token: token, expiresAt: t0 + (expiresIn ?? lifetime), wsUrl: wsUrl)
    }

    func envelopeJSON(workspace: String = "ws_1") -> String {
        #"{"workspaceId":"\#(workspace)","callId":"call_1","eventType":"call_ended","#
            + #""data":{"status":"completed"},"timestamp":"t"}"#
    }

    /// A connection with its socket open at `t0`, attempt 1.
    func openConnection(expiresIn: Int64? = nil) -> TelemetryConnection {
        var connection = TelemetryConnection(workspaceId: "ws_1")
        _ = connection.handle(.start, atMilliseconds: t0, jitter: 0)
        _ = connection.handle(.minted(.success(grant(expiresIn: expiresIn)), attempt: 1), atMilliseconds: t0, jitter: 0)
        _ = connection.handle(
            .opened(selectedSubprotocol: "distronode.telemetry.v1", attempt: 1),
            atMilliseconds: t0,
            jitter: 0
        )
        return connection
    }
}

/// The connection's rules, as command lists, on an injected time: connecting and
/// minting.
final class TelemetryConnectionTests: TelemetryConnectionTestCase {
    // MARK: - Connecting

    func testStartMintsThenOpensWithTheVersionAndTheCredentialThenReportsConnected() {
        var connection = TelemetryConnection(workspaceId: "ws_1")
        XCTAssertEqual(connection.phase, .idle)

        XCTAssertEqual(connection.handle(.start, atMilliseconds: t0, jitter: 0), [.mint(attempt: 1)])
        XCTAssertEqual(connection.phase, .minting)

        XCTAssertEqual(
            connection.handle(.minted(.success(grant()), attempt: 1), atMilliseconds: t0, jitter: 0),
            [
                .open(url: url, subprotocols: offer, attempt: 1),
                .schedule(.connect, afterMilliseconds: 15000, attempt: 1),
            ]
        )
        XCTAssertEqual(connection.phase, .connecting(expiresAt: t0 + lifetime))

        XCTAssertEqual(
            connection.handle(
                .opened(selectedSubprotocol: "distronode.telemetry.v1", attempt: 1),
                atMilliseconds: t0,
                jitter: 0
            ),
            [
                .emit(.connected),
                .schedule(.renewal, afterMilliseconds: lifetime - 60000, attempt: 1),
                .schedule(.silence, afterMilliseconds: 90000, attempt: 1),
            ]
        )
        XCTAssertEqual(connection.phase, .open(openedAt: t0, lastHeardAt: t0))
        XCTAssertEqual(connection.workspaceId, "ws_1")
    }

    func testASecondStartDoesNothing() {
        var connection = openConnection()
        XCTAssertEqual(connection.handle(.start, atMilliseconds: t0, jitter: 0), [])
    }

    /// ⛔ THE SERVER MUST SELECT THE VERSION. Anything else, including the credential
    /// echoed back, closes the socket and ends the connection.
    func testAServerThatSelectsAnythingButTheVersionEndsTheConnection() {
        for selected in [nil, "distronode.token.a.b.c", "distronode.telemetry.v2"] {
            var connection = TelemetryConnection(workspaceId: "ws_1")
            _ = connection.handle(.start, atMilliseconds: t0, jitter: 0)
            _ = connection.handle(.minted(.success(grant()), attempt: 1), atMilliseconds: t0, jitter: 0)

            XCTAssertEqual(
                connection.handle(.opened(selectedSubprotocol: selected, attempt: 1), atMilliseconds: t0, jitter: 0),
                [.close(attempt: 1), .cancelTimers, .emit(.ended(.protocolMismatch)), .finish]
            )
            XCTAssertEqual(connection.phase, .ended)
        }
    }

    func testAnUnpresentableCredentialEndsTheConnection() {
        var connection = TelemetryConnection(workspaceId: "ws_1")
        _ = connection.handle(.start, atMilliseconds: t0, jitter: 0)

        XCTAssertEqual(
            connection.handle(.minted(.success(grant(token: "a b")), attempt: 1), atMilliseconds: t0, jitter: 0),
            [.cancelTimers, .emit(.ended(.invalidGrant)), .finish]
        )
    }

    func testAnUnusableAddressEndsTheConnection() {
        for (wsUrl, error) in [(nil, TelemetryEndpointError.missing), ("ws://telemetry.example.com/ws", .insecure)] {
            var connection = TelemetryConnection(workspaceId: "ws_1")
            _ = connection.handle(.start, atMilliseconds: t0, jitter: 0)

            XCTAssertEqual(
                connection.handle(.minted(.success(grant(wsUrl: wsUrl)), attempt: 1), atMilliseconds: t0, jitter: 0),
                [.cancelTimers, .emit(.ended(.endpoint(error))), .finish]
            )
        }
    }

    // MARK: - Mint failures

    func testATransientMintFailureBacksOffAndAFinalOneEnds() {
        for error in [
            ApiError.transport("offline"),
            .http(status: 503, message: nil),
            .http(status: 429, message: nil),
            .http(status: 401, message: nil),
        ] {
            var connection = TelemetryConnection(workspaceId: "ws_1")
            _ = connection.handle(.start, atMilliseconds: t0, jitter: 0)
            XCTAssertEqual(
                connection.handle(.minted(.failure(error), attempt: 1), atMilliseconds: t0, jitter: 0),
                [
                    .emit(.reconnecting(delayMilliseconds: 1000, cause: .mint(error))),
                    .schedule(.backoff, afterMilliseconds: 1000, attempt: 1),
                ],
                "\(error)"
            )
            XCTAssertEqual(connection.phase, .waiting)
        }
        for error in [
            ApiError.http(status: 403, message: "Access denied"),
            .http(status: 400, message: nil),
            .decoding("x"),
        ] {
            var connection = TelemetryConnection(workspaceId: "ws_1")
            _ = connection.handle(.start, atMilliseconds: t0, jitter: 0)
            XCTAssertEqual(
                connection.handle(.minted(.failure(error), attempt: 1), atMilliseconds: t0, jitter: 0),
                [.cancelTimers, .emit(.ended(.mint(error))), .finish],
                "\(error)"
            )
        }
    }

    func testTheBackoffTimerStartsTheNextAttemptAndFailuresAccumulate() {
        var connection = TelemetryConnection(workspaceId: "ws_1")
        _ = connection.handle(.start, atMilliseconds: t0, jitter: 0)
        _ = connection.handle(.minted(.failure(.transport("x")), attempt: 1), atMilliseconds: t0, jitter: 1)

        XCTAssertEqual(
            connection.handle(.timerFired(.backoff, attempt: 1), atMilliseconds: t0, jitter: 0),
            [.mint(attempt: 2)]
        )
        XCTAssertEqual(
            connection.handle(.minted(.failure(.transport("x")), attempt: 2), atMilliseconds: t0, jitter: 1),
            [
                .emit(.reconnecting(delayMilliseconds: 4000, cause: .mint(.transport("x")))),
                .schedule(.backoff, afterMilliseconds: 4000, attempt: 2),
            ]
        )
        XCTAssertEqual(connection.failures, 2)
    }

    // MARK: - Failures opening

    func testAFailedHandshakeBacksOff() {
        var connection = TelemetryConnection(workspaceId: "ws_1")
        _ = connection.handle(.start, atMilliseconds: t0, jitter: 0)
        _ = connection.handle(.minted(.success(grant()), attempt: 1), atMilliseconds: t0, jitter: 0)

        XCTAssertEqual(
            connection.handle(.openFailed(reason: "refused", attempt: 1), atMilliseconds: t0, jitter: 0),
            [
                .emit(.reconnecting(delayMilliseconds: 1000, cause: .network("refused"))),
                .schedule(.backoff, afterMilliseconds: 1000, attempt: 1),
            ]
        )
    }

    /// ⛔ A RECONNECT REUSES A CREDENTIAL WITH MORE THAN THE LEAD LEFT, and mints when
    /// it has less.
    func testAReconnectReusesALiveCredentialAndMintsForAnExpiringOne() {
        var connection = TelemetryConnection(workspaceId: "ws_1")
        _ = connection.handle(.start, atMilliseconds: t0, jitter: 0)
        _ = connection.handle(.minted(.success(grant()), attempt: 1), atMilliseconds: t0, jitter: 0)
        _ = connection.handle(.openFailed(reason: "refused", attempt: 1), atMilliseconds: t0, jitter: 0)

        XCTAssertEqual(
            connection.handle(.timerFired(.backoff, attempt: 1), atMilliseconds: t0 + 1000, jitter: 0),
            [
                .open(url: url, subprotocols: offer, attempt: 2),
                .schedule(.connect, afterMilliseconds: 15000, attempt: 2),
            ]
        )
        _ = connection.handle(.openFailed(reason: "refused", attempt: 2), atMilliseconds: t0, jitter: 0)
        let nearExpiry = t0 + lifetime - 60000
        XCTAssertEqual(
            connection.handle(.timerFired(.backoff, attempt: 2), atMilliseconds: nearExpiry, jitter: 0),
            [.mint(attempt: 3)]
        )
    }

    func testAHandshakeThatOutlivesItsDeadlineIsClosedAndRetried() {
        var connection = TelemetryConnection(workspaceId: "ws_1")
        _ = connection.handle(.start, atMilliseconds: t0, jitter: 0)
        _ = connection.handle(.minted(.success(grant()), attempt: 1), atMilliseconds: t0, jitter: 0)

        XCTAssertEqual(
            connection.handle(.timerFired(.connect, attempt: 1), atMilliseconds: t0 + 15000, jitter: 0),
            [
                .close(attempt: 1),
                .emit(.reconnecting(delayMilliseconds: 1000, cause: .connectTimedOut)),
                .schedule(.backoff, afterMilliseconds: 1000, attempt: 1),
            ]
        )
        // ⛔ The socket that finishes its handshake afterwards is closed, not adopted.
        XCTAssertEqual(
            connection.handle(
                .opened(selectedSubprotocol: "distronode.telemetry.v1", attempt: 1),
                atMilliseconds: t0 + 16000,
                jitter: 0
            ),
            [.close(attempt: 1)]
        )
    }
}

/// The connection's rules once a socket is open: messages, closes, timers, stale
/// results and stopping.
final class TelemetryConnectionLifecycleTests: TelemetryConnectionTestCase {
    // MARK: - Messages

    func testAnEnvelopeForThisWorkspaceIsDeliveredAndAnythingElseIsDiscarded() throws {
        var connection = openConnection()
        let envelope = try JSONDecoder().decode(TelemetryEnvelope.self, from: Data(envelopeJSON().utf8))

        XCTAssertEqual(
            connection.handle(.received(.text(envelopeJSON()), attempt: 1), atMilliseconds: t0 + 1, jitter: 0),
            [.emit(.event(envelope))]
        )
        XCTAssertEqual(
            connection
                .handle(.received(.binary(Data(envelopeJSON().utf8)), attempt: 1), atMilliseconds: t0 + 2, jitter: 0),
            [.emit(.event(envelope))]
        )
        XCTAssertEqual(
            connection.handle(.received(.text("not json"), attempt: 1), atMilliseconds: t0 + 3, jitter: 0),
            [.emit(.discarded)]
        )
        XCTAssertEqual(
            connection.handle(
                .received(.text(envelopeJSON(workspace: "ws_other")), attempt: 1),
                atMilliseconds: t0 + 4,
                jitter: 0
            ),
            [.emit(.discarded)]
        )
        XCTAssertEqual(connection.handle(.received(.heartbeat, attempt: 1), atMilliseconds: t0 + 5, jitter: 0), [])
        XCTAssertEqual(connection.phase, .open(openedAt: t0, lastHeardAt: t0 + 5))
    }

    // MARK: - Closes

    func testA4401MintsAgainAndA4403Ends() {
        var refused = openConnection()
        XCTAssertEqual(
            refused.handle(
                .received(.closed(code: 4401, reason: "expired"), attempt: 1),
                atMilliseconds: t0 + 1000,
                jitter: 0
            ),
            [
                .close(attempt: 1),
                .emit(.reconnecting(delayMilliseconds: 1000, cause: .unauthorized(reason: "expired"))),
                .schedule(.backoff, afterMilliseconds: 1000, attempt: 1),
            ]
        )
        // ⛔ The refused credential is not reused, though it has time left.
        XCTAssertEqual(
            refused.handle(.timerFired(.backoff, attempt: 1), atMilliseconds: t0 + 2000, jitter: 0),
            [.mint(attempt: 2)]
        )

        var forbidden = openConnection()
        XCTAssertEqual(
            forbidden.handle(
                .received(.closed(code: 4403, reason: "not a member"), attempt: 1),
                atMilliseconds: t0,
                jitter: 0
            ),
            [.close(attempt: 1), .cancelTimers, .emit(.ended(.forbidden(reason: "not a member"))), .finish]
        )
    }

    func testAnyOtherCloseBacksOffAndAStableSocketResetsTheCount() {
        var connection = openConnection()
        // A socket that stayed up for 30 s counts as established: the count resets
        // to zero and this failure is the first.
        XCTAssertEqual(
            connection.handle(
                .received(.closed(code: 1001, reason: "restart"), attempt: 1),
                atMilliseconds: t0 + 30000,
                jitter: 0
            ),
            [
                .close(attempt: 1),
                .emit(.reconnecting(delayMilliseconds: 1000, cause: .closed(code: 1001, reason: "restart"))),
                .schedule(.backoff, afterMilliseconds: 1000, attempt: 1),
            ]
        )
        XCTAssertEqual(connection.failures, 1)
    }

    func testABrokenSocketBacksOff() {
        var connection = openConnection()
        XCTAssertEqual(
            connection.handle(.broken(reason: "reset", attempt: 1), atMilliseconds: t0 + 10, jitter: 0),
            [
                .emit(.reconnecting(delayMilliseconds: 1000, cause: .network("reset"))),
                .schedule(.backoff, afterMilliseconds: 1000, attempt: 1),
            ]
        )
    }

    // MARK: - Timers

    /// ⛔ A ROUTINE RENEWAL GOES AGAIN AT ONCE, ON A FRESH CREDENTIAL.
    func testTheRenewalReplacesAnEstablishedSocketImmediatelyOnAFreshCredential() {
        var connection = openConnection()
        let due = t0 + lifetime - 60000

        XCTAssertEqual(
            connection.handle(.timerFired(.renewal, attempt: 1), atMilliseconds: due, jitter: 0),
            [
                .close(attempt: 1),
                .emit(.reconnecting(delayMilliseconds: 0, cause: .renewal)),
                .schedule(.backoff, afterMilliseconds: 0, attempt: 1),
            ]
        )
        XCTAssertEqual(connection.failures, 0)
        XCTAssertEqual(
            connection.handle(.timerFired(.backoff, attempt: 1), atMilliseconds: due, jitter: 0),
            [.mint(attempt: 2)]
        )
    }

    /// ⚠️ A RENEWAL BEFORE THE SOCKET WAS ESTABLISHED (a credential that arrived nearly
    /// spent) COUNTS AS A FAILURE, so a server handing out short credentials cannot
    /// make the client spin.
    func testARenewalOfAnUnestablishedSocketBacksOff() {
        var connection = openConnection(expiresIn: 30000)
        XCTAssertEqual(
            connection.handle(.timerFired(.renewal, attempt: 1), atMilliseconds: t0 + 5000, jitter: 0),
            [
                .close(attempt: 1),
                .emit(.reconnecting(delayMilliseconds: 1000, cause: .renewal)),
                .schedule(.backoff, afterMilliseconds: 1000, attempt: 1),
            ]
        )
    }

    func testTheSilenceWatchdogReArmsForWhatIsLeftAndFiresAfterNinetyQuietSeconds() {
        var connection = openConnection()
        _ = connection.handle(.received(.heartbeat, attempt: 1), atMilliseconds: t0 + 40000, jitter: 0)

        XCTAssertEqual(
            connection.handle(.timerFired(.silence, attempt: 1), atMilliseconds: t0 + 90000, jitter: 0),
            [.schedule(.silence, afterMilliseconds: 40000, attempt: 1)]
        )
        XCTAssertEqual(
            connection.handle(.timerFired(.silence, attempt: 1), atMilliseconds: t0 + 130_000, jitter: 0),
            [
                .close(attempt: 1),
                .emit(.reconnecting(delayMilliseconds: 1000, cause: .silent)),
                .schedule(.backoff, afterMilliseconds: 1000, attempt: 1),
            ]
        )
    }

    /// ⚠️ A TIMER FOR ANOTHER PHASE OF THE SAME ATTEMPT CHANGES NOTHING.
    func testATimerForAnotherPhaseIsIgnored() {
        var connection = openConnection()
        XCTAssertEqual(connection.handle(.timerFired(.connect, attempt: 1), atMilliseconds: t0 + 15000, jitter: 0), [])
        XCTAssertEqual(connection.handle(.timerFired(.backoff, attempt: 1), atMilliseconds: t0 + 15000, jitter: 0), [])
    }

    // MARK: - Stale results

    func testEveryResultForAnotherAttemptIsIgnored() {
        var connection = openConnection()
        let before = connection

        XCTAssertEqual(connection.handle(.minted(.success(grant()), attempt: 0), atMilliseconds: t0, jitter: 0), [])
        XCTAssertEqual(connection.handle(.openFailed(reason: "x", attempt: 9), atMilliseconds: t0, jitter: 0), [])
        XCTAssertEqual(
            connection.handle(.received(.text(envelopeJSON()), attempt: 9), atMilliseconds: t0, jitter: 0),
            []
        )
        XCTAssertEqual(connection.handle(.broken(reason: "x", attempt: 9), atMilliseconds: t0, jitter: 0), [])
        XCTAssertEqual(connection.handle(.timerFired(.renewal, attempt: 9), atMilliseconds: t0, jitter: 0), [])
        XCTAssertEqual(connection, before)
    }

    func testResultsForTheRightAttemptInTheWrongPhaseAreIgnored() {
        var waiting = TelemetryConnection(workspaceId: "ws_1")
        _ = waiting.handle(.start, atMilliseconds: t0, jitter: 0)
        _ = waiting.handle(.minted(.failure(.transport("x")), attempt: 1), atMilliseconds: t0, jitter: 0)

        XCTAssertEqual(waiting.handle(.minted(.success(grant()), attempt: 1), atMilliseconds: t0, jitter: 0), [])
        XCTAssertEqual(waiting.handle(.openFailed(reason: "x", attempt: 1), atMilliseconds: t0, jitter: 0), [])
        XCTAssertEqual(waiting.handle(.received(.heartbeat, attempt: 1), atMilliseconds: t0, jitter: 0), [])
        XCTAssertEqual(waiting.handle(.broken(reason: "x", attempt: 1), atMilliseconds: t0, jitter: 0), [])
        XCTAssertEqual(waiting.phase, .waiting)
    }

    // MARK: - Stopping

    func testStopClosesAnOpenSocketAndEndsOnce() {
        var connection = openConnection()
        XCTAssertEqual(
            connection.handle(.stop, atMilliseconds: t0, jitter: 0),
            [.close(attempt: 1), .cancelTimers, .emit(.ended(nil)), .finish]
        )
        XCTAssertEqual(connection.handle(.stop, atMilliseconds: t0, jitter: 0), [])
        XCTAssertEqual(connection.handle(.start, atMilliseconds: t0, jitter: 0), [])
    }

    func testStopWithoutASocketEndsWithoutAClose() {
        var idle = TelemetryConnection(workspaceId: "ws_1")
        XCTAssertEqual(idle.handle(.stop, atMilliseconds: t0, jitter: 0), [.cancelTimers, .emit(.ended(nil)), .finish])

        var minting = TelemetryConnection(workspaceId: "ws_1")
        _ = minting.handle(.start, atMilliseconds: t0, jitter: 0)
        XCTAssertEqual(
            minting.handle(.stop, atMilliseconds: t0, jitter: 0),
            [.cancelTimers, .emit(.ended(nil)), .finish]
        )
    }

    func testStopWhileConnectingClosesTheSocketToCome() {
        var connection = TelemetryConnection(workspaceId: "ws_1")
        _ = connection.handle(.start, atMilliseconds: t0, jitter: 0)
        _ = connection.handle(.minted(.success(grant()), attempt: 1), atMilliseconds: t0, jitter: 0)

        XCTAssertEqual(
            connection.handle(.stop, atMilliseconds: t0, jitter: 0),
            [.close(attempt: 1), .cancelTimers, .emit(.ended(nil)), .finish]
        )
        XCTAssertEqual(
            connection.handle(
                .opened(selectedSubprotocol: "distronode.telemetry.v1", attempt: 1),
                atMilliseconds: t0,
                jitter: 0
            ),
            [.close(attempt: 1)]
        )
    }

    // MARK: - Classification

    func testTransientMintFailures() {
        XCTAssertTrue(TelemetryConnection.isTransient(.transport("offline")))
        XCTAssertTrue(TelemetryConnection.isTransient(.http(status: 500, message: nil)))
        XCTAssertTrue(TelemetryConnection.isTransient(.http(status: 429, message: nil)))
        XCTAssertTrue(TelemetryConnection.isTransient(.http(status: 401, message: nil)))
        XCTAssertFalse(TelemetryConnection.isTransient(.http(status: 403, message: nil)))
        XCTAssertFalse(TelemetryConnection.isTransient(.http(status: 404, message: nil)))
        XCTAssertFalse(TelemetryConnection.isTransient(.decoding("x")))
    }
}
