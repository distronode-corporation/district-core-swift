@testable import DistrictData
import DistrictModel
import DistrictNetwork
import XCTest

final class HQVoiceRepositoryTests: XCTestCase {
    private static let token = #"{"success":true,"token":"jwt","url":"wss://lk.example.test","roomName":"hq_ws_1_x","#
        + #""processingRegion":"us","micMode":"push","sessionId":"s1","e2ee":{"key":"k"}}"#

    func testATokenIsMintedWithTheLocaleAndTheBoundedHistory() async {
        let transport = RepositoryTransport(json: Self.token)
        let result = await HQRepository(client: .repositoryTest(transport))
            .voiceToken(workspaceId: "ws_1", locale: "en", history: [HQVoiceTurn(role: .model, text: "Hello")])
        XCTAssertEqual(result.successOnly?.roomName, "hq_ws_1_x")
        XCTAssertEqual(result.successOnly?.micMode, .push)
        XCTAssertEqual(
            transport.bodies,
            [#"{"history":[{"role":"model","text":"Hello"}],"locale":"en","workspaceId":"ws_1"}"#]
        )
    }

    /// ⛔ A ROOM WITHOUT ITS KEY IS NEVER HANDED TO A CALLER.
    func testAnUnencryptedCredentialIsRefused() async {
        let transport = RepositoryTransport(json: Self.token.replacingOccurrences(
            of: #","e2ee":{"key":"k"}"#,
            with: ""
        ))
        let result = await HQRepository(client: .repositoryTest(transport))
            .voiceToken(workspaceId: "ws_1", locale: "en", history: [])
        XCTAssertEqual(result.failureOnly, .decoding("HQVoiceTokenResponse is not an encrypted HQ room"))
        XCTAssertEqual(transport.bodies, [#"{"locale":"en","workspaceId":"ws_1"}"#], "an empty history is left out")
    }

    func testTheAllowanceRefusalCarriesItsCodeAndSentence() async {
        let transport = RepositoryTransport(
            json: #"{"success":false,"error":"All used.","code":"hq_voice_allowance_reached"}"#,
            status: 429
        )
        let result = await HQRepository(client: .repositoryTest(transport))
            .voiceToken(workspaceId: "ws_1", locale: "fr", history: [])
        guard case let .http(status, message, code)? = result.failureOnly else {
            return XCTFail("expected an HTTP refusal, got \(result)")
        }
        XCTAssertEqual(status, 429)
        XCTAssertEqual(message, "All used.")
        XCTAssertEqual(code, ApiErrorCode.hqVoiceAllowanceReached)
    }

    func testAVoiceProposalIsConfirmedWithItsIdAndCancelled() async {
        let transport = RepositoryTransport(queue: [
            #"{"success":true,"executed":true,"tool":"update_persona","args":{"greeting":"Hi"},"result":{"ok":true}}"#,
            #"{"success":true}"#,
        ])
        let hq = HQRepository(client: .repositoryTest(transport))
        let proposal = HQVoiceProposal(
            proposalId: "p1", tool: "update_persona", args: .object(["greeting": .string("Hi")]), summary: ""
        )
        let confirmed = await hq.confirm(workspaceId: "ws_1", voiceProposal: proposal)
        let cancelled = await hq.cancel(workspaceId: "ws_1", proposalId: "p2")
        XCTAssertEqual(confirmed.successOnly?.executed, true)
        XCTAssertNotNil(cancelled.successOnly)
        XCTAssertEqual(transport.bodies, [
            #"{"confirm":{"args":{"greeting":"Hi"},"proposalId":"p1","tool":"update_persona"},"workspaceId":"ws_1"}"#,
            #"{"proposalId":"p2","workspaceId":"ws_1"}"#,
        ])
    }

    func testTheScreenAndTheSettingsRoundTrip() async throws {
        let settings = #"{"success":true,"settings":{"voice":"Puck","length":"normal","pace":"normal","#
            + #""language":"portal","micMode":"open"}}"#
        let transport = RepositoryTransport(queue: [#"{"success":true}"#, settings, settings])
        let hq = HQRepository(client: .repositoryTest(transport))
        let reported = await hq.reportVoiceScreen(
            workspaceId: "ws_1", roomName: "hq_ws_1_x", screen: HQVoiceScreen(version: 1, page: "hq")
        )
        let read = await hq.voiceSettings(workspaceId: "ws_1")
        let saved = try await hq.saveVoiceSettings(workspaceId: "ws_1", settings: XCTUnwrap(read.successOnly))
        XCTAssertNotNil(reported.successOnly)
        XCTAssertEqual(read.successOnly?.voice, "Puck")
        XCTAssertEqual(saved.successOnly, read.successOnly)
        XCTAssertEqual(
            transport.bodies.first,
            #"{"roomName":"hq_ws_1_x","snapshot":{"page":"hq","version":1},"workspaceId":"ws_1"}"#
        )
    }
}
