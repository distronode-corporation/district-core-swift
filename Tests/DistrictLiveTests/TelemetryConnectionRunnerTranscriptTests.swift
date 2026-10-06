@testable import DistrictLive
import DistrictModel
import Foundation
import XCTest

/// The driver's half of the transcript ops: each `send` is performed on the socket it
/// names, after every send before it, and the subscriptions are sent again on the next
/// socket. The rules are proved in `TelemetryConnectionTranscriptTests`.
final class TelemetryConnectionRunnerTranscriptTests: XCTestCase {
    private let clock = ManualClock()
    private let minter = FakeMinter()
    private let transport = FakeTransport()

    private let mode = #"{"op":"socket.mode","v":1,"broadcast":false}"#
    private let subscribe = #"{"op":"transcript.subscribe","v":1,"callId":"call_1"}"#
    private let unsubscribe = #"{"op":"transcript.unsubscribe","v":1,"callId":"call_1"}"#

    private func makeRunner(broadcast: Bool) -> TelemetryConnectionRunner {
        TelemetryConnectionRunner(
            workspaceId: "ws_1",
            broadcast: broadcast,
            minter: minter,
            transport: transport,
            clock: clock,
            jitter: { 0 }
        )
    }

    private func grant(expiresIn: Int64 = 900_000) -> TelemetryTokenResponse {
        .grant(expiresAt: clock.nowMilliseconds() + expiresIn)
    }

    /// ⛔ ORDER: `socket.mode` IS HELD IN FLIGHT, AND THE SUBSCRIBE WAITS BEHIND IT. Two
    /// independent tasks could have sent the subscribe first, and the server would then
    /// relay the workspace to a socket that asked it not to, until the mode arrived.
    func testSendsArePerformedInOrderEachAfterTheOneBefore() async {
        let runner = makeRunner(broadcast: false)
        var updates = runner.updates.makeAsyncIterator()
        await runner.subscribeTranscript(callId: "call_1")
        await runner.start()
        minter.results.provide(.success(grant()))
        let socket = FakeSocket()
        socket.holdSends()
        transport.outcomes.provide(.success(socket))

        let connected = await updates.next()
        XCTAssertEqual(connected, .connected)
        await waitUntil { socket.isHoldingASend }
        for _ in 0 ..< 100 {
            await Task.yield()
        }
        XCTAssertEqual(socket.sent, [], "the subscribe has not overtaken the held mode")

        socket.releaseSend()
        await waitUntil { socket.sent.count == 2 }
        XCTAssertEqual(socket.sent, [mode, subscribe])

        await runner.unsubscribeTranscript(callId: "call_1")
        await waitUntil { socket.sent.count == 3 }
        XCTAssertEqual(socket.sent.last, unsubscribe)
        await runner.stop()
    }

    /// The subscription is sent again on the socket that replaces a closed one, and the
    /// gap heal sends it once more.
    func testTheNextSocketIsSubscribedAgainAndAResubscribeIsSent() async {
        let runner = makeRunner(broadcast: true)
        var updates = runner.updates.makeAsyncIterator()
        await runner.start()
        minter.results.provide(.success(grant()))
        let first = FakeSocket()
        transport.outcomes.provide(.success(first))
        _ = await updates.next()
        await runner.subscribeTranscript(callId: "call_1")
        await waitUntil { first.sent == [subscribe] }

        first.push(.closed(code: 1001, reason: "restart"))
        _ = await updates.next()
        // The handshake deadline, the renewal, the silence watchdog and now the backoff: the
        // advance must land on a backoff that is already asleep.
        await waitUntil { clock.pendingSleepers >= 4 }
        clock.advance(by: 1000)
        let second = FakeSocket()
        transport.outcomes.provide(.success(second))
        let reconnected = await updates.next()
        XCTAssertEqual(reconnected, .connected)
        await waitUntil { second.sent == [subscribe] }

        await runner.resubscribeTranscript(callId: "call_1")
        await waitUntil { second.sent == [subscribe, subscribe] }
        XCTAssertEqual(first.sent, [subscribe], "nothing more reaches the closed socket")
        await runner.stop()
    }

    /// A send that throws is not reported: the broken socket's read reports it, and the
    /// sends after it still run (and fail) rather than waiting forever.
    func testAFailedSendIsLeftToTheReadSide() async {
        let runner = makeRunner(broadcast: false)
        var updates = runner.updates.makeAsyncIterator()
        await runner.subscribeTranscript(callId: "call_1")
        await runner.start()
        minter.results.provide(.success(grant()))
        let socket = FakeSocket()
        socket.breakSends()
        transport.outcomes.provide(.success(socket))
        _ = await updates.next()

        await runner.unsubscribeTranscript(callId: "call_1")
        socket.fail()
        let next = await updates.next()
        guard case .reconnecting(_, .network) = next else {
            return XCTFail("expected the read side to report the break, got \(String(describing: next))")
        }
        XCTAssertEqual(socket.sent, [])
        await runner.stop()
    }
}
