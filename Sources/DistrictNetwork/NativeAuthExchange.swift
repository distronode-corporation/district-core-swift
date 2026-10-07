import Foundation

/// One code exchange, as the token route's schema describes it.
public struct CodeExchangeRequest: Sendable, Equatable {
    /// The iOS app's value, which is what ``clientPlatform`` defaults to.
    ///
    /// ⛔ The server's schema is `z.enum(["ios", "android", "linux", "macos"])`.
    /// Anything else is a 400 that reads exactly like a rejected code.
    public static let platform = ClientPlatform.ios.wire

    /// Which app is signing in.
    ///
    /// ⚠️ THE APP'S CHOICE, NEVER A SCREEN'S, which is why it defaults to ``ClientPlatform/ios``
    /// and the macOS app sets it once where it builds its requests. A value
    /// chosen per call is how a device ends up listed as the wrong platform in the
    /// settings device list. See ``ClientPlatform``.
    public let clientPlatform: ClientPlatform

    public let code: String
    public let codeVerifier: String

    /// ⛔ Must match `NATIVE_REDIRECT_ALLOWLIST` byte for byte. The server
    /// compares it literally, twice: once against the allowlist and once against
    /// the value the code was minted for.
    public let redirectUri: String

    /// Opaque install id. Scopes per-device sign-out; 8...200 characters.
    public let deviceId: String

    /// Display only, shown in the settings device list. Never trusted.
    ///
    /// ⚠️ Optional server-side, and OMITTED rather than sent empty when nil,
    /// see ``NativeAuthClient/exchangeCode(_:)``.
    public let deviceName: String?

    public init(
        code: String,
        codeVerifier: String,
        redirectUri: String,
        deviceId: String,
        deviceName: String?,
        clientPlatform: ClientPlatform = .ios
    ) {
        self.clientPlatform = clientPlatform
        self.code = code
        self.codeVerifier = codeVerifier
        self.redirectUri = redirectUri
        self.deviceId = deviceId
        self.deviceName = deviceName
    }
}

/// What a code exchange learned. Mirrors `DistrictAuthCore.RefreshResult`'s
/// shape minus the `notSent` case, which only matters to a credential that must
/// not be re-presented, a code is single-use and the flow restarts either way.
///
/// ⚠️ GENERIC OVER THE TOKEN TYPE for the reason ``NativeAuthTokenWire`` exists:
/// `NativeTokens` lives in `DistrictAuthCore`, which this module does not
/// depend on. Callers write `case let .success(tokens)` and never name it.
public enum CodeExchangeResult<Tokens: Sendable>: Sendable {
    case success(Tokens)

    /// ⚠️ THE 400. The token route answers one opaque `invalid_grant` for every
    /// refusal, expired, replayed, PKCE mismatch, redirect mismatch, and all
    /// four mean "start the login over".
    case rejected

    case rateLimited

    /// ⛔ THE APPLE ROUTE'S 403, AND ONLY THE APPLE ROUTE'S. `POST
    /// /api/auth/native/apple` answers `403 {"error":"no_account"}` when the
    /// Apple ID resolves to no existing account, because sign-in never creates
    /// one: creating an account from an unknown Apple ID falls foul of App Store
    /// Review Guideline 3.1.1 ("account registration"). It is not a refusal to retry
    /// and not a transport fault: the person needs an invitation, and trying
    /// again cannot change the answer.
    ///
    /// ⚠️ ``NativeAuthClient/exchangeCode(_:)`` NEVER PRODUCES IT. The PKCE route
    /// signs in an account the web login already resolved, so a 403 there stays
    /// ambiguous (`transportFailure`).
    case noAccount

    /// ⛔ THE APPLE ROUTE'S 401 `mfa_required`, AND ONLY THE APPLE ROUTE'S. The Apple ID
    /// is verified and the account has an authenticator enrolled, so the server asks for
    /// the code before it issues anything. Show the code step and spend the challenge
    /// with ``NativeAuthClient/submitMfaCode(_:)``; nothing has been signed in yet.
    ///
    /// ⚠️ ``NativeAuthClient/exchangeCode(_:)`` NEVER PRODUCES IT: the browser leg asks
    /// for the code on the web page before a PKCE code exists.
    case mfaRequired(NativeMfaChallenge)

    /// No usable answer: an I/O failure, a 5xx, or a 200 this build cannot
    /// parse.
    case transportFailure
}

extension CodeExchangeResult: Equatable where Tokens: Equatable {}
