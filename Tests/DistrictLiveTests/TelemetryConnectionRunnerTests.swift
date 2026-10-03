@testable import DistrictLive
import DistrictModel
import Foundation
import XCTest

/// The driver, end to end over scripted doubles and a manual clock.
///
/// ⚠️ THE RULES ARE PROVED IN `TelemetryConnectionTests`; these prove only that each
/// command is performed and each result fed back, which is all the driver does.
final class TelemetryConnectionRunnerTests: XCTestCase {
    private let clock = ManualClock()
    private let minter = FakeMinter()
    private let transport = FakeTransport()

    private func makeRunner() -> TelemetryConnectionRunner {
        TelemetryConnectionRunner(
            workspaceId: "ws_1",
            minter: minter,
            transport: transport,
            clock: clock,
            jitter: { 0 }
        )
    }

    private func grant(expiresIn: Int64 = 900_000) -> TelemetryTokenResponse {
        .grant(expiresAt: clock.nowMilliseconds() + expiresIn)
    }

    private let envelopeJSON = #"{"workspaceId":"ws_1","callId":"call_1","eventType":"call_ringing","#
        + #""data":{"callId":"call_1","userIds":["u"]},"timestamp":"t"}"#

    func testItMintsDialsDeliversAndStops() async {
        let runner = makeRunner()
        var updates = runner.updates.makeAsyncIterator()
        await runner.start()

        minter.results.provide(.success(grant()))
        let socket = FakeSocket()
        transport.outcomes.provide(.success(socket))
        let connected = await updates.next()
        XCTAssertEqual(connected, .connected)
        XCTAssertEqual(
            transport.dials.first?.url.absoluteString,
            "wss://telemetry.example.com/ws/telemetry?workspaceId=ws_1"
        )
        XCTAssertEqual(transport.dials.first?.subprotocols, ["distronode.telemetry.v1", "distronode.token.a.b.c"])

        socket.push(.heartbeat)
        socket.push(.text(envelopeJSON))
        let delivered = await updates.next()
        guard case let .event(envelope) = delivered
        else { return XCTFail("expected an event, got \(String(describing: delivered))") }
        XCTAssertEqual(envelope.ringingUserIds, ["u"])

        socket.push(.binary(Data("nope".utf8)))
        let discarded = await updates.next()
        XCTAssertEqual(discarded, .discarded)
        let phase = await runner.phase
        XCTAssertEqual(phase, .open(openedAt: clock.nowMilliseconds(), lastHeardAt: clock.nowMilliseconds()))

        await runner.stop()
        let ended = await updates.next()
        XCTAssertEqual(ended, .ended(nil))
        let after = await updates.next()
        XCTAssertNil(after, "the stream finishes after `ended`")
        await waitUntil { socket.isClosed }
    }

    /// ⛔ 4401: THE SOCKET IS DROPPED AND A NEW CREDENTIAL MINTED AFTER THE BACKOFF.
    func testAServerCloseIsFedBackAndTheBackoffRunsOnTheClock() async {
        let runner = makeRunner()
        var updates = runner.updates.makeAsyncIterator()
        await runner.start()
        minter.results.provide(.success(grant()))
        let socket = FakeSocket()
        transport.outcomes.provide(.success(socket))
        _ = await updates.next()

        socket.push(.closed(code: 4401, reason: "expired"))
        let reconnecting = await updates.next()
        XCTAssertEqual(reconnecting, .reconnecting(delayMilliseconds: 1000, cause: .unauthorized(reason: "expired")))
        await waitUntil { socket.isClosed }
        XCTAssertEqual(minter.results.callCount, 1)

        await waitUntil { clock.pendingSleepers >= 4 }
        clock.advance(by: 1000)
        await waitUntil { minter.results.callCount == 2 }
        await runner.stop()
    }

    func testAFailedHandshakeIsFedBack() async {
        let runner = makeRunner()
        var updates = runner.updates.makeAsyncIterator()
        await runner.start()
        minter.results.provide(.success(grant()))
        transport.outcomes.provide(.failure(.refused))

        let update = await updates.next()
        guard case let .reconnecting(delay, .network(reason)) = update else {
            return XCTFail("expected a network reconnect, got \(String(describing: update))")
        }
        XCTAssertEqual(delay, 1000)
        XCTAssertTrue(reason.contains("refused"), reason)
        await runner.stop()
    }

    func testABrokenSocketIsFedBack() async {
        let runner = makeRunner()
        var updates = runner.updates.makeAsyncIterator()
        await runner.start()
        minter.results.provide(.success(grant()))
        let socket = FakeSocket()
        transport.outcomes.provide(.success(socket))
        _ = await updates.next()

        socket.fail()
        let update = await updates.next()
        guard case .reconnecting(_, .network) = update else {
            return XCTFail("expected a network reconnect, got \(String(describing: update))")
        }
        await runner.stop()
    }

    /// ⛔ A HANDSHAKE THAT FINISHES AFTER ITS DEADLINE IS CLOSED, NOT LEAKED.
    func testALateHandshakeIsClosed() async {
        let runner = makeRunner()
        var updates = runner.updates.makeAsyncIterator()
        await runner.start()
        minter.results.provide(.success(grant()))
        await waitUntil { transport.outcomes.waiters == 1 && clock.pendingSleepers == 1 }

        clock.advance(by: TelemetryProtocol.connectTimeoutMilliseconds)
        let timedOut = await updates.next()
        XCTAssertEqual(timedOut, .reconnecting(delayMilliseconds: 1000, cause: .connectTimedOut))

        let late = FakeSocket()
        transport.outcomes.provide(.success(late))
        await waitUntil { late.isClosed }
        XCTAssertEqual(late.readers, 0, "a closed socket is never read")
        await runner.stop()
    }

    /// ⛔ THE ROUTINE RENEWAL: the old socket closed, a fresh credential minted at once.
    func testTheRenewalTimerReplacesTheSocket() async {
        let runner = makeRunner()
        var updates = runner.updates.makeAsyncIterator()
        await runner.start()
        minter.results.provide(.success(grant(expiresIn: 120_000)))
        let socket = FakeSocket()
        transport.outcomes.provide(.success(socket))
        _ = await updates.next()

        // The connect deadline, the renewal and the watchdog are all armed.
        await waitUntil { clock.pendingSleepers == 3 }
        clock.advance(by: 60000)
        let renewal = await updates.next()
        XCTAssertEqual(renewal, .reconnecting(delayMilliseconds: 0, cause: .renewal))
        await waitUntil { socket.isClosed && minter.results.callCount == 2 }
        await runner.stop()
    }

    func testAProtocolMismatchClosesTheSocketWithoutReadingIt() async {
        let runner = makeRunner()
        var updates = runner.updates.makeAsyncIterator()
        await runner.start()
        minter.results.provide(.success(grant()))
        let socket = FakeSocket(selected: nil)
        transport.outcomes.provide(.success(socket))

        let ended = await updates.next()
        XCTAssertEqual(ended, .ended(.protocolMismatch))
        await waitUntil { socket.isClosed }
        XCTAssertEqual(socket.readers, 0)
    }

    func testTheRandomJitterIsInTheUnitInterval() {
        for _ in 0 ..< 100 {
            XCTAssertTrue((0 ... 1).contains(TelemetryConnectionRunner.randomJitter()))
        }
    }
}

/// The system clock, without waiting on it.
final class SystemLiveClockTests: XCTestCase {
    func testNowIsTheWallClockInMilliseconds() {
        let before = Int64(Date().timeIntervalSince1970 * 1000) - 1
        let now = SystemLiveClock().nowMilliseconds()
        let after = Int64(Date().timeIntervalSince1970 * 1000) + 1
        XCTAssertTrue((before ... after).contains(now))
    }

    /// ⚠️ A deadline already passed is a wait of zero, not a trap.
    func testAZeroOrNegativeWaitReturnsAtOnce() async throws {
        try await SystemLiveClock().sleep(milliseconds: 0)
        try await SystemLiveClock().sleep(milliseconds: -5000)
    }
}
