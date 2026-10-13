import DistrictL10n
import Foundation

/// The single normalised error type every District API call resolves to.
///
/// ⚠️ The server answers errors in THREE different envelope shapes
/// (`{success:false,error}`, `{error}`, `{error,code}`). Normalising them into
/// one type is a real piece of behaviour with its own tests; this enum is the
/// destination that work decodes into.
public enum ApiError: Error, Equatable, Sendable {
    /// The request reached the server and it answered with a non-2xx status.
    /// `message` is whatever the envelope carried, already unwrapped. `code` is the
    /// machine-readable name of the refusal, from the body's `code` or else the
    /// `X-Distronode-Error-Code` header, and nil when the server named none.
    ///
    /// ⚠️ `code` DEFAULTS TO nil, AND A REFUSAL BUILT ON THIS SIDE (a file too large to
    /// send, a blank draft) HAS NONE. Its `message` comes from the catalog, so it is in
    /// the active language.
    case http(status: Int, message: String?, code: String? = nil)
    /// The request never produced a response (DNS, TLS, timeout, offline).
    case transport(String)
    /// A 2xx response whose body did not match the declared contract.
    case decoding(String)

    /// A human-readable reason suitable for a UI surface.
    ///
    /// ⚠️ Deliberately does NOT invent copy for the `http` case when the server
    /// sent no message. A caller that needs a fallback string owns that choice;
    /// inventing one here would make a contract regression look like a normal
    /// error to every screen.
    public var message: String? {
        switch self {
        case let .http(_, message, _):
            message
        case let .transport(reason):
            reason
        case let .decoding(reason):
            reason
        }
    }

    /// The HTTP status, when there was one.
    public var httpStatus: Int? {
        guard case let .http(status, _, _) = self else { return nil }
        return status
    }

    /// The refusal's error code, when the server sent one.
    ///
    /// ⛔ BRANCH ON THIS, NEVER ON ``message``. The message is product copy, rewritten
    /// without a version bump, and English whatever the reader's language.
    public var code: String? {
        guard case let .http(_, _, code) = self else { return nil }
        return code
    }

    /// The sentence to show for this failure in the reader's language, or nil when the
    /// screen should show its own.
    ///
    /// ⛔ IN ENGLISH IT IS ``message``, EXACTLY AS BEFORE: the server's sentence, or the
    /// reason this client wrote. In French it is the catalog sentence for ``code``, and
    /// nil for a failure with no code this build knows, so the screen shows its own French
    /// sentence. Never the English wire text on a French screen.
    ///
    /// ⚠️ A REFUSAL THIS CLIENT BUILT HAS NO CODE, SO IN FRENCH IT IS nil HERE TOO. Its
    /// ``message`` is catalog text in the active language; a screen that wants that
    /// specific reason reads it there.
    public var localizedMessage: String? {
        switch L10nRuntime.locale {
        case .en:
            message
        case .frCA:
            code.flatMap { ApiErrorText.sentence(for: $0) }
        }
    }

    /// Whether the failure is an authentication failure the token refresh
    /// coordinator should react to. 403 is deliberately excluded: it means
    /// "authenticated but not permitted", and refreshing a token cannot fix it.
    public var isUnauthorized: Bool {
        httpStatus == 401
    }
}
