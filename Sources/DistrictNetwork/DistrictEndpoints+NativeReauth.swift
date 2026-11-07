import DistrictModel
import Foundation

/// A fresh re-authentication, and the account deletion it guards.
///
/// ⛔ THE ACTION IS SENT ON EVERY STEP AND MUST BE THE SAME ONE: the sheet's address, the code
/// exchange and the proof are each bound to it, and the service refuses a mismatch.
public extension DistrictEndpoints {
    /// Exchanges the code the re-authentication sheet handed back for a proof. ⚠️ The service
    /// also checks the code was issued to this installation and this account.
    static func nativeReauthSso(
        action: NativeReauthAction,
        code: String,
        codeVerifier: String,
        redirectUri: String
    ) -> ApiRequestDescriptor {
        ApiRequestDescriptor(
            .nativeReauthSso,
            .post,
            DistrictPaths.nativeReauthSso,
            body: .json(.object([
                ("action", .string(action.rawValue)),
                ("code", .string(code)),
                ("codeVerifier", .string(codeVerifier)),
                ("redirectUri", .string(redirectUri)),
            ]))
        )
    }

    /// A proof from the account's password, and its authenticator code when two-factor is on
    /// (the first try without one answers `MFA_REQUIRED`).
    static func nativeReauthPassword(
        action: NativeReauthAction,
        password: String,
        code: String? = nil
    ) -> ApiRequestDescriptor {
        ApiRequestDescriptor(
            .nativeReauthPassword,
            .post,
            DistrictPaths.nativeReauthPassword,
            body: .json(.object([
                ("action", .string(action.rawValue)),
                ("password", .string(password)),
                ("code", code.map(JSONValue.string)),
            ]))
        )
    }

    /// Deletes the signed-in account, spending a `delete-account` proof.
    ///
    /// ⛔ `confirmation` IS THE ACCOUNT'S EMAIL ADDRESS, TYPED: the service compares it without
    /// case before it spends the proof, so a typo costs nothing (`confirmation_mismatch`).
    static func deleteAccount(confirmation: String) -> ApiRequestDescriptor {
        ApiRequestDescriptor(
            .deleteAccount,
            .delete,
            DistrictPaths.deleteAccount,
            body: .json(.object([("confirmation", .string(confirmation))]))
        )
    }
}

extension DistrictPaths {
    /// A fresh re-authentication: the sheet's code exchanged, or the password. ⚠️ Here rather
    /// than in `DistrictPaths.swift`, which is at its 500-line ceiling.
    static let nativeReauthSso = ["api", "auth", "native", "reauth", "sso"]
    static let nativeReauthPassword = ["api", "auth", "native", "reauth", "password"]
    /// ⚠️ UNDER `auth`, NOT `auth/native`: the website's own route, which takes a native proof.
    static let deleteAccount = ["api", "auth", "delete-account"]
}
