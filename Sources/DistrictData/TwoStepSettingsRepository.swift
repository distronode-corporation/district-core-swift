import DistrictModel
import DistrictNetwork
import Foundation

/// Turning two-step verification on and off from an app.
///
/// ⛔ A FRESH `2fa-change` PROOF COMES FIRST, from ``NativeReauthRepository`` with
/// ``NativeReauthAction/twoFactorChange``. ``enroll()`` checks it without spending it, so a
/// restarted enrolment needs no second re-authentication; ``confirm(totp:)`` and ``disable()``
/// spend it. Without one each answers 403 `reauth_required`; a hand-off cookie or any other
/// non-browser credential that is not this app's bearer answers 403 `browser_session_required`.
/// Other refusals keep the service's `code` (`MFA_ALREADY_ENABLED`, `MFA_NOT_STARTED`,
/// `MFA_NOT_PENDING`, `mfa_code_invalid`, `rate_limited`) for the caller to act on.
public struct TwoStepSettingsRepository: Sendable {
    private let client: ApiClient

    public init(client: ApiClient) {
        self.client = client
    }

    /// Starts enrolment: a new secret, its `otpauth://` URI and a QR code of it. The factor is
    /// not on until ``confirm(totp:)``; starting again replaces an unconfirmed secret.
    public func enroll() async -> Result<MfaEnrollResponse, ApiError> {
        await client.send(DistrictEndpoints.mfaEnroll(), as: MfaEnrollResponse.self)
    }

    /// Turns the factor on with a code from the authenticator. Answers the recovery codes,
    /// which the service never shows again.
    public func confirm(totp: String) async -> Result<MfaConfirmResponse, ApiError> {
        let outcome = await client.send(DistrictEndpoints.mfaConfirm(totp: totp), as: MfaConfirmResponse.self)
        return outcome.flatMap { ResponseEnvelope.affirm("MfaConfirmResponse", $0.enrolled, $0) }
    }

    /// Turns the factor off and drops its recovery codes.
    public func disable() async -> Result<Void, ApiError> {
        let outcome = await client.send(DistrictEndpoints.mfaDisable(), as: MfaDisableResponse.self)
        return outcome.flatMap { ResponseEnvelope.affirm("MfaDisableResponse", !$0.enrolled, ()) }
    }
}
