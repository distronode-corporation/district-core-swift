@testable import DistrictCall
import XCTest

/// ``CallJoinGate``: one microphone track per call.
///
/// ⛔ THE CASE THAT MATTERS IS THE FIRST ONE BELOW. Both reducers send an unmute on
/// ``CallEngineEvent/connected``, which the SDK reports before the join's own microphone is
/// published; an unmute that reached the SDK then published a second track.
final class CallJoinGateTests: XCTestCase {
    func testAnUnmuteDuringTheJoinIsDroppedAtOnce() async {
        let gate = CallJoinGate()
        await gate.begin()

        let admitted = await gate.admitsMute(false)

        XCTAssertFalse(admitted, "the join is publishing the microphone live; a second unmute is a second track")
    }

    func testAMuteDuringTheJoinWaitsForItAndThenGoesThrough() async {
        let gate = CallJoinGate()
        await gate.begin()
        let answer = Answer()

        let mute = Task {
            let admitted = await gate.admitsMute(true)
            await answer.record(admitted)
        }
        for _ in 0 ..< 500 {
            await Task.yield()
        }
        await expectAnswer(nil, answer)

        await gate.finish(joined: true)
        await mute.value

        await expectAnswer(true, answer)
    }

    func testAMuteWaitingOnAFailedJoinIsDropped() async {
        let gate = CallJoinGate()
        await gate.begin()
        let first = Answer()
        let second = Answer()

        // Two waiters, so the release is proved to reach every one of them.
        let one = Task { await first.record(gate.admitsMute(true)) }
        let two = Task { await second.record(gate.admitsMute(true)) }
        for _ in 0 ..< 500 {
            await Task.yield()
        }
        await gate.finish(joined: false)
        await one.value
        await two.value

        await expectAnswer(false, first)
        await expectAnswer(false, second)
    }

    func testAfterAJoinEveryCommandGoesThrough() async {
        let gate = CallJoinGate()
        await gate.begin()
        await gate.finish(joined: true)

        let unmute = await gate.admitsMute(false)
        let mute = await gate.admitsMute(true)

        XCTAssertTrue(unmute)
        XCTAssertTrue(mute)
    }

    func testAfterAFailedJoinNothingGoesThrough() async {
        let gate = CallJoinGate()
        await gate.begin()
        await gate.finish(joined: false)

        let unmute = await gate.admitsMute(false)
        let mute = await gate.admitsMute(true)

        XCTAssertFalse(unmute)
        XCTAssertFalse(mute)
    }

    func testWithNoJoinBegunACommandGoesThrough() async {
        let gate = CallJoinGate()

        let unmute = await gate.admitsMute(false)
        let mute = await gate.admitsMute(true)

        XCTAssertTrue(unmute)
        XCTAssertTrue(mute)
    }

    /// ⚠️ THE REDUCERS' HALF OF THE CONTRACT: each answers `.connected` with exactly one
    /// unmute, which is the command the gate drops while the join is out.
    func testBothReducersAnswerConnectedWithAnUnmute() {
        var incoming = IncomingCallController()
        incoming.handle(.ringing(workspace: WorkspaceID("w"), call: CallID("c"), atMilliseconds: 0))
        incoming.handle(.answerPressed)
        incoming.handle(.answerJoinable(url: "wss://example.invalid", token: "t"))
        let answered = incoming.handle(.engine(.connected))
        XCTAssertEqual(answered.filter { $0 == .engine(.setMuted(false)) }.count, 1)

        var outbound = SoftphoneSession.inConnecting()
        let placed = outbound.handle(.engine(.connected))
        XCTAssertEqual(placed.filter { $0 == .engine(.setMuted(false)) }.count, 1)
    }

    private func expectAnswer(
        _ expected: Bool?,
        _ answer: Answer,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let value = await answer.value
        XCTAssertEqual(value, expected, file: file, line: line)
    }
}

/// What one waiting command was told.
private actor Answer {
    private(set) var value: Bool?

    func record(_ admitted: Bool) {
        value = admitted
    }
}
