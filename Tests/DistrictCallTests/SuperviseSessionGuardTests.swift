import DistrictCall
import DistrictModel
import Foundation
import XCTest

/// Supervise's two guards beyond the phases: an engine this session has left can end
/// nothing, and a call with no assistant on it offers Listen only. Split from
/// `SuperviseSessionTests` for `type_body_length`.
final class SuperviseSessionGuardTests: XCTestCase {
    private let caller = CallParticipant(identity: "sip_caller")
    private let agent = CallParticipant(identity: "agent-1", isAgent: true)

    /// A session listening to a room holding the caller and the assistant.
    private func listening(_ role: WorkspaceRole? = .client) -> SuperviseSession {
        var supervise = SuperviseSession(callId: "call_1", role: role)
        supervise.handle(.listenPressed)
        supervise.handle(.listenGranted(url: "wss://listen", token: "listen-jwt"))
        supervise.handle(.listen, .connected)
        supervise.handle(.listen, .participantJoined(caller))
        supervise.handle(.listen, .participantJoined(agent))
        return supervise
    }

    // MARK: - Engine generations

    /// ⛔ STOP, LISTEN AGAIN, AND THE FIRST ENGINE'S LATE EVENTS END NOTHING (Seer, #52). The
    /// first engine was generation 1; its `disconnected` and `failed` arrive after the second
    /// listen was granted, and the second engine (generation 2) carries on.
    func testAStoppedEnginesLateEventsDoNotEndTheListenThatReplacedIt() {
        var supervise = listening()
        XCTAssertEqual(supervise.state.generation, 1)
        supervise.handle(.stopPressed)
        supervise.handle(.listenPressed)
        XCTAssertEqual(
            supervise.handle(.listenGranted(url: "wss://listen-2", token: "listen-jwt-2")),
            [.join(.listen, generation: 2, url: "wss://listen-2", token: "listen-jwt-2")]
        )

        XCTAssertEqual(supervise.handle(.engine(.listen, generation: 1, .disconnected(reason: "left"))), [])
        XCTAssertEqual(supervise.state.phase, .joiningListen)
        XCTAssertNil(supervise.state.problem)

        XCTAssertEqual(supervise.handle(.engine(.listen, generation: 2, .connected)), [])
        XCTAssertEqual(supervise.state.phase, .listening)
        XCTAssertEqual(supervise.handle(.engine(.listen, generation: 1, .failed(message: "late"))), [])
        XCTAssertEqual(supervise.state.phase, .listening)
        XCTAssertNil(supervise.state.problem)
    }

    /// ⚠️ ONE GENERATION PER JOIN, ACROSS BOTH LEGS: listen 1, coach 2, and after handing back
    /// and listening again, 3.
    func testEveryJoinHasTheNextGeneration() {
        var supervise = listening()
        supervise.handle(.takeOverPressed)
        supervise.handle(.takeoverGranted(url: "wss://coach", token: "coach-jwt"))
        XCTAssertEqual(supervise.state.generation, 2)
        supervise.handle(.stopPressed)
        supervise.handle(.listenPressed)
        XCTAssertEqual(
            supervise.handle(.listenGranted(url: "wss://listen", token: "listen-jwt")),
            [.join(.listen, generation: 3, url: "wss://listen", token: "listen-jwt")]
        )
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
        supervise.handle(.listen, .connected)
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
}
