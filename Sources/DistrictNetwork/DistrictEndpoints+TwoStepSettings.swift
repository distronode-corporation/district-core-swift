import DistrictModel
import Foundation

/// Two-step verification settings: enrolling an authenticator, confirming it, and turning it off.
///
/// ⛔ EACH ONE NEEDS A FRESH `2fa-change` PROOF FIRST (``nativeReauthSso(action:code:codeVerifier:
/// redirectUri:)`` or ``nativeReauthPassword(action:password:code:)`` with
/// ``NativeReauthAction/twoFactorChange``). The proof lives on the service and is keyed on this
/// installation's bearer, so nothing here carries it; without one the service answers 403
/// `reauth_required`. Enrolling checks the proof without spending it, and confirming or
/// disabling spends it.
public extension DistrictEndpoints {
    /// Mints a new authenticator secret. ⚠️ No body: the route reads none.
    static func mfaEnroll() -> ApiRequestDescriptor {
        ApiRequestDescriptor(.mfaEnroll, .post, DistrictPaths.mfaEnroll)
    }

    /// Proves the authenticator works with one of its codes, which turns the factor on.
    static func mfaConfirm(totp: String) -> ApiRequestDescriptor {
        ApiRequestDescriptor(
            .mfaConfirm,
            .post,
            DistrictPaths.mfaConfirm,
            body: .json(.object([("totp", .string(totp))]))
        )
    }

    /// Turns the factor off. ⛔ NO BODY AND NO PASSWORD: for an app the `2fa-change` proof takes
    /// the password's place, which is also how an account without a password turns it off.
    static func mfaDisable() -> ApiRequestDescriptor {
        ApiRequestDescriptor(.mfaDisable, .post, DistrictPaths.mfaDisable)
    }
}

extension DistrictPaths {
    /// ⚠️ UNDER `auth/mfa`, NOT `auth/native`: the website's own routes, which take a native
    /// proof. Here rather than in `DistrictPaths.swift`, which is at its 500-line ceiling.
    static let mfaEnroll = ["api", "auth", "mfa", "enroll"]
    static let mfaConfirm = ["api", "auth", "mfa", "confirm"]
    static let mfaDisable = ["api", "auth", "mfa", "disable"]
}
