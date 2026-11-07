import Foundation

public extension TypedEndpoints {
    /// A fresh re-authentication (``NativeReauthResponse`` twice) and the account deletion
    /// (``AccountDeleteResponse``), each gated against the service's fixture.
    static let nativeReauth: Set<EndpointID> = [
        .nativeReauthSso,
        .nativeReauthPassword,
        .deleteAccount,
    ]
}
