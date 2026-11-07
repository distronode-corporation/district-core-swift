@testable import DistrictModel
import XCTest

/// HQ by voice's models, ported from core-rust's `district-model/src/hq_voice.rs` tests so the
/// apps agree on what is joinable, what a packet is, and what a token request carries.
final class HQVoiceTests: XCTestCase {
    private func credential(roomName: String = "hq_ws-1_00000000", key: String? = "c2VjcmV0") -> HQVoiceTokenResponse {
        HQVoiceTokenResponse(
            success: true,
            token: "jwt-secret",
            url: "wss://livekit.example.test",
            roomName: roomName,
            processingRegion: "us",
            micModeWire: "push",
            sessionId: "session-secret",
            e2ee: key.map(HQVoiceTokenResponse.E2EE.init(key:))
        )
    }

    /// ⛔ ONLY AN ENCRYPTED HQ ROOM IS JOINABLE.
    func testOnlyAnEncryptedHQRoomIsJoinable() {
        XCTAssertTrue(credential().isJoinable)
        XCTAssertFalse(credential(key: nil).isJoinable)
        XCTAssertFalse(credential(key: "   ").isJoinable)
        XCTAssertFalse(credential(roomName: "meet_ws-1_x").isJoinable)
    }

    /// ⛔ THE TOKEN AND THE SESSION ID NEVER REACH A LOG.
    func testTheSecretsAreRedacted() {
        for text in [credential().description, credential().debugDescription, String(describing: credential())] {
            XCTAssertFalse(text.contains("jwt-secret"), text)
            XCTAssertFalse(text.contains("session-secret"), text)
            XCTAssertFalse(text.contains("c2VjcmV0"), text)
            XCTAssertTrue(text.contains("hq_ws-1_00000000"), text)
        }
    }

    func testPushIsTheOnlyMutedMode() {
        XCTAssertEqual(HQMicMode(wire: "push"), .push)
        for wire in ["open", "", "PUSH", "hold"] {
            XCTAssertEqual(HQMicMode(wire: wire), .open, wire)
        }
    }

    /// The service's bounds: the last six non-blank turns, each trimmed and cut to 500.
    func testTheHistoryIsBoundedAsTheServiceBoundsIt() {
        let turns = (1 ... 8).map { HQVoiceTurn(role: $0.isMultiple(of: 2) ? .model : .user, text: "turn \($0)") }
            + [HQVoiceTurn(role: .user, text: "   ")]
        let bounded = HQVoiceTurn.bounded(turns)
        XCTAssertEqual(bounded.map(\.text), ["turn 3", "turn 4", "turn 5", "turn 6", "turn 7", "turn 8"])
        let long = HQVoiceTurn.bounded([HQVoiceTurn(role: .user, text: "  " + String(repeating: "a", count: 600))])
        XCTAssertEqual(long.first?.text.count, 500)
    }

    /// A record id the service would refuse is reported without one.
    func testASelectionOnlyCarriesAnIdTheServiceAccepts() {
        XCTAssertNotNil(HQVoiceSelection(kind: .call, id: "call_1-A"))
        XCTAssertNil(HQVoiceSelection(kind: .call, id: ""))
        XCTAssertNil(HQVoiceSelection(kind: .contact, id: "Jordan Lee"))
        XCTAssertNil(HQVoiceSelection(kind: .contact, id: "é1"))
        XCTAssertNotNil(HQVoiceSelection(kind: .conversation, id: String(repeating: "a", count: 128)))
        XCTAssertNil(HQVoiceSelection(kind: .conversation, id: String(repeating: "a", count: 129)))
    }

    // MARK: - Packets (core-rust's tests/hq-voice-drafts)

    private func packet(_ json: String) -> HQVoicePacket? {
        HQVoicePacket.read(Data(json.utf8))
    }

    func testAProposalIsRead() {
        let read =
            packet(
                #"{"type":"HQ_PROPOSAL","proposalId":"p1","tool":"update_persona","args":{"greeting":"Hi"},"#
                    + #""summary":"Update the greeting.","extra":1}"#
            )
        XCTAssertEqual(read, .proposal(HQVoiceProposal(
            proposalId: "p1", tool: "update_persona", args: .object(["greeting": .string("Hi")]),
            summary: "Update the greeting."
        )))
        // An empty summary is allowed: the app shows its own sentence.
        XCTAssertNotNil(packet(#"{"type":"HQ_PROPOSAL","proposalId":"p1","tool":"t","args":{},"summary":""}"#))
    }

    func testAnInvalidProposalIsIgnored() {
        for json in [
            #"{"type":"HQ_PROPOSAL","proposalId":"","tool":"t","args":{},"summary":""}"#,
            #"{"type":"HQ_PROPOSAL","proposalId":"p1","tool":"","args":{},"summary":""}"#,
            #"{"type":"HQ_PROPOSAL","proposalId":"p1","tool":"t","args":[],"summary":""}"#,
            #"{"type":"HQ_PROPOSAL","proposalId":"p1","tool":"t","args":{}}"#,
            #"{"type":"HQ_SOMETHING","proposalId":"p1"}"#,
            #"["HQ_PROPOSAL"]"#,
            "not json",
        ] {
            XCTAssertNil(packet(json), json)
        }
    }

    func testResolutionsAreRead() {
        XCTAssertEqual(
            packet(
                #"{"type":"HQ_PROPOSAL_RESOLVED","proposalId":"p1","status":"failed","via":"voice","error":"Nope."}"#
            ),
            .resolved(HQVoiceResolution(proposalId: "p1", status: .failed, error: "Nope.", joinCallId: nil))
        )
        XCTAssertEqual(
            packet(
                #"{"type":"HQ_PROPOSAL_RESOLVED","proposalId":"p1","status":"applied","via":"voice","#
                    + #""joinCall":{"callId":"c1"}}"#
            ),
            .resolved(HQVoiceResolution(proposalId: "p1", status: .applied, error: nil, joinCallId: "c1"))
        )
        // A joinCall is kept only on an applied change, and an empty error is dropped.
        XCTAssertEqual(
            packet(
                #"{"type":"HQ_PROPOSAL_RESOLVED","proposalId":"p1","status":"cancelled","via":"voice","error":"","#
                    + #""joinCall":{"callId":"c1"}}"#
            ),
            .resolved(HQVoiceResolution(proposalId: "p1", status: .cancelled, error: nil, joinCallId: nil))
        )
    }

    func testAResolutionNotByVoiceOrOfAnUnknownStatusIsIgnored() {
        XCTAssertNil(packet(#"{"type":"HQ_PROPOSAL_RESOLVED","proposalId":"p1","status":"applied","via":"click"}"#))
        XCTAssertNil(packet(#"{"type":"HQ_PROPOSAL_RESOLVED","proposalId":"p1","status":"done","via":"voice"}"#))
        XCTAssertNil(packet(#"{"type":"HQ_PROPOSAL_RESOLVED","proposalId":"","status":"applied","via":"voice"}"#))
    }

    func testTheAgentStateIsReadOrIgnored() {
        XCTAssertEqual(HQAgentState(wire: "listening"), .listening)
        XCTAssertEqual(HQAgentState(wire: "thinking"), .thinking)
        XCTAssertEqual(HQAgentState(wire: "speaking"), .speaking)
        XCTAssertNil(HQAgentState(wire: "initializing"))
    }
}
