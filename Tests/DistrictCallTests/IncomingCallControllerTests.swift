@testable import DistrictCall
import XCTest

/// The inbound state machine: ring, answer, decline, time out.
///
/// ⛔ THE MOST IMPORTANT ASSERTIONS IN THIS FILE ARE WHAT IS SENT WHEN A RING ENDS
/// UNANSWERED. A person's decline adds exactly one request,
/// ``IncomingCallCommand/requestDecline(workspace:call:)``, so the server can end the
/// ring and let the agent take a message (Sean's decision, 2026-10-24, GitLab #2 note
/// 4083623386). A timeout, a withdrawal and a missing session add NOTHING: none has a
/// person behind it, and reporting one would tell the caller somebody refused them.
final class IncomingCallControllerTests: XCTestCase {
    func testAPushRingsTheOSAndTheNotificationShadeTogether() {
        var controller = IncomingCallController()
        let commands = controller.handle(
            .ringing(workspace: testWorkspace, call: testCall, atMilliseconds: testRingStart)
        )

        XCTAssertEqual([.startRinging(workspace: testWorkspace, call: testCall)], commands)
        XCTAssertEqual(.ringing, controller.state.phase)
        XCTAssertEqual(testWorkspace, controller.state.workspaceID)
        XCTAssertEqual(testCall, controller.state.callID)
        // ⚠️ NO DURATION YET. The media state stays nil until media is up, which
        // is what stops a ringing screen drawing a timer.
        XCTAssertNil(controller.state.media)
    }

    func testASecondPushWhileOneIsLiveIsDroppedNotQueuedAndNotAReplacement() {
        // ⛔ ONE ENGINE, ONE AUDIO FOCUS. A replacement would tear down a
        // conversation the user is having in order to ring them about another;
        // the dropped call still reaches the server's timeout and the agent takes a
        // message, which is the right outcome for someone already on the phone.
        var controller = IncomingCallController.inRinging()
        let commands = controller.handle(
            .ringing(workspace: testWorkspace, call: CallID("CA2"), atMilliseconds: testRingStart + 1)
        )

        XCTAssertEqual([], commands)
        XCTAssertEqual(testCall, controller.state.callID)
        XCTAssertEqual(testRingStart, controller.state.ringStartedAtMilliseconds)
    }

    /// The ending every unanswered ring shares, with nothing sent.
    private static let quietEnding: [IncomingCallCommand] = [.stopRinging, .reportCallEnded]

    private static func sendsSomething(_ commands: [IncomingCallCommand]) -> Bool {
        commands.contains { command in
            switch command {
            case .requestAnswer, .requestDecline:
                true
            default:
                false
            }
        }
    }

    func testAPersonsDeclineAddsExactlyTheDeclineRequest() {
        // ⛔ THE RULE SINCE 8.0.0, ASSERTED AS A DIFFERENCE RATHER THAN A LIST. A
        // decline ends the ring exactly as a timeout does and then adds ONE command,
        // the request, LAST, so the ring is gone locally before any round trip.
        var declined = IncomingCallController.inRinging()
        var timedOut = IncomingCallController.inRinging()

        let declineCommands = declined.handle(.declinePressed)
        let timeoutCommands = timedOut.handle(.ringTimedOut)

        XCTAssertEqual(timeoutCommands + [.requestDecline(workspace: testWorkspace, call: testCall)], declineCommands)
        XCTAssertEqual(
            [.stopRinging, .reportCallEnded, .requestDecline(workspace: testWorkspace, call: testCall)],
            declineCommands
        )
        XCTAssertEqual(.ended(.declined), declined.state.phase)
    }

    func testATimeoutSendsNothing() {
        // ⛔ A PHONE IN A POCKET IS NOT A PERSON REFUSING THE CALL. The server's own
        // rendezvous expiry does the work.
        var controller = IncomingCallController.inRinging()

        let commands = controller.handle(.ringTimedOut)

        XCTAssertEqual(Self.quietEnding, commands)
        XCTAssertFalse(Self.sendsSomething(commands))
        XCTAssertEqual(.ended(.ringTimedOut), controller.state.phase)
    }

    func testAWithdrawalSendsNothing() {
        // ⛔ THE MAC'S `withdraw` (the live session stopped: sleep, quit, the setting
        // switched off) used to feed `.declinePressed`. Nobody pressed anything, so it
        // feeds `.withdrawnLocally`, which ends the ring the same way and sends nothing.
        // Its summary is skipped straight after, as the app does.
        var controller = IncomingCallController.inRinging()

        let commands = controller.handle(.withdrawnLocally)
        let dismissed = controller.handle(.dismissed)

        XCTAssertEqual(Self.quietEnding, commands)
        XCTAssertEqual([], dismissed)
        XCTAssertEqual(.idle, controller.state.phase)
    }

    func testANoSessionEndingSendsNothingInAnyPhase() {
        // ⛔ BOTH APPS' `endForNoSession` (the session gate found nobody signed in)
        // feed `.withdrawnLocally` in whatever phase the call is in. While ringing it
        // ends like a decline; after the press like a hang-up, closing a socket only if
        // a join was issued. In no phase does it send a request.
        let ringingOrAnswering: [IncomingCallController] = [.inRinging(), .inAnswering()]
        let joined: [IncomingCallController] = [.inJoining(), .inCall()]
        for start in ringingOrAnswering + joined {
            var controller = start
            let commands = controller.handle(.withdrawnLocally)
            let expected = joined.contains(start) ? Self.quietEnding + [.engine(.disconnect)] : Self.quietEnding
            XCTAssertEqual(expected, commands, "from \(start.state.phase)")
            XCTAssertFalse(Self.sendsSomething(commands), "from \(start.state.phase)")
            XCTAssertEqual(
                start.state.phase == .ringing ? .ended(.declined) : .ended(.hungUpLocally),
                controller.state.phase
            )
        }
    }

    func testADeclineAfterTheAnswerPressSendsNoDeclineRequest() {
        // ⚠️ ONCE ANSWER IS PRESSED THE SERVER HAS THE ANSWER, so a decline from here
        // is a hang-up of a call being joined, not a refusal of a ring.
        var controller = IncomingCallController.inAnswering()

        let commands = controller.handle(.declinePressed)

        XCTAssertEqual(Self.quietEnding, commands)
        XCTAssertEqual(.ended(.hungUpLocally), controller.state.phase)
    }

    func testTheDeclineRequestIsEmittedAtMostOncePerCall() {
        // ⚠️ The ringing screen, the notification and CallKit can all deliver a
        // decline; the first ends the ring and every later one is absorbed.
        var controller = IncomingCallController.inRinging()
        controller.handle(.declinePressed)

        XCTAssertEqual([], controller.handle(.declinePressed))
        XCTAssertEqual([], controller.handle(.withdrawnLocally))
    }

    func testTheRingNotificationGoesAwayAtThePressBeforeTheRoundTrip() {
        // ⛔ AT THE PRESS, NOT AT THE CONNECT. Leaving it up during the round trip
        // leaves an Answer/Decline pair on screen for a call that is already
        // being joined, and the notification is deliberately not swipeable.
        var controller = IncomingCallController.inRinging()
        let commands = controller.handle(.answerPressed)

        XCTAssertEqual([.stopRinging, .requestAnswer(workspace: testWorkspace, call: testCall)], commands)
        XCTAssertEqual(.answering, controller.state.phase)
    }

    func testASecondAnswerWhileTheFirstIsInFlightIsDropped() {
        // ⚠️ The notification's button, the on-screen button and a car head unit
        // can all fire, and the OS can deliver one twice. A second round trip
        // would write the server's rendezvous again for a call already joining.
        var controller = IncomingCallController.inRinging()
        controller.handle(.answerPressed)

        XCTAssertEqual([], controller.handle(.answerPressed))
        XCTAssertEqual(.answering, controller.state.phase)
    }

    func testTheOSIsToldTheCallIsActiveOnlyAfterMediaIsUp() {
        // ⛔ Marking it active on the press starts the OS's own duration counter
        // early and, on a failed join, leaves the user looking at a connected
        // call with no audio.
        var controller = IncomingCallController.inAnswering()

        let joining = controller.handle(.answerJoinable(url: testAnswerURL, token: testAnswerToken))
        XCTAssertEqual([.engine(.connect(url: testAnswerURL, token: testAnswerToken))], joining)
        XCTAssertEqual(.answering, controller.state.phase, "not connected until media says so")
        XCTAssertNil(controller.state.media)

        let live = controller.handle(.engine(.connected))
        XCTAssertEqual([.engine(.setMuted(false)), .reportCallActive], live)
        XCTAssertEqual(.inCall, controller.state.phase)
        XCTAssertNotNil(controller.state.media)
    }

    func testAFailedJoinEndsTheCallAndClosesTheSocketItOpened() {
        // ⛔ `engineAttached` IS WHY THE DISCONNECT IS HERE. `media` is still nil
        // at this point, so a check on that would leave the engine holding a
        // socket nobody told it to release.
        var controller = IncomingCallController.inJoining()
        let commands = controller.handle(.engine(.failed(message: "no route to host")))

        XCTAssertEqual([.stopRinging, .reportCallEnded, .engine(.disconnect)], commands)
        XCTAssertEqual(.ended(.failed(message: "no route to host")), controller.state.phase)
    }

    func testACallerWhoHungUpWhileThePhoneRangIsNotReportedAsAnError() {
        // ⚠️ The overwhelmingly common way to reach this is that the caller hung
        // up between the phone ringing and a thumb arriving.
        var controller = IncomingCallController.inAnswering()
        let commands = controller.handle(.answerRejected(.callerGone))

        XCTAssertEqual([.stopRinging, .reportCallEnded], commands, "no engine was ever attached")
        XCTAssertEqual(.ended(.callerCancelled), controller.state.phase)
    }

    func testAViewersRefusalEndsTheCallWithTheServersMessage() {
        // ⛔ A VIEWER'S PHONE GENUINELY RINGS: the ring is fanned out to every
        // registered device in the workspace without consulting roles.
        var controller = IncomingCallController.inAnswering()
        controller.handle(.answerRejected(.refused(message: "Forbidden")))

        XCTAssertEqual(.ended(.answerRefused(message: "Forbidden")), controller.state.phase)
    }

    func testTheDurationRunsFromMediaRatherThanFromThePress() {
        // ⛔ The platform bills answered time; counting from the press would
        // include the answer round trip and the join.
        var controller = IncomingCallController.inAnswering()
        controller.handle(.tick)
        XCTAssertNil(controller.state.media)

        controller.handle(.answerJoinable(url: testAnswerURL, token: testAnswerToken))
        controller.handle(.engine(.connected))
        controller.handle(.tick)
        controller.handle(.tick)
        XCTAssertEqual(2, controller.state.media?.elapsedSeconds)
    }

    func testEndedIsAStateTheUserLeavesRatherThanOneThatExpires() {
        // ⛔ A call that vanished on hang-up would answer "how long was that"
        // with nothing.
        var ringing = IncomingCallController.inRinging()
        XCTAssertEqual([], ringing.handle(.dismissed))
        XCTAssertEqual(.ringing, ringing.state.phase, "a ringing call is not dismissible")

        var controller = IncomingCallController.inEnded()
        XCTAssertEqual([], controller.handle(.dismissed))
        XCTAssertEqual(IncomingCallState(), controller.state)
    }
}
