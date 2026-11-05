import DistrictCall
import DistrictModel
import Foundation
import XCTest

/// Live supervision of one call: listen, take over, hand back, and every way out.
///
/// ⛔ THE ORDERING ASSERTIONS ARE THE POINT. The takeover credential is asked for while
/// the person is still listening, a refusal leaves them listening, and only a grant
/// leaves the listen room, before the coach room is joined.
final class SuperviseSessionTests: XCTestCase {
    private let caller = CallParticipant(identity: "sip_caller")
    private let agent = CallParticipant(identity: "agent-1", isAgent: true)
    private let refusal = ApiError.http(status: 409, message: "This call has ended.", code: "call_not_in_progress")

    private func session(_ role: WorkspaceRole? = .client) -> SuperviseSession {
        SuperviseSession(callId: "call_1", role: role)
    }

    /// A session listening to a room holding the caller and the assistant.
    private func listening(_ role: WorkspaceRole? = .client) -> SuperviseSession {
        var supervise = session(role)
        supervise.handle(.listenPressed)
        supervise.handle(.listenGranted(url: "wss://listen", token: "listen-jwt"))
        supervise.handle(.engine(.listen, .connected))
        supervise.handle(.engine(.listen, .participantJoined(caller)))
        supervise.handle(.engine(.listen, .participantJoined(agent)))
        return supervise
    }

    /// A session holding the call.
    private func takenOver() -> SuperviseSession {
        var supervise = listening()
        supervise.handle(.takeOverPressed)
        supervise.handle(.takeoverGranted(url: "wss://coach", token: "coach-jwt"))
        supervise.handle(.engine(.takeover, .connected))
        supervise.handle(.engine(.takeover, .participantJoined(caller)))
        return supervise
    }

    // MARK: - Listen

    func testListeningAsksOnceJoinsVerbatimAndPublishesNothing() {
        var supervise = session()
        XCTAssertTrue(supervise.state.mayListen)

        XCTAssertEqual(supervise.handle(.listenPressed), [.requestListen])
        XCTAssertEqual(supervise.state.phase, .requestingListen)
        XCTAssertEqual(supervise.handle(.listenPressed), [], "a second press asks nothing")

        let response = CallMonitorResponse(success: true, token: "listen-jwt", url: "wss://listen")
        XCTAssertEqual(
            supervise.handle(.listenGranted(response)),
            [.join(.listen, url: "wss://listen", token: "listen-jwt")]
        )
        XCTAssertEqual(supervise.state.phase, .joiningListen)

        // ⛔ NO MICROPHONE COMMAND, EVER, ON THE LISTEN LEG.
        XCTAssertEqual(supervise.handle(.engine(.listen, .connected)), [])
        XCTAssertEqual(supervise.state.phase, .listening)
        XCTAssertFalse(supervise.state.media.microphoneEnabled)
        XCTAssertFalse(supervise.state.holdsTheCall)
    }

    func testARefusedListenReportsTheCallKitCallAndKeepsTheReason() {
        var supervise = session()
        supervise.handle(.listenPressed)

        XCTAssertEqual(supervise.handle(.listenRefused(refusal)), [.reportCallEnded])
        XCTAssertEqual(supervise.state.phase, .idle)
        XCTAssertEqual(supervise.state.problem, .listenRefused(refusal))

        // The next attempt clears it.
        supervise.handle(.listenPressed)
        XCTAssertNil(supervise.state.problem)
    }

    func testAListenJoinThatFailsLeavesNoLeg() {
        var supervise = session()
        supervise.handle(.listenPressed)
        supervise.handle(.listenGranted(url: "wss://listen", token: "t"))

        XCTAssertEqual(
            supervise.handle(.engine(.listen, .failed(message: "timeout"))),
            [.reportCallEnded, .engine(.listen, .disconnect)]
        )
        XCTAssertEqual(supervise.state.phase, .idle)
        XCTAssertNil(supervise.state.leg)
        XCTAssertEqual(supervise.state.problem, .listenFailed(message: "timeout"))
    }

    func testADroppedListenRoomIsReportedAndSaysSo() {
        var supervise = listening()

        XCTAssertEqual(
            supervise.handle(.engine(.listen, .disconnected(reason: "network"))),
            [.reportCallEnded, .engine(.listen, .disconnect)]
        )
        XCTAssertEqual(supervise.state.problem, .listenDropped(reason: "network"))
    }

    /// ⛔ NO REPORT: CallKit performed Stop itself. A grant that answers afterwards builds
    /// no engine for a person who left.
    func testStoppingWhileTheSeatIsInFlightAbsorbsTheLateGrant() {
        var supervise = session()
        supervise.handle(.listenPressed)

        XCTAssertEqual(supervise.handle(.stopPressed), [])
        XCTAssertEqual(supervise.handle(.listenGranted(url: "wss://listen", token: "t")), [])
        XCTAssertEqual(supervise.state.phase, .idle)
    }

    func testStopListeningLeavesTheRoomAndMayListenAgain() {
        var supervise = listening()

        XCTAssertEqual(supervise.handle(.stopPressed), [.engine(.listen, .disconnect)])
        XCTAssertEqual(supervise.state.phase, .idle)
        XCTAssertTrue(supervise.state.mayListen)
        XCTAssertEqual(supervise.handle(.listenPressed), [.requestListen])
    }

    // MARK: - Take over

    func testATakeoverIsAskedForWhileStillListening() {
        var supervise = listening()
        XCTAssertTrue(supervise.state.mayTakeOver)

        XCTAssertEqual(supervise.handle(.takeOverPressed), [.requestTakeover])
        XCTAssertEqual(supervise.state.phase, .requestingTakeover)
        XCTAssertEqual(supervise.state.leg, .listen, "the listen room is kept until a grant")
        XCTAssertEqual(supervise.handle(.takeOverPressed), [], "a second press asks nothing")
    }

    /// ⛔ THE WEBSITE'S RULE: a refused takeover leaves the person listening, untouched.
    func testARefusedTakeoverLeavesThePersonListening() {
        var supervise = listening()
        supervise.handle(.takeOverPressed)

        XCTAssertEqual(supervise.handle(.takeoverRefused(refusal)), [])
        XCTAssertEqual(supervise.state.phase, .listening)
        XCTAssertEqual(supervise.state.leg, .listen)
        XCTAssertEqual(supervise.state.problem, .takeoverRefused(refusal))
    }

    // MARK: - A team member's own call

    /// ⛔ NO ASSISTANT, NO NOTE AND NO TAKEOVER, BUT LISTENING STAYS. A team member's own
    /// softphone call (`receptionistOnCall: false`) offers Listen only, and a stray Take over
    /// asks nothing of the server.
    func testATeamMembersOwnCallOffersListenOnly() {
        var supervise = SuperviseSession(callId: "call_1", role: .agency, receptionistOnCall: false)
        XCTAssertTrue(supervise.state.mayListen)
        XCTAssertFalse(supervise.state.mayWhisper)

        supervise.handle(.listenPressed)
        supervise.handle(.listenGranted(url: "wss://listen", token: "listen-jwt"))
        supervise.handle(.engine(.listen, .connected))
        XCTAssertEqual(supervise.state.phase, .listening)
        XCTAssertFalse(supervise.state.mayTakeOver)
        XCTAssertFalse(supervise.state.mayWhisper)
        XCTAssertEqual(supervise.handle(.takeOverPressed), [])
        XCTAssertEqual(supervise.state.phase, .listening)
    }

    /// ⚠️ THE DEFAULT IS THE ASSISTANT BEING ON THE CALL, the website's reading of an absent
    /// flag, so a caller that never passes it keeps every action.
    func testTheAssistantIsAssumedOnTheCallUnlessSaidOtherwise() {
        let supervise = listening(.agency)
        XCTAssertTrue(supervise.state.receptionistOnCall)
        XCTAssertTrue(supervise.state.mayWhisper)
        XCTAssertTrue(supervise.state.mayTakeOver)
    }

    /// ⛔ A SESSION BUILT FROM THE FEED FOLLOWS EACH ROW: the recorded `district-calls.json`
    /// has three calls with the assistant on them and two team-member softphone calls.
    func testASessionFromTheFeedReadsTheReceptionistFlag() throws {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0 ..< 3 {
            url = url.deletingLastPathComponent()
        }
        let feed = try JSONDecoder().decode(
            [CallSummary].self,
            from: Data(contentsOf: url.appendingPathComponent("contracts/mobile/district-calls.json"))
        )
        let mayWhisper = feed.map { SuperviseSession(call: $0, role: .client).state.mayWhisper }
        XCTAssertEqual(mayWhisper, [true, true, true, false, false])
        XCTAssertEqual(SuperviseSession(call: feed[3], role: .client).state.callId, "call_contract_outbound_unanswered")
    }

    /// ⛔ A TEAM MEMBER'S OWN CALL REFUSES THE TAKEOVER (409 `call_has_no_receptionist`) AND
    /// THE PERSON KEEPS LISTENING, with the code kept for the screen's sentence.
    func testATakeoverOfATeamMembersOwnCallLeavesThePersonListening() {
        let ownCall = ApiError.http(status: 409, message: "x", code: "call_has_no_receptionist")
        var supervise = listening()
        supervise.handle(.takeOverPressed)

        XCTAssertEqual(supervise.handle(.takeoverRefused(ownCall)), [])
        XCTAssertEqual(supervise.state.phase, .listening)
        XCTAssertEqual(supervise.state.problem, .takeoverRefused(ownCall))
    }

    /// ⛔ A LISTEN ON A CALL THAT HAS ENDED (409 `call_ended`) ENDS THE CALLKIT CALL, like
    /// any refused listen, and keeps the code.
    func testAListenOnAnEndedCallReportsTheCallKitCallAndKeepsCallEnded() {
        let ended = ApiError.http(status: 409, message: "This call has ended.", code: "call_ended")
        var supervise = session()
        supervise.handle(.listenPressed)

        XCTAssertEqual(supervise.handle(.listenRefused(ended)), [.reportCallEnded])
        XCTAssertEqual(supervise.state.problem, .listenRefused(ended))
    }

    /// ⛔ LEAVE THE LISTEN ROOM, THEN JOIN THE COACH ROOM, THEN OPEN THE MICROPHONE.
    func testAGrantSwapsTheLegsInOrderAndOpensTheMicrophoneOnlyOnceJoined() {
        var supervise = listening()
        supervise.handle(.takeOverPressed)
        let grant = CallTakeoverResponse(success: true, url: "wss://coach", token: "coach-jwt", roomName: "call_1")

        XCTAssertEqual(
            supervise.handle(.takeoverGranted(grant)),
            [.engine(.listen, .disconnect), .join(.takeover, url: "wss://coach", token: "coach-jwt")]
        )
        XCTAssertEqual(supervise.state.phase, .joiningTakeover)
        XCTAssertFalse(supervise.state.mayWhisper, "the assistant is about to step back")

        // ⛔ THE LISTEN ENGINE'S OWN LATE DISCONNECT ENDS NOTHING.
        XCTAssertEqual(supervise.handle(.engine(.listen, .disconnected(reason: nil))), [])
        XCTAssertEqual(supervise.state.phase, .joiningTakeover)

        XCTAssertEqual(supervise.handle(.engine(.takeover, .connected)), [.engine(.takeover, .setMuted(false))])
        XCTAssertEqual(supervise.state.phase, .takenOver)
        XCTAssertTrue(supervise.state.holdsTheCall)
    }

    /// ⛔ NO HALF-JOINED LEG: the listen room is already gone, so the person is out of the
    /// call and told why, not silently back to listening.
    func testACoachRoomThatCannotBeJoinedLeavesThePersonOutOfTheCall() {
        var supervise = listening()
        supervise.handle(.takeOverPressed)
        supervise.handle(.takeoverGranted(url: "wss://coach", token: "coach-jwt"))

        XCTAssertEqual(
            supervise.handle(.engine(.takeover, .failed(message: "mic"))),
            [.reportCallEnded, .engine(.takeover, .disconnect)]
        )
        XCTAssertEqual(supervise.state.phase, .idle)
        XCTAssertEqual(supervise.state.problem, .takeoverJoinFailed(message: "mic"))
    }

    func testHandingBackLeavesTheCoachRoomWithoutAReport() {
        var supervise = takenOver()

        XCTAssertEqual(supervise.handle(.stopPressed), [.engine(.takeover, .disconnect)])
        XCTAssertEqual(supervise.state.phase, .idle)
        XCTAssertFalse(supervise.state.media.microphoneEnabled)
    }

    func testMuteGoesToTheCoachLegOnly() {
        var supervise = takenOver()
        supervise.handle(.engine(.takeover, .microphoneChanged(enabled: true)))

        XCTAssertEqual(supervise.handle(.muteToggled), [.engine(.takeover, .setMuted(true))])

        var listener = listening()
        XCTAssertEqual(listener.handle(.muteToggled), [], "a listener has no microphone to mute")
    }

    func testTheSpeakerFollowsTheCurrentLegAndSurvivesTheSwap() {
        var supervise = listening()
        XCTAssertEqual(supervise.handle(.speakerToggled), [.engine(.listen, .setSpeakerphone(true))])
        supervise.handle(.takeOverPressed)
        supervise.handle(.takeoverGranted(url: "wss://coach", token: "t"))

        XCTAssertTrue(supervise.state.media.speakerRequested)
        // ⛔ THE COACH LEG IS A NEW ENGINE: the speaker is re-applied when it connects, with
        // the microphone (Seer, #52).
        XCTAssertEqual(
            supervise.handle(.engine(.takeover, .connected)),
            [.engine(.takeover, .setMuted(false)), .engine(.takeover, .setSpeakerphone(true))]
        )
        XCTAssertEqual(supervise.handle(.speakerToggled), [.engine(.takeover, .setSpeakerphone(false))])
        var idle = session()
        XCTAssertEqual(idle.handle(.speakerToggled), [], "no engine, nothing to route")
    }

    /// ⛔ A ROOM THAT HANGS UP WHILE STILL BEING JOINED IS A FAILED JOIN, on either leg: the OS
    /// is told, the one engine is disconnected, and the reason is kept.
    func testARoomThatDisconnectsWhileJoiningIsAFailedJoin() {
        var joiningListen = session()
        joiningListen.handle(.listenPressed)
        joiningListen.handle(.listenGranted(url: "wss://listen", token: "listen-jwt"))
        XCTAssertEqual(
            joiningListen.handle(.engine(.listen, .disconnected(reason: "room closed"))),
            [.reportCallEnded, .engine(.listen, .disconnect)]
        )
        XCTAssertEqual(joiningListen.state.problem, .listenFailed(message: "room closed"))

        var joiningCoach = listening()
        joiningCoach.handle(.takeOverPressed)
        joiningCoach.handle(.takeoverGranted(url: "wss://coach", token: "coach-jwt"))
        XCTAssertEqual(
            joiningCoach.handle(.engine(.takeover, .disconnected(reason: "room closed"))),
            [.reportCallEnded, .engine(.takeover, .disconnect)]
        )
        XCTAssertEqual(joiningCoach.state.problem, .takeoverJoinFailed(message: "room closed"))
        XCTAssertEqual(joiningCoach.state.phase, .idle)
    }

    func testADroppedCoachRoomIsReported() {
        var supervise = takenOver()

        XCTAssertEqual(
            supervise.handle(.engine(.takeover, .disconnected(reason: "network"))),
            [.reportCallEnded, .engine(.takeover, .disconnect)]
        )
        XCTAssertEqual(supervise.state.problem, .takeoverDropped(reason: "network"))
    }

    // MARK: - Roles

    func testAViewerMayListenButNeverWhisperOrTakeOver() {
        var supervise = listening(.viewer)
        XCTAssertEqual(supervise.state.phase, .listening)
        XCTAssertFalse(supervise.state.mayWhisper)
        XCTAssertFalse(supervise.state.mayTakeOver)
        XCTAssertEqual(supervise.handle(.takeOverPressed), [])
        XCTAssertEqual(supervise.state.phase, .listening)
    }

    /// ⛔ AN UNKNOWN ROLE GRANTS NOTHING, NOT EVEN LISTENING (``WorkspaceRole/fromWire(_:)``).
    func testAnUnestablishedRoleMayDoNothing() {
        var supervise = session(nil)
        XCTAssertFalse(supervise.state.mayListen)
        XCTAssertFalse(supervise.state.mayWhisper)
        XCTAssertEqual(supervise.handle(.listenPressed), [])
    }

    func testWhisperingIsOpenUntilThePersonHoldsTheCall() {
        XCTAssertTrue(session().state.mayWhisper, "a note needs no room")
        XCTAssertTrue(listening().state.mayWhisper)
        XCTAssertFalse(takenOver().state.mayWhisper)
        XCTAssertFalse(takenOver().state.mayTakeOver)
    }

    // MARK: - The call ending

    func testTheRoomEmptyingIsTheCallEnding() {
        var supervise = listening()

        XCTAssertEqual(supervise.handle(.engine(.listen, .participantLeft(agent))), [], "the caller is still there")
        XCTAssertEqual(
            supervise.handle(.engine(.listen, .participantLeft(caller))),
            [.reportCallEnded, .engine(.listen, .disconnect)]
        )
        XCTAssertEqual(supervise.state.phase, .over)
        XCTAssertNil(supervise.state.problem)
    }

    func testACallThatEndsWhileHeldIsTornDownOnce() {
        var supervise = takenOver()

        XCTAssertEqual(supervise.handle(.callEnded), [.reportCallEnded, .engine(.takeover, .disconnect)])
        XCTAssertEqual(supervise.state.phase, .over)
        // ⛔ TERMINAL: nothing after it produces a command.
        XCTAssertEqual(supervise.handle(.stopPressed), [])
        XCTAssertEqual(supervise.handle(.callEnded), [])
        XCTAssertEqual(supervise.handle(.listenPressed), [])
        XCTAssertFalse(supervise.state.mayWhisper)
    }

    func testACallThatEndsWhileNotInItReportsNothing() {
        var supervise = session()
        XCTAssertEqual(supervise.handle(.callEnded), [])
        XCTAssertEqual(supervise.state.phase, .over)

        var asking = session()
        asking.handle(.listenPressed)
        XCTAssertEqual(asking.handle(.callEnded), [.reportCallEnded], "CallKit holds the call; no engine yet")
    }

    // MARK: - The receipt

    func testANewNoteClearsTheLastReceipt() {
        var supervise = listening()
        let receipt = WhisperReceipt(applied: true, firstWords: "Of course", reason: nil)

        XCTAssertEqual(supervise.handle(.whisperReceipt(receipt)), [])
        XCTAssertEqual(supervise.state.receipt, receipt)
        XCTAssertEqual(supervise.handle(.whisperSent), [])
        XCTAssertNil(supervise.state.receipt)
    }
}
