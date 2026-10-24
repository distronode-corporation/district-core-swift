import Foundation

public extension TypedEndpoints {
    /// A message notification's sender name: the credential, and the one read it buys.
    ///
    /// ⚠️ ITS OWN FILE FOR THE REASON ``TypedEndpoints/softphone`` HAS ONE. ⛔ Unioned
    /// into ``TypedEndpoints/all``, or `EndpointSurfaceTests`' partition assertion fails.
    ///
    /// ⛔ TYPED FROM THEIR FIRST COMMIT: `NotifyTokenRepository` decodes
    /// ``NotifyTokenResponse`` and `InboxRepository.messageSender` decodes
    /// ``MessageSenderResponse``, gated against `district-notify-token.json` and
    /// `district-message-sender.json`.
    ///
    /// ⛔ ONE PAIR, BECAUSE THE TOKEN AUTHENTICATES ONLY THE READ. Every other route
    /// answers 401 to a notify-read token, and the read answers one display name or
    /// null, which is all a lock screen may show.
    static let notifyRead: Set<EndpointID> = [.notifyToken, .messageSender]
}
