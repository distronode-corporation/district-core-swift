import DistrictModel
import Foundation

// Two-step verification settings (the three changes vendored by #62, the status read after
// them), in a file of their own because `ImplementedFixtures.swift` is at its 500-line ceiling.

extension ImplementedFixtures {
    static var twoStepSettings: [ImplementedFixture] {
        [
            gate("district-mfa-status.json", MfaStatusResponse.self),
            gate("district-mfa-enroll.json", MfaEnrollResponse.self),
            gate("district-mfa-confirm.json", MfaConfirmResponse.self),
            gate("district-mfa-disable.json", MfaDisableResponse.self),
        ]
    }
}
