import Foundation

/// `GET /api/district/workspace/email-identity`, the name and Reply-to address this
/// workspace's email goes out under, and the caller's own address.
///
/// ⚠️ ``senderName`` AND ``replyTo`` ARE NEVER NULL; `""` IS "NOT SET". An empty sender name
/// sends as the service's default name, and an empty Reply-to sends replies to the member who
/// sent the email (else the owner). ``memberEmail`` is that member's address when it is the
/// caller, which is what a form shows as the meaning of an empty Reply-to.
///
/// ⛔ A ROUTE OF ITS OWN, NOT A KEY ON `workspace/config`. That response is pinned byte for
/// byte by its fixture, so the Reply-to never joins it; read this route instead.
public struct EmailIdentityResponse: Codable, Sendable, Equatable {
    public let success: Bool
    public let senderName: String
    public let replyTo: String
    /// The caller's own address. ⚠️ Only on the read; the PATCH does not echo it.
    public let memberEmail: String

    public init(success: Bool, senderName: String, replyTo: String, memberEmail: String) {
        self.success = success
        self.senderName = senderName
        self.replyTo = replyTo
        self.memberEmail = memberEmail
    }
}

/// `PATCH /api/district/workspace/email-identity`: the two values as stored after the write.
///
/// ⚠️ ITS OWN TYPE BECAUSE THE BODY IS NOT THE READ'S: it has no `memberEmail`. The values
/// come back trimmed, and a Reply-to normalised, so the response is the new baseline and no
/// re-read is needed.
public struct EmailIdentitySaveResponse: Codable, Sendable, Equatable {
    public let success: Bool
    public let senderName: String
    public let replyTo: String

    public init(success: Bool, senderName: String, replyTo: String) {
        self.success = success
        self.senderName = senderName
        self.replyTo = replyTo
    }
}

/// The bounds the email-identity PATCH validates, mirroring the route.
public enum EmailIdentity {
    /// `MAX_SENDER_NAME_LENGTH`, counted as the route counts it (UTF-16 code units, before
    /// trimming).
    public static let maximumSenderNameLength = 100
    /// The route's bound on the raw Reply-to, before it is checked as one address.
    public static let maximumReplyToLength = 320
}
