import Foundation

public extension TypedEndpoints {
    /// Two-step verification settings (``MfaEnrollResponse``, ``MfaConfirmResponse`` and
    /// ``MfaDisableResponse``), each gated against the service's fixture.
    static let twoStepSettings: Set<EndpointID> = [
        .mfaEnroll,
        .mfaConfirm,
        .mfaDisable,
    ]
}
