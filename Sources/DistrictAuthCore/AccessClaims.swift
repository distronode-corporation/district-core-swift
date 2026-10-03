import Foundation

/// The three claims this client reads out of its own native access token.
///
/// ⛔ A READ, NOT A VERIFICATION, AND NOTHING MAY TREAT IT AS ONE. The token is an
/// HS256 JWT whose key never leaves the server, so this client cannot check the
/// signature and does not try: these values are only as trustworthy as the
/// Keychain the token came out of. That is enough for what they are used for,
/// which is reading facts about THIS session (whose ring is this, when does the
/// bearer lapse), and it is never enough for an access decision. The server
/// verifies every request it is presented with, and a forged token here only
/// fools the process that forged it.
///
/// ⛔ ALL THREE ARE REQUIRED, MATCHING `verifyNativeAccessToken`, which refuses a
/// token missing any of them. A token that decodes here without one was not
/// minted by the server, so answering nil is the honest result rather than a
/// half-filled value a caller would have to second-guess.
///
/// ⚠️ WHY THE DESKTOP NEEDS IT AT ALL: a `call_ringing` telemetry event reaches
/// every socket in the workspace and names the members it rings by user id, the
/// `sub` of their bearer. A Mac rings only when its own `sub` is in the list. See
/// `DistrictLive.DesktopRingGate`.
public struct AccessClaims: Sendable, Equatable {
    /// `sub`: the account's user id.
    public let userId: String

    /// `did`: the installation id the token was minted for. The server recovers it
    /// from the bearer for device-scoped routes; it is never sent as an argument.
    public let deviceId: String

    /// `exp`, in seconds since the epoch, as the token states it.
    public let expiresAtSeconds: Int64

    /// `exp` as a date.
    public var expiresAt: Date {
        Date(timeIntervalSince1970: TimeInterval(expiresAtSeconds))
    }

    /// Read the claims out of a compact JWT.
    ///
    /// - Returns: nil for anything that is not three dot-separated segments, a
    ///   payload that is not base64url JSON, or a payload without a non-empty
    ///   string `sub` and `did` and an integer `exp`.
    ///
    /// ⚠️ NIL RATHER THAN A THROWN REASON. Every caller has one branch for "no
    /// usable claims" and none of them could do anything different per cause; the
    /// value also comes from the Keychain, not from a person, so there is nobody
    /// to show a reason to.
    public init?(jwt: String) {
        let segments = jwt.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count == 3 else { return nil }
        guard let payload = Base64URL.decode(String(segments[1])) else { return nil }
        guard let wire = try? JSONDecoder().decode(Wire.self, from: payload) else { return nil }
        guard !wire.sub.isEmpty, !wire.did.isEmpty else { return nil }
        userId = wire.sub
        deviceId = wire.did
        expiresAtSeconds = wire.exp
    }

    /// ⚠️ `exp` AS `Int64`, NOT `Double`. The server writes whole seconds, and a
    /// fractional or string `exp` is a token it did not mint.
    private struct Wire: Decodable {
        let sub: String
        let did: String
        let exp: Int64
    }
}
