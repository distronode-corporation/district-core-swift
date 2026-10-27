import Foundation

/// `POST /api/auth/native/notify-token`: the notify-read token, pinned by
/// `contracts/mobile/district-notify-token.json`.
///
/// ⛔ ``token`` IS A BEARER SECRET, AND THIS TYPE KEEPS IT OUT OF EVERY STRING IT CAN,
/// as ``TelemetryTokenResponse`` does: `description`, `debugDescription` and the mirror
/// all redact it, so a `print`, an interpolation, a `dump` or an `XCTAssert` failure
/// message never carries it.
///
/// ⚠️ IT AUTHENTICATES ONE READ, `GET /api/district/messages/{id}/sender`, and only
/// while this device's native session family is alive. That is why it may live where a
/// notification extension can read it, and why it must not be mistaken for a session.
public struct NotifyTokenResponse: Codable, Sendable, Equatable {
    /// `true` on the 200. Checked like every other envelope.
    public let success: Bool

    /// The credential, a compact JWS. ⛔ Never log it; see the type note.
    public let token: String

    /// When the token expires, ISO-8601 UTC with milliseconds
    /// (`2026-11-23T00:00:00.000Z`), 30 days after the mint.
    ///
    /// ⚠️ A STRING, NOT A PARSED DATE, like `createdAt` on the device and message
    /// DTOs; ``WireInstant/parse(_:)`` reads it. The server is the authority on expiry
    /// (and on the session behind it); a client reads this only to decide when to mint
    /// again.
    public let expiresAt: String

    public init(success: Bool, token: String, expiresAt: String) {
        self.success = success
        self.token = token
        self.expiresAt = expiresAt
    }
}

extension NotifyTokenResponse: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var description: String {
        "NotifyTokenResponse(success: \(success), token: <redacted>, expiresAt: \(expiresAt))"
    }

    public var debugDescription: String {
        description
    }

    /// ⚠️ THE MIRROR TOO, because `dump(_:)` and XCTest's failure messages walk the
    /// mirror rather than calling `description`.
    public var customMirror: Mirror {
        Mirror(self, children: [
            "success": success,
            "token": "<redacted>",
            "expiresAt": expiresAt,
        ])
    }
}

/// `GET /api/district/messages/{id}/sender`: one message's sender, as a display name.
/// Pinned by `contracts/mobile/district-message-sender.json`.
///
/// ⛔ ONE NAME OR NULL, AND NOTHING ELSE, BY DESIGN. The route answers the contact's
/// name and never the number, the address or the thread, because what reads it is a
/// notification extension writing a lock-screen title. `null` is "this thread has no
/// named contact", not a failure: the extension keeps its generic text.
public struct MessageSenderResponse: Codable, Sendable, Equatable {
    /// `true` on the 200. Checked like every other envelope.
    public let success: Bool

    /// The contact's display name, or nil when the thread has no named contact.
    public let name: String?

    public init(success: Bool, name: String?) {
        self.success = success
        self.name = name
    }

    private enum CodingKeys: String, CodingKey {
        case success
        case name
    }

    /// ⚠️ WRITTEN BY HAND FOR ONE KEY: a nil ``name`` is encoded as an explicit `null`,
    /// the way the server sends it, rather than dropped the way synthesised `Encodable`
    /// drops a nil Optional. Decoding is the synthesised behaviour.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(success, forKey: .success)
        try container.encode(name, forKey: .name)
    }
}
