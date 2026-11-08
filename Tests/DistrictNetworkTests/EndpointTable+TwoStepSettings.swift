@testable import DistrictModel
@testable import DistrictNetwork
import Foundation

extension EndpointTable {
    /// Two-step verification settings, read off the service's `auth/mfa` routes. ⚠️ Enrolling and
    /// disabling send no body: the first reads none, and the second reads none from an app.
    static func twoStepSettings() -> [EndpointExpectation] {
        [
            EndpointExpectation(.mfaStatus, DistrictEndpoints.mfaStatus(), .get, "\(host)/api/auth/mfa"),
            EndpointExpectation(.mfaEnroll, DistrictEndpoints.mfaEnroll(), .post, "\(host)/api/auth/mfa/enroll"),
            EndpointExpectation(
                .mfaConfirm,
                DistrictEndpoints.mfaConfirm(totp: "123456"),
                .post,
                "\(host)/api/auth/mfa/confirm",
                .json(#"{"totp":"123456"}"#)
            ),
            EndpointExpectation(.mfaDisable, DistrictEndpoints.mfaDisable(), .post, "\(host)/api/auth/mfa/disable"),
        ]
    }
}
