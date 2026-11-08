import DistrictModel
import Foundation

// Two-step verification settings (vendored by #62), in a file of their own because
// `ImplementedFixtures.swift` is at its 500-line ceiling. ⚠️ The status read (`GET auth/mfa`)
// has no fixture yet, so no client here calls it.

extension ImplementedFixtures {
    static var twoStepSettings: [ImplementedFixture] {
        [
            gate("district-mfa-enroll.json", MfaEnrollResponse.self),
            gate("district-mfa-confirm.json", MfaConfirmResponse.self),
            gate("district-mfa-disable.json", MfaDisableResponse.self),
        ]
    }
}
