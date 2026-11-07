@testable import DistrictModel
@testable import DistrictNetwork
import Foundation

extension EndpointTable {
    /// HQ by voice, read off core-rust's `district-api/src/hq.rs` and the service's routes.
    static func hqVoice() -> [EndpointExpectation] {
        hqVoiceSession() + hqVoiceSettingsRows()
    }

    /// The session's credential, its screen reports and the proposal cancel.
    static func hqVoiceSession() -> [EndpointExpectation] {
        [
            EndpointExpectation(
                .hqVoiceToken,
                DistrictEndpoints.hqVoiceToken(
                    workspaceId: "ws_1",
                    locale: "fr",
                    history: [HQVoiceTurn(role: .user, text: "  how many calls today  ")]
                ),
                .post,
                "\(host)/api/district/hq/voice-token",
                .json(
                    #"{"history":[{"role":"user","text":"how many calls today"}],"#
                        + #""locale":"fr","workspaceId":"ws_1"}"#
                )
            ),
            EndpointExpectation(
                .hqVoiceContext,
                DistrictEndpoints.hqVoiceContext(
                    workspaceId: "ws_1",
                    roomName: "hq_ws_1_abc",
                    screen: HQVoiceScreen(
                        version: 2,
                        page: .calls,
                        selected: HQVoiceSelection(kind: .call, id: "call_1")
                    )
                ),
                .post,
                "\(host)/api/district/hq/voice-context",
                .json(
                    #"{"roomName":"hq_ws_1_abc","snapshot":{"page":"calls","selected":{"id":"call_1","kind":"call"},"#
                        + #""version":2},"workspaceId":"ws_1"}"#
                )
            ),
            EndpointExpectation(
                .hqProposalCancel,
                DistrictEndpoints.hqProposalCancel(workspaceId: "ws_1", proposalId: "p_1"),
                .post,
                "\(host)/api/district/hq/proposals/cancel",
                .json(#"{"proposalId":"p_1","workspaceId":"ws_1"}"#)
            ),
            EndpointExpectation(
                .hqVoiceEnd,
                DistrictEndpoints.hqVoiceEnd(workspaceId: "ws_1", sessionId: "s_1"),
                .post,
                "\(host)/api/district/hq/voice-end",
                .json(#"{"sessionId":"s_1","workspaceId":"ws_1"}"#)
            ),
            EndpointExpectation(
                .hqVoiceDiscard,
                DistrictEndpoints.hqVoiceDiscard(workspaceId: "ws_1", sessionId: "s_1"),
                .post,
                "\(host)/api/district/hq/voice-discard",
                .json(#"{"sessionId":"s_1","workspaceId":"ws_1"}"#)
            ),
        ]
    }

    /// The member's own voice settings.
    static func hqVoiceSettingsRows() -> [EndpointExpectation] {
        let settings = HQVoiceSettings(
            voice: "Charon",
            length: "detailed",
            pace: "normal",
            language: "fr",
            micMode: "push"
        )
        return [
            EndpointExpectation(
                .hqVoiceSettings,
                DistrictEndpoints.hqVoiceSettings(workspaceId: "ws_1"),
                .get,
                "\(host)/api/district/hq/voice-settings?workspaceId=ws_1"
            ),
            EndpointExpectation(
                .saveHqVoiceSettings,
                DistrictEndpoints.saveHqVoiceSettings(workspaceId: "ws_1", settings: settings),
                .put,
                "\(host)/api/district/hq/voice-settings",
                .json(
                    #"{"settings":{"language":"fr","length":"detailed","micMode":"push","pace":"normal","#
                        + #""voice":"Charon"},"workspaceId":"ws_1"}"#
                )
            ),
        ]
    }
}
