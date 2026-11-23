import Foundation

// The refresh coordinator's answers, split from ``TokenRefreshCoordinator``
// when that file hit the 500-line `file_length` ceiling. Same module, no
// behaviour change; do not merge them back to "tidy".

/// The result of asking for an access token.
public enum AccessTokenOutcome: Sendable, Equatable {
    case available(String)

    /// Terminal. Route to login; do not retry.
    case reauthRequired(ReauthReason)

    /// Transient. The session is intact and the stored token is still valid.
    /// Fail the in-flight request, keep the user signed in, try again later.
    ///
    /// ⛔ DO NOT TREAT THIS AS A SIGN-OUT. That is the entire reason it is a
    /// separate case rather than another ``ReauthReason``.
    case retryLater(RetryReason)
}

/// Why the session ended.
public enum ReauthReason: Sendable, Equatable {
    /// Never signed in, or signed out locally.
    case noSession

    /// A refresh was in flight when the process died. The stored token is
    /// presumed spent. ⚠️ NOT A SECURITY EVENT, see ``TokenStore``.
    case interruptedRefresh

    /// The 60-day sliding window elapsed without the app being opened.
    case refreshTokenExpired

    /// The server refused the token: unknown, expired, revoked, or replayed.
    /// Indistinguishable by design.
    case refreshRejected

    /// The refresh could not be delivered, or its response was lost. The next
    /// attempt reports ``interruptedRefresh`` because the marker is
    /// intentionally still set.
    case refreshUnreachable
}

/// Why the caller should try again rather than sign out.
public enum RetryReason: Sendable, Equatable {
    /// HTTP 429 from the refresh route. The token was never consumed.
    case refreshThrottled

    /// The refresh request provably never left the device.
    case refreshNotSent

    /// The token store could not be read, a locked device, typically. The
    /// session is intact; this says nothing about whether one exists.
    case storeUnavailable

    /// The pending-refresh marker could not be written durably, so no refresh
    /// was sent. ⛔ Sending one anyway is the fall-through this case exists to
    /// refuse.
    case markerNotDurable

    /// The session this acquisition was started for was replaced while it was
    /// suspended, by a re-login or by a sign-out a login followed. A session
    /// exists, just not the one this request was made under: fail the request
    /// and let the next attempt serve the replacement, rather than reporting
    /// the login as a sign-out. ⚠️ NOT ANOTHER ``ReauthReason``, for the same
    /// reason ``AccessTokenOutcome/retryLater(_:)`` exists: the caller must
    /// not clear state or route to login.
    case sessionReplaced
}
