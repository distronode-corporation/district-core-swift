import DistrictModel
import Foundation

/// App parity: the Inbox reads with the opt-in flags, thread assignment, the push
/// registration's capabilities, and the WhatsApp composer's window, templates and
/// template send.
///
/// ⛔ EVERY READ HERE IS AN OVERLOAD, NOT A NEW DEFAULT ON THE OLD SIGNATURE. The
/// descriptors without ``InboxReadOptions`` keep answering the bytes they always sent,
/// so nothing that already builds one changes; the options are chosen once by the
/// repository that holds them.
public extension DistrictEndpoints {
    // MARK: - The Inbox reads, with the opt-in flags

    /// ``conversations(workspaceId:)`` with this build's opt-ins: `metaChannels=1` adds the
    /// Messenger and Instagram threads and every row's `replyOptions`; `assignments=1` adds
    /// `assigneeEmail` and `assignedToMe`. With ``InboxReadOptions/legacy`` the URL is
    /// byte for byte the old one.
    static func conversations(workspaceId: String, options: InboxReadOptions) -> ApiRequestDescriptor {
        ApiRequestDescriptor(
            .conversations,
            .get,
            DistrictPaths.conversations,
            query: [
                ApiQueryItem("workspaceId", workspaceId),
                ApiQueryItem("metaChannels", InboxReadOptions.flag(options.metaChannels)),
                ApiQueryItem("assignments", InboxReadOptions.flag(options.assignments)),
            ]
        )
    }

    /// ``timeline(workspaceId:contactId:address:before:beforeId:)`` with `metaChannels=1`
    /// when asked: the thread then carries its `messenger` and `instagram` rows.
    static func timeline(
        workspaceId: String,
        contactId: String?,
        address: String?,
        before: String? = nil,
        beforeId: String? = nil,
        metaChannels: Bool
    ) -> ApiRequestDescriptor {
        ApiRequestDescriptor(
            .timeline,
            .get,
            DistrictPaths.timeline,
            query: [
                ApiQueryItem("workspaceId", workspaceId),
                ApiQueryItem("contactId", contactId),
                ApiQueryItem("phoneNumber", address),
                ApiQueryItem("before", before),
                ApiQueryItem("beforeId", beforeId),
                ApiQueryItem("metaChannels", InboxReadOptions.flag(metaChannels)),
            ]
        )
    }

    /// ``unreadCount(workspaceId:)`` with `metaChannels=1` when asked, so the badge counts
    /// the Meta threads the list shows. Same response shape.
    static func unreadCount(workspaceId: String, metaChannels: Bool) -> ApiRequestDescriptor {
        ApiRequestDescriptor(
            .unreadCount,
            .get,
            DistrictPaths.messagesUnreadCount,
            query: [
                ApiQueryItem("workspaceId", workspaceId),
                ApiQueryItem("metaChannels", InboxReadOptions.flag(metaChannels)),
            ]
        )
    }

    /// ``messageThread(workspaceId:id:)`` with `metaChannels=1` when asked.
    ///
    /// ⛔ WITHOUT THE FLAG A MESSENGER OR INSTAGRAM MESSAGE IS A 404, the answer an
    /// installed build gets for a thread it cannot show. With it, `thread.channel` may be
    /// `messenger` or `instagram` and the counterpart an `fb:` or `ig:` address.
    static func messageThread(workspaceId: String, id: String, metaChannels: Bool) -> ApiRequestDescriptor {
        ApiRequestDescriptor(
            .messageThread,
            .get,
            DistrictPaths.messageThreadTarget(id),
            query: [
                ApiQueryItem("workspaceId", workspaceId),
                ApiQueryItem("metaChannels", InboxReadOptions.flag(metaChannels)),
            ]
        )
    }

    // MARK: - Thread assignment

    /// Hand one Inbox thread to a member, or take it back with `assigneeEmail: nil`.
    ///
    /// ⛔ THE UNASSIGN SENDS AN EXPLICIT `null`, NOT AN ABSENT KEY. The route reads
    /// `assigneeEmail === null` as "unassign" and an absent key as a malformed email,
    /// which is a 400 `validation_failed`. This is the one body in the client that keeps
    /// a null (see ``JSONValue/object(_:)``).
    ///
    /// ⚠️ ROLES ARE `["agency","client"]`; the assignee must be a member and must not be a
    /// Viewer (400 `assignee_is_viewer`). Not idempotent in what it notifies: the assignee
    /// gets a push for the thread's newest message unless they assigned it to themselves.
    static func assignConversation(
        workspaceId: String,
        threadKey: String,
        assigneeEmail: String?
    ) -> ApiRequestDescriptor {
        ApiRequestDescriptor(
            .assignConversation,
            .post,
            DistrictPaths.conversationsAssign,
            body: .json(.object([
                ("workspaceId", .string(workspaceId)),
                ("threadKey", .string(threadKey)),
                ("assigneeEmail", assigneeEmail.map { JSONValue.string($0) } ?? .null),
            ]))
        )
    }

    // MARK: - Push registration with capabilities

    /// ``registerPushToken(token:kind:platform:)`` declaring what this installation can
    /// open, as `capabilities`.
    ///
    /// ⚠️ AN EMPTY SET SENDS NO KEY, so the bytes equal the old descriptor's. The server
    /// reads absent and empty alike (none), and REPLACES the stored list on every
    /// register, so a build that stops declaring a capability stops being pushed for it.
    /// Sorted, so the body is deterministic.
    static func registerPushToken(
        token: String,
        kind: PushTokenKind = .alert,
        platform: ClientPlatform = .ios,
        capabilities: Set<DeviceCapability>
    ) -> ApiRequestDescriptor {
        let declared = capabilities.sorted().map { JSONValue.string($0.rawValue) }
        return ApiRequestDescriptor(
            .registerPushToken,
            .post,
            DistrictPaths.devicesRegister,
            body: .json(.object([
                ("token", .string(token)),
                ("platform", .string(platform.wire)),
                ("kind", .optional(kind.wire)),
                ("capabilities", declared.isEmpty ? nil : .array(declared)),
            ]))
        )
    }

    // MARK: - WhatsApp

    /// Whether free-form WhatsApp text may go to `to` now, and from which sender.
    ///
    /// ⚠️ `to` MUST BE A PHONE NUMBER (400 `invalid_request` otherwise). Without `senderId`
    /// the server answers for the sender the customer last wrote to; 404
    /// `whatsapp_unsupported` is a workspace with no active WhatsApp sender. Viewer and up.
    static func whatsAppWindow(workspaceId: String, to: String, senderId: String? = nil) -> ApiRequestDescriptor {
        ApiRequestDescriptor(
            .whatsAppWindow,
            .get,
            DistrictPaths.whatsAppWindow,
            query: [
                ApiQueryItem("workspaceId", workspaceId),
                ApiQueryItem("to", to),
                ApiQueryItem("senderId", senderId),
            ]
        )
    }

    /// The templates one WhatsApp sender may send, approved and pending.
    ///
    /// ⚠️ `senderId` IS REQUIRED (400 without it): take it from the window read's answer,
    /// so the picker lists the templates of the number the send goes out on. Viewer and up.
    static func whatsAppTemplates(workspaceId: String, senderId: String) -> ApiRequestDescriptor {
        ApiRequestDescriptor(
            .whatsAppTemplates,
            .get,
            DistrictPaths.whatsAppTemplates,
            query: [
                ApiQueryItem("workspaceId", workspaceId),
                ApiQueryItem("senderId", senderId),
            ]
        )
    }

    /// A free-form WhatsApp reply from a chosen sender: ``sendMessage(workspaceId:to:body:channel:subject:mediaUrls:)``
    /// on the `whatsapp` channel with `whatsappSenderId`.
    ///
    /// ⛔ METERED AND NEVER RETRIED, like every send. ⚠️ Text only: the route refuses
    /// attachments on WhatsApp, so none are sent. Without `senderId` the server sends from
    /// the number the customer last wrote to, which is the window read's `senderId` too.
    static func sendWhatsApp(
        workspaceId: String,
        to: String,
        body: String,
        senderId: String?
    ) -> ApiRequestDescriptor {
        ApiRequestDescriptor(
            .sendMessage,
            .post,
            DistrictPaths.messagesSend,
            body: .json(.object([
                ("workspaceId", .string(workspaceId)),
                ("to", .string(to)),
                ("body", .string(body)),
                ("channel", .string("whatsapp")),
                ("whatsappSenderId", .optional(senderId)),
            ]))
        )
    }

    /// An approved WhatsApp template, the only send a closed window allows.
    ///
    /// ⛔ THE SAME ROUTE AND ``EndpointID/sendMessage``: a template is a body on
    /// `messages/send`, not a route. ⛔ METERED AND NEVER RETRIED.
    ///
    /// ⚠️ `body` IS ``WhatsAppTemplate/filled(with:)``, NOT WHAT IS STORED. The route's first
    /// check wants a non-empty body on every send; the thread stores the server's own fill
    /// of the template, which is what the customer received.
    ///
    /// - Parameter variables: the values for `{{1}}` to `{{n}}`, in order. A count that
    ///   does not match the template is 400 `whatsapp_template_invalid`.
    static func sendWhatsAppTemplate(
        workspaceId: String,
        to: String,
        senderId: String?,
        template: WhatsAppTemplate,
        variables: [String]
    ) -> ApiRequestDescriptor {
        ApiRequestDescriptor(
            .sendMessage,
            .post,
            DistrictPaths.messagesSend,
            body: .json(.object([
                ("workspaceId", .string(workspaceId)),
                ("to", .string(to)),
                ("body", .string(template.filled(with: variables))),
                ("channel", .string("whatsapp")),
                ("whatsappSenderId", .optional(senderId)),
                ("templateId", .string(template.id)),
                ("templateVariables", .array(variables.map { JSONValue.string($0) })),
            ]))
        )
    }

    // MARK: - Messenger and Instagram

    /// Whether a Messenger or Instagram reply may go to `to` now: open, the 7-day human agent
    /// window, or closed.
    ///
    /// ⚠️ A GET ON THE SEND'S OWN PATH, `messages/send`. ⚠️ `to` IS THE REPLY OPTION'S ADDRESS
    /// VERBATIM, `fb:<psid>` for `messenger` and `ig:<igsid>` for `instagram`: a prefix that
    /// does not match `channel`, or a non-digit id, is 400 `invalid_request`. Viewer and up.
    static func metaWindow(workspaceId: String, channel: String, to: String) -> ApiRequestDescriptor {
        ApiRequestDescriptor(
            .metaWindow,
            .get,
            DistrictPaths.messagesSend,
            query: [
                ApiQueryItem("workspaceId", workspaceId),
                ApiQueryItem("channel", channel),
                ApiQueryItem("to", to),
            ]
        )
    }
}
