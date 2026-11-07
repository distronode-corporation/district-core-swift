import DistrictModel
import Foundation

// District HQ by voice's six fixtures (monorepo branch `wip/parity-ios-server`, held until it
// lands on main), in a file of their own because `ImplementedFixtures.swift` is at its
// 500-line ceiling.

extension ImplementedFixtures {
    /// ⛔ EACH LEAVES `ContractManifest.unimplemented` WITH ITS DTO, ITS DESCRIPTOR AND THE
    /// REPOSITORY METHOD THAT DECODES IT, in one commit.
    ///
    /// ⚠️ THE ALLOWANCE REFUSAL IS THE PLAIN `{success, error, code}` ENVELOPE.
    static var hqVoice: [ImplementedFixture] {
        [
            gate("district-hq-voice-token.json", HQVoiceTokenResponse.self),
            gate("district-hq-voice-token-allowance.json", ApiErrorEnvelope.self),
            gate("district-hq-voice-context.json", HQVoiceContextResponse.self),
            gate("district-hq-voice-settings.json", HQVoiceSettingsResponse.self),
            gate("district-hq-voice-settings-put.json", HQVoiceSettingsResponse.self),
            gate("district-hq-proposal-cancel.json", HQProposalCancelResponse.self),
            gate("district-hq-voice-end.json", HQVoiceEndResponse.self),
            gate("district-hq-voice-discard.json", HQVoiceDiscardResponse.self),
        ]
    }
}
