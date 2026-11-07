import DistrictModel
import DistrictNetwork
import Foundation

/// District HQ by voice: the credential, the screen report, the member's settings and the
/// two ways a voice proposal is resolved by a click. The room itself is the app's.
public extension HQRepository {
    /// A credential for one voice session, or the service's refusal.
    ///
    /// ⛔ EACH CALL STARTS A BILLED SESSION: call it only on the member's action. A
    /// credential that is not ``HQVoiceTokenResponse/isJoinable`` is answered as a decoding
    /// failure, so no caller can join a room without its encryption key.
    /// ⚠️ The allowance refusal is a ``ApiError/http(status:message:code:)`` with code
    /// ``ApiErrorCode/hqVoiceAllowanceReached`` (and `hq_voice_busy` at capacity); its
    /// message is the service's own sentence. The text console keeps working.
    func voiceToken(
        workspaceId: String,
        locale: String,
        history: [HQVoiceTurn]
    ) async -> Result<HQVoiceTokenResponse, ApiError> {
        let outcome = await client.send(
            DistrictEndpoints.hqVoiceToken(workspaceId: workspaceId, locale: locale, history: history),
            as: HQVoiceTokenResponse.self
        )
        return outcome
            .flatMap { ResponseEnvelope.affirm("HQVoiceTokenResponse", $0.success, $0) }
            .flatMap { credential in
                credential.isJoinable
                    ? .success(credential)
                    : .failure(.decoding("HQVoiceTokenResponse is not an encrypted HQ room"))
            }
    }

    /// Reports the member's screen to the voice agent. Fire and forget: a failure needs
    /// no handling, because the next report replaces it.
    func reportVoiceScreen(
        workspaceId: String,
        roomName: String,
        screen: HQVoiceScreen
    ) async -> Result<Void, ApiError> {
        let outcome = await client.send(
            DistrictEndpoints.hqVoiceContext(workspaceId: workspaceId, roomName: roomName, screen: screen),
            as: HQVoiceContextResponse.self
        )
        return outcome
            .flatMap { ResponseEnvelope.affirm("HQVoiceContextResponse", $0.success, $0) }
            .map { _ in () }
    }

    /// The member's own voice settings in the workspace.
    func voiceSettings(workspaceId: String) async -> Result<HQVoiceSettings, ApiError> {
        let outcome = await client.send(
            DistrictEndpoints.hqVoiceSettings(workspaceId: workspaceId),
            as: HQVoiceSettingsResponse.self
        )
        return outcome
            .flatMap { ResponseEnvelope.affirm("HQVoiceSettingsResponse", $0.success, $0) }
            .map(\.settings)
    }

    /// Saves the member's voice settings and answers them as the service stored them.
    func saveVoiceSettings(workspaceId: String, settings: HQVoiceSettings) async -> Result<HQVoiceSettings, ApiError> {
        let outcome = await client.send(
            DistrictEndpoints.saveHqVoiceSettings(workspaceId: workspaceId, settings: settings),
            as: HQVoiceSettingsResponse.self
        )
        return outcome
            .flatMap { ResponseEnvelope.affirm("HQVoiceSettingsResponse", $0.success, $0) }
            .map(\.settings)
    }

    /// Applies a voice proposal by a click: its tool and arguments, untouched, with its id,
    /// so the service records the proposal as resolved.
    func confirm(
        workspaceId: String,
        voiceProposal proposal: HQVoiceProposal
    ) async -> Result<HqConfirmation, ApiError> {
        let outcome = await client.send(
            DistrictEndpoints.hqConfirm(
                workspaceId: workspaceId,
                tool: proposal.tool,
                args: JSONValue.carrying(proposal.args),
                proposalId: proposal.proposalId
            ),
            as: HqConfirmResponse.self
        )
        return outcome
            .flatMap { ResponseEnvelope.affirm("HqConfirmResponse", $0.success, $0) }
            .flatMap { response in
                response.tool == proposal.tool
                    ? .success(HqConfirmation(tool: response.tool, executed: response.executed))
                    : .failure(.decoding("HqConfirmResponse echoed a different tool than the one proposed"))
            }
    }

    /// Ends a running session. Answers whether this call ended it.
    func endVoice(workspaceId: String, sessionId: String) async -> Result<Bool, ApiError> {
        let outcome = await client.send(
            DistrictEndpoints.hqVoiceEnd(workspaceId: workspaceId, sessionId: sessionId),
            as: HQVoiceEndResponse.self
        )
        return outcome
            .flatMap { ResponseEnvelope.affirm("HQVoiceEndResponse", $0.success, $0) }
            .map(\.ended)
    }

    /// Discards a session that never started. Answers whether it was discarded.
    func discardVoice(workspaceId: String, sessionId: String) async -> Result<Bool, ApiError> {
        let outcome = await client.send(
            DistrictEndpoints.hqVoiceDiscard(workspaceId: workspaceId, sessionId: sessionId),
            as: HQVoiceDiscardResponse.self
        )
        return outcome
            .flatMap { ResponseEnvelope.affirm("HQVoiceDiscardResponse", $0.success, $0) }
            .map(\.discarded)
    }

    /// Cancels a voice proposal by a click.
    func cancel(workspaceId: String, proposalId: String) async -> Result<Void, ApiError> {
        let outcome = await client.send(
            DistrictEndpoints.hqProposalCancel(workspaceId: workspaceId, proposalId: proposalId),
            as: HQProposalCancelResponse.self
        )
        return outcome
            .flatMap { ResponseEnvelope.affirm("HQProposalCancelResponse", $0.success, $0) }
            .map { _ in () }
    }
}
