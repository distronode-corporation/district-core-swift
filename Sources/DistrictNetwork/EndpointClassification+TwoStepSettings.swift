import Foundation

public extension TypedEndpoints {
    /// Two-step verification settings (``MfaStatusResponse``, ``MfaEnrollResponse``,
    /// ``MfaConfirmResponse`` and ``MfaDisableResponse``), each gated against the service's fixture.
    static let twoStepSettings: Set<EndpointID> = [
        .mfaStatus,
        .mfaEnroll,
        .mfaConfirm,
        .mfaDisable,
    ]
}
