import Foundation

/// The 401 `POST /api/auth/native/apple` answers when the account behind a verified
/// Apple ID has an authenticator (TOTP) enrolled. Fixture:
/// `district-native-apple-mfa-required.json`.
///
/// ⛔ NOT A REFUSAL. The Apple identity is proven; the server is asking for the second
/// factor before it issues anything. No session, access token or sign-in event exists
/// yet, and none will until `POST /api/auth/native/mfa` is answered with ``mfaTicket``
/// and a code (see `NativeAuthClient.submitMfaCode(_:)`). Added server-side 2026-10-06:
/// before it, an enrolled account got a 60-day device credential on the Apple ID alone.
///
/// ⛔ ``mfaTicket`` IS A SHORT-LIVED CREDENTIAL. Single use, bound to this install and
/// platform, held in memory for one attempt and never logged or persisted.
///
/// ⚠️ ``mfaTicketExpiresAt`` IS AN ISO-8601 STRING, as every timestamp in this module
/// is; ``WireInstant`` parses it where a decision is made.
///
/// ⚠️ ``error`` IS WHAT A CLIENT KEYS ON (`"mfa_required"`), the way the web leg does.
/// ``code`` (`"MFA_REQUIRED"`) and ``message`` are carried for the strict contract gate,
/// which re-encodes and compares key sets, so an undeclared key would fail it.
public struct NativeMfaRequiredResponse: Codable, Sendable, Equatable {
    /// The discriminator a client may branch on.
    public static let mfaRequiredError = "mfa_required"

    public let error: String
    public let code: String
    /// The server's own sentence. ⚠️ The apps word the step themselves.
    public let message: String
    public let mfaTicket: String
    public let mfaTicketExpiresAt: String

    public init(error: String, code: String, message: String, mfaTicket: String, mfaTicketExpiresAt: String) {
        self.error = error
        self.code = code
        self.message = message
        self.mfaTicket = mfaTicket
        self.mfaTicketExpiresAt = mfaTicketExpiresAt
    }
}
