import DistrictModel
import Foundation

/// The second factor the Apple exchange asked for: what
/// ``CodeExchangeResult/mfaRequired(_:)`` carries, and what
/// ``NativeAuthClient/submitMfaCode(_:)`` spends.
///
/// ⛔ ``ticket`` IS A CREDENTIAL, HALF OF ONE SIGN-IN. The server minted it after
/// verifying the Apple identity token, bound it to this install, this platform and the
/// account's session cutoff, and will trade it once for the native grant. Keep it in
/// memory for the one attempt; never log it, persist it or put it in a URL.
///
/// ⚠️ ``expiresAt`` IS OPTIONAL BECAUSE PARSING CAN FAIL, NOT BECAUSE THE SERVER OMITS
/// IT. A nil expiry means "this client cannot tell", and the server stays the judge: an
/// expired ticket is answered `400 invalid_grant`, which is
/// ``NativeMfaResult/ticketRejected``. The local check in ``isExpired(at:)`` only spares a
/// request that is certain to fail.
public struct NativeMfaChallenge: Sendable, Equatable {
    public let ticket: String
    public let expiresAt: Date?

    public init(ticket: String, expiresAt: Date?) {
        self.ticket = ticket
        self.expiresAt = expiresAt
    }

    /// The challenge a 401 body describes, or nil when it is not an MFA challenge.
    ///
    /// ⛔ KEYED ON `error == "mfa_required"` AND A NON-EMPTY TICKET, BOTH. A 401 that is
    /// anything else (a proxy's page, a future refusal) stays ambiguous for the caller,
    /// and an empty ticket could never be redeemed, so showing a code sheet for it would
    /// ask for a code that cannot work.
    init?(_ response: NativeMfaRequiredResponse) {
        guard response.error == NativeMfaRequiredResponse.mfaRequiredError, !response.mfaTicket.isEmpty else {
            return nil
        }
        self.init(ticket: response.mfaTicket, expiresAt: WireInstant.parse(response.mfaTicketExpiresAt))
    }

    /// Whether the ticket has certainly expired at `now`.
    ///
    /// ⚠️ FALSE WHEN THE EXPIRY IS UNKNOWN: an unparseable instant is not evidence of
    /// expiry, and the server answers the question either way.
    public func isExpired(at now: Date) -> Bool {
        guard let expiresAt else { return false }
        return now >= expiresAt
    }
}

/// One code submission, as `POST /api/auth/native/mfa`'s zod schema describes it.
///
/// ⛔ `deviceId` AND `platform` MUST BE THE VALUES THE APPLE LEG WAS CALLED WITH. The
/// ticket is bound to both, and a mismatch is the opaque `400 invalid_grant` that sends
/// the person back to the Apple sheet. Build this from the same container values the
/// ``AppleNativeSignInRequest`` used.
///
/// ⚠️ `Encodable` FOR THE SAME REASON ``AppleNativeSignInRequest`` IS: the key names
/// live on the type, and `deviceName` is omitted when nil (synthesised
/// `encodeIfPresent`), so the device list never shows a blank row.
public struct NativeMfaRequest: Encodable, Sendable, Equatable {
    public let mfaTicket: String
    /// An authenticator code or a recovery code; the server routes it by shape. See
    /// `DistrictAuthCore.NativeMfaCode` for what the apps send.
    public let code: String
    public let deviceId: String
    public let deviceName: String?
    /// ⛔ `z.enum(["ios", "android", "macos"])`, from a ``ClientPlatform``, never a free
    /// string.
    public let platform: String

    public init(
        challenge: NativeMfaChallenge,
        code: String,
        deviceId: String,
        deviceName: String?,
        platform: ClientPlatform = .ios
    ) {
        mfaTicket = challenge.ticket
        self.code = code
        self.deviceId = deviceId
        self.deviceName = deviceName
        self.platform = platform.wire
    }
}

/// What one code submission learned.
///
/// ⛔ TWO REFUSALS, AND THEY MEAN OPPOSITE THINGS TO THE PERSON. ``invalidCode`` (the
/// route's 401) leaves the ticket usable until it expires, so the sheet stays open and
/// the person types again; ``ticketRejected`` (its 400) means the ticket is gone, so the
/// sheet closes and sign-in starts again from the Apple button. Swapping them either
/// strands a person on a sheet that can never succeed or throws away a ticket over a
/// typo.
public enum NativeMfaResult<Tokens: Sendable>: Sendable {
    case success(Tokens)

    /// HTTP 401 `invalid_credentials`: a wrong code, a spent code, or a locked account
    /// (the server answers all three alike, as the web leg does). The ticket stands.
    case invalidCode

    /// HTTP 400 `invalid_grant`: the ticket expired, was spent, belongs to another
    /// install, or the account changed under it. Start again from the Apple sheet.
    case ticketRejected

    /// HTTP 429, refused before the code was looked at. The ticket stands.
    case rateLimited

    /// No usable answer: an I/O failure, a 5xx, or a 200 this build cannot parse.
    case transportFailure
}

extension NativeMfaResult: Equatable where Tokens: Equatable {}
