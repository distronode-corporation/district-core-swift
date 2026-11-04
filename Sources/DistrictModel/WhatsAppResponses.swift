import Foundation

/// `GET /api/district/workspace/whatsapp/window?workspaceId&to[&senderId]`, whether the
/// composer may send free-form WhatsApp text to `to` now.
///
/// ⛔ A PREVIEW, NEVER THE GATE. `messages/send` enforces the same 24-hour window itself
/// and answers 409 `whatsapp_window_closed` when it has shut between this read and the
/// send, so a caller handles that refusal whatever this said.
///
/// ⚠️ ``senderId`` IS THE SENDER WHOSE WINDOW THIS IS, and the send must go out on it.
/// Without a `senderId` in the request the server picks the sender the customer last
/// wrote to (the same rule the send applies), and names it here, so the composer shows
/// and sends from one number.
public struct WhatsAppWindowResponse: Codable, Sendable {
    public let success: Bool
    public let window: WhatsAppWindow
    /// The workspace's WhatsApp sender this window belongs to. Send with it as
    /// `whatsappSenderId`, and read its templates with it.
    public let senderId: String
    /// The number of ours the customer's latest inbound WhatsApp message reached, or nil
    /// when they never wrote: the thread's "via" label.
    ///
    /// ⛔ NOT THE SENDING NUMBER. It says which number RECEIVED, whatever ``senderId`` is.
    public let receivedOn: String?
}

/// The 24-hour customer-service window on one sender for one customer.
public struct WhatsAppWindow: Codable, Sendable, Equatable {
    /// True while free-form text may be sent. When false only an approved template may.
    public let open: Bool
    /// ISO-8601, when the open window closes; nil when it is closed.
    public let expiresAt: String?
}

/// `GET /api/district/workspace/whatsapp/templates?workspaceId&senderId`, the templates
/// one sender may send, approved and pending, by name then language.
public struct WhatsAppTemplatesResponse: Codable, Sendable {
    public let success: Bool
    public let templates: [WhatsAppTemplate]
}

/// One WhatsApp message template.
///
/// ⚠️ ONLY ``isSendable`` ONES MAY BE OFFERED FOR SENDING. A pending template is listed so
/// the picker can say it is waiting on Meta; a send naming it is refused with 400
/// `whatsapp_template_invalid`.
public struct WhatsAppTemplate: Codable, Sendable, Equatable {
    /// Sent back as `templateId`.
    public let id: String
    /// The sender this template belongs to, or nil when it is tied to no one sender (any
    /// sender on the same provider and business account may send it).
    public let senderId: String?
    /// Meta's template name, e.g. `appointment_reminder`.
    public let name: String
    /// Meta's language tag, e.g. `en_US` or `fr_CA`.
    public let language: String
    /// Meta's category, `UTILITY`, `MARKETING` or `AUTHENTICATION`. Raw.
    public let category: String
    /// `approved` or `pending`. Raw, like every vocabulary here. See ``isSendable``.
    public let status: String
    /// The body text with its placeholders (`{{1}}`, or named, `{{first_name}}`).
    public let body: String
    /// How many numbered placeholders (`{{1}}` to `{{n}}`) the body takes, or nil when the
    /// body uses named ones or could not be read.
    ///
    /// ⚠️ THE SEND IS REFUSED (400 `whatsapp_template_invalid`) WHEN THE VARIABLES SENT DO
    /// NOT MATCH THE TEMPLATE, so a picker collects exactly this many.
    public let variableCount: Int?

    /// The status a template must have to be sent.
    public static let approvedStatus = "approved"

    /// True when this template may be sent now.
    public var isSendable: Bool {
        status == Self.approvedStatus
    }

    /// The body with `{{1}}` to `{{n}}` replaced by `variables`, in order: the composer's
    /// preview, and the `body` a template send carries.
    ///
    /// ⛔ NOT WHAT THE THREAD STORES. The server fills the template itself and stores its
    /// own text, so six clients cannot each store a different one; the route only requires
    /// a non-empty `body` on every send. ⚠️ Named placeholders are left as they are, and a
    /// body that fills to nothing falls back to ``name`` so the send is never refused for
    /// an empty body.
    public func filled(with variables: [String]) -> String {
        var text = body
        for (index, value) in variables.enumerated() {
            text = text.replacingOccurrences(of: "{{\(index + 1)}}", with: value)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? name : text
    }
}
