import Foundation

public extension TypedEndpoints {
    /// HQ by voice: each route answers a type of its own (``HQVoiceTokenResponse``,
    /// ``HQVoiceContextResponse``, ``HQVoiceSettingsResponse`` twice and
    /// ``HQProposalCancelResponse``), every one gated against the service's fixture.
    static let hqVoice: Set<EndpointID> = [
        .hqVoiceToken,
        .hqVoiceContext,
        .hqVoiceSettings,
        .saveHqVoiceSettings,
        .hqProposalCancel,
    ]
}
