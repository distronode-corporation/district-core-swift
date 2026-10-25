import DistrictModel
import DistrictNetwork
import Foundation

/// Minting the notify-read token a notification extension spends on a sender's name.
///
/// ⛔ THE APP MINTS AND STORES IT; THE EXTENSION ONLY SPENDS IT. This runs under the
/// app's own session bearer (`POST /api/auth/native/notify-token` refuses anything that
/// is not a native session). The extension then builds an ``ApiClient`` whose token
/// provider answers this token and calls ``InboxRepository/messageSender(workspaceId:messageId:)``,
/// the one route it authenticates. ⛔ The extension never mints and never refreshes.
///
/// ⛔ NO STORAGE HERE, AND THAT IS THE APP'S DECISION TO MAKE. Where the token lives (a
/// keychain group the extension can read, never the session's own), when it is minted
/// again (before ``NotifyTokenResponse/expiresAt``) and its deletion at sign-out all
/// need the Security framework, which this package does not import.
///
/// ⚠️ ACCOUNT-AND-DEVICE SCOPED, LIKE ``DevicesRepository``: no `workspaceId`, because
/// the token is bound to this device's native session family, which the server reads
/// from the bearer.
public struct NotifyTokenRepository: Sendable {
    private let client: ApiClient

    public init(client: ApiClient) {
        self.client = client
    }

    /// Mint a fresh notify-read token for this device.
    ///
    /// ⚠️ ENVELOPE-CHECKED, and the token must not be blank: an empty bearer stored for
    /// the extension would make every sender lookup a 401 that reads like an expiry.
    ///
    /// ⚠️ A 401 IS "this is not a native session" (or the session lapsed); the app keeps
    /// whatever it had and the extension degrades to the generic text.
    public func mint() async -> Result<NotifyTokenResponse, ApiError> {
        let outcome = await client.send(DistrictEndpoints.notifyToken(), as: NotifyTokenResponse.self)
        return outcome
            .flatMap { ResponseEnvelope.affirm("NotifyTokenResponse", $0.success, $0) }
            .flatMap { response in
                guard !response.token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    return .failure(.decoding("NotifyTokenResponse carried no token"))
                }
                return .success(response)
            }
    }
}
