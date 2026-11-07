import DistrictModel
import DistrictNetwork
import Foundation

/// A fresh re-authentication for one action, and deleting the account with it.
///
/// ⛔ EVERY ACCOUNT TYPE RE-AUTHENTICATES THE SAME WAY BEFORE A DELETION: a fresh sign-in at its
/// provider (``reauthenticate(action:code:codeVerifier:redirectUri:)``) or its password
/// (``reauthenticate(action:password:code:)``), then the typed email (``deleteAccount(confirmation:)``).
/// A refusal keeps the service's `code` (`MFA_REQUIRED`, `incorrect_password`,
/// `reauth_failed`, `reauth_required`, `confirmation_mismatch`) for the caller to act on.
public struct NativeReauthRepository: Sendable {
    private let client: ApiClient

    public init(client: ApiClient) {
        self.client = client
    }

    /// Exchanges the re-authentication sheet's code. Answers how long the proof stands.
    public func reauthenticate(
        action: NativeReauthAction,
        code: String,
        codeVerifier: String,
        redirectUri: String
    ) async -> Result<Int, ApiError> {
        await proof(
            action,
            DistrictEndpoints.nativeReauthSso(
                action: action,
                code: code,
                codeVerifier: codeVerifier,
                redirectUri: redirectUri
            )
        )
    }

    /// Re-authenticates with the account's password, and its authenticator code once asked.
    public func reauthenticate(
        action: NativeReauthAction,
        password: String,
        code: String? = nil
    ) async -> Result<Int, ApiError> {
        await proof(action, DistrictEndpoints.nativeReauthPassword(action: action, password: password, code: code))
    }

    /// Deletes the signed-in account. Answers whether vendor-held support data is still being
    /// erased (the account itself is gone either way).
    public func deleteAccount(confirmation: String) async -> Result<Bool, ApiError> {
        let outcome = await client.send(
            DistrictEndpoints.deleteAccount(confirmation: confirmation),
            as: AccountDeleteResponse.self
        )
        return outcome
            .flatMap { ResponseEnvelope.affirm("AccountDeleteResponse", $0.success && $0.accountDeleted, $0) }
            .map(\.externalErasurePending)
    }

    /// ⚠️ A PROOF FOR ANOTHER ACTION IS NOT THIS ONE'S, so it is refused rather than trusted.
    private func proof(_ action: NativeReauthAction, _ request: ApiRequestDescriptor) async -> Result<Int, ApiError> {
        let outcome = await client.send(request, as: NativeReauthResponse.self)
        return outcome
            .flatMap { ResponseEnvelope.affirm("NativeReauthResponse", $0.success, $0) }
            .flatMap { response in
                response.action == action.rawValue
                    ? .success(response.expiresInSeconds)
                    : .failure(.decoding("NativeReauthResponse is for another action"))
            }
    }
}
