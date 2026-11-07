import Foundation

/// What a fresh re-authentication is for. The service binds each proof to one action and
/// refuses a code or a proof spent on another (`lib/auth/native-reauth.ts`).
public enum NativeReauthAction: String, Sendable, Equatable, CaseIterable {
    /// Deleting the signed-in account.
    case deleteAccount = "delete-account"
    /// Turning two-factor authentication on or off.
    case twoFactorChange = "2fa-change"
}

/// `POST /api/auth/native/reauth/sso` and `/reauth/password`: a proof for one action now
/// stands on the service for `expiresInSeconds`.
public struct NativeReauthResponse: Codable, Sendable, Equatable {
    public let success: Bool
    public let action: String
    public let expiresInSeconds: Int
}

/// `DELETE /api/auth/delete-account`: the account is gone. ⚠️ `externalErasurePending` means
/// support data held by a vendor is still being erased; the account itself is deleted.
public struct AccountDeleteResponse: Codable, Sendable, Equatable {
    public let success: Bool
    public let accountDeleted: Bool
    public let externalErasurePending: Bool
    public let message: String?
    /// The support-data erasure's counts, kept whole and not read: nothing on a device acts on
    /// them, and the service may add a count.
    public let supportErasure: WireJSON?
}
