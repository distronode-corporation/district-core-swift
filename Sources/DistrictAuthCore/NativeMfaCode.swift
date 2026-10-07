import Foundation

/// What the person is typing into the second-factor step after Sign in with Apple.
public enum NativeMfaCodeKind: Sendable, Equatable {
    /// The six digits an authenticator app shows.
    case authenticator
    /// One of the single-use recovery codes issued at enrolment (`XXXXX-XXXXX`).
    case recovery
}

/// The code the apps send to `POST /api/auth/native/mfa`, checked for SHAPE before it
/// is sent.
///
/// ⛔ THE SERVER ROUTES A CODE BY SHAPE, AND THIS MIRRORS THAT RULE RATHER THAN
/// INVENTING ONE. `second-factor.ts` strips whitespace and treats exactly six digits as
/// an authenticator code and anything else as a recovery code. So the authenticator
/// field sends six digits or nothing, and the recovery field refuses a six-digit value
/// (which the server would check against the authenticator, not the recovery codes).
///
/// ⚠️ SHAPE ONLY, NEVER VALIDITY. Whether a code is right is the server's question; a
/// wrong code that is well formed is sent and answered `invalid_credentials`. What
/// this spares is a request that cannot succeed, each of which the server counts
/// against the account's lockout.
///
/// ⚠️ THE RECOVERY RULE IS DELIBERATELY LOOSE (8 to 64 characters once spaces and
/// hyphens are gone). Issued codes are 10 characters from a 32-letter alphabet, but the
/// server normalises case and separators itself, and a client that enforced the
/// alphabet would refuse every code the day the server issued a new form.
public enum NativeMfaCode {
    /// Authenticator codes are this many digits.
    public static let authenticatorLength = 6

    /// The server's `code` schema is `z.string().min(1).max(64)`.
    static let maximumLength = 64

    /// The shortest recovery code worth sending, separators excluded.
    static let minimumRecoveryLength = 8

    /// The value to send for `input`, or nil when it cannot be a code of `kind`.
    public static func normalized(_ input: String, as kind: NativeMfaCodeKind) -> String? {
        let compact = input.filter { !$0.isWhitespace }
        switch kind {
        case .authenticator:
            return isAuthenticatorShaped(compact) ? compact : nil
        case .recovery:
            let letters = compact.filter { $0 != "-" }
            guard letters.count >= minimumRecoveryLength,
                  compact.count <= maximumLength,
                  !isAuthenticatorShaped(compact)
            else { return nil }
            return compact.uppercased()
        }
    }

    /// What an authenticator field should keep of `input` as it is typed: its ASCII
    /// digits, at most six. ⚠️ Pasted text ("123 456", "Code: 123456") keeps its digits.
    public static func authenticatorInput(_ input: String) -> String {
        String(input.filter(\.isASCIIDigit).prefix(authenticatorLength))
    }

    private static func isAuthenticatorShaped(_ compact: String) -> Bool {
        compact.count == authenticatorLength && compact.allSatisfy(\.isASCIIDigit)
    }
}

private extension Character {
    /// ⚠️ ASCII ONLY. `isNumber` admits Arabic-Indic and full-width digits, which the
    /// server's `^\d{6}$` refuses.
    var isASCIIDigit: Bool {
        isASCII && isWholeNumber
    }
}
