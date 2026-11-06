import DistrictModel
import DistrictNetwork
import Foundation

// App parity on the Inbox: thread assignment and the WhatsApp composer. In a file of its
// own because `InboxRepository.swift` sits near SwiftLint's 500-line `file_length`, the
// reason `InboxRepository+MessageThread.swift` exists.

public extension InboxRepository {
    // MARK: - Thread assignment

    /// Hand one thread to a member (`assigneeEmail`), or take it back (`nil`).
    ///
    /// ⛔ nil ON SUCCESS IS THE UNASSIGN'S ANSWER, NOT A MISSING ROW. The server answers
    /// `{success: true, assignment: null}` once nobody owns the thread.
    ///
    /// ⚠️ THE REFUSALS ARE CODED AND EACH NEEDS ITS OWN SENTENCE, which
    /// ``ApiError/localizedMessage`` gives in either language: `assignee_is_viewer`
    /// (``ApiErrorCode/assigneeIsViewer``), `assignee_not_member`, and the role guard's 403
    /// for a Viewer who tries to assign. Gate the control on
    /// ``WorkspaceRole/allowsMutation(_:)`` and offer only non-Viewer members as assignees.
    ///
    /// ⛔ NEVER RETRIED: the assignee is pushed the thread's newest message on each assign.
    ///
    /// - Parameter threadKey: ``ConversationSummary/threadKey``, verbatim.
    func assign(
        workspaceId: String,
        threadKey: String,
        assigneeEmail: String?
    ) async -> Result<ThreadAssignment?, ApiError> {
        let outcome = await client.send(
            DistrictEndpoints.assignConversation(
                workspaceId: workspaceId,
                threadKey: threadKey,
                assigneeEmail: assigneeEmail
            ),
            as: ConversationAssignResponse.self
        )
        return outcome
            .flatMap { ResponseEnvelope.affirm("ConversationAssignResponse", $0.success, $0) }
            .map(\.assignment)
    }

    // MARK: - WhatsApp

    /// Whether free-form WhatsApp text may go to `to` now, and which sender the composer
    /// sends from.
    ///
    /// ⛔ A PREVIEW, NOT THE GATE: the send still answers 409 `whatsapp_window_closed` when
    /// the window shut in between. When ``WhatsAppWindow/open`` is false, offer
    /// ``whatsAppTemplates(workspaceId:senderId:)`` instead of the text box.
    ///
    /// - Parameter to: the WhatsApp ``ReplyOption/to``, in E.164.
    /// - Parameter senderId: the operator's pick, or nil for the sender the customer last
    ///   wrote to.
    func whatsAppWindow(
        workspaceId: String,
        to: String,
        senderId: String? = nil
    ) async -> Result<WhatsAppWindowResponse, ApiError> {
        let outcome = await client.send(
            DistrictEndpoints.whatsAppWindow(workspaceId: workspaceId, to: to, senderId: senderId),
            as: WhatsAppWindowResponse.self
        )
        return outcome
            .flatMap { ResponseEnvelope.affirm("WhatsAppWindowResponse", $0.success, $0) }
    }

    /// The templates one sender may send, approved and pending. Offer only
    /// ``WhatsAppTemplate/isSendable`` ones for sending.
    ///
    /// - Parameter senderId: ``WhatsAppWindowResponse/senderId``, so the list is the
    ///   templates of the number the send goes out on.
    func whatsAppTemplates(workspaceId: String, senderId: String) async -> Result<[WhatsAppTemplate], ApiError> {
        let outcome = await client.send(
            DistrictEndpoints.whatsAppTemplates(workspaceId: workspaceId, senderId: senderId),
            as: WhatsAppTemplatesResponse.self
        )
        return outcome
            .flatMap { ResponseEnvelope.affirm("WhatsAppTemplatesResponse", $0.success, $0) }
            .map(\.templates)
    }

    /// A free-form WhatsApp reply from a chosen sender.
    ///
    /// ⛔ METERED AND NON-IDEMPOTENT, like
    /// ``send(workspaceId:target:body:subject:mediaUrls:)``, which sends WhatsApp too when
    /// the sender need not be named. Never retried.
    func sendWhatsApp(
        workspaceId: String,
        to: String,
        body: String,
        senderId: String?
    ) async -> Result<SentMessage, ApiError> {
        let outcome = await client.send(
            DistrictEndpoints.sendWhatsApp(workspaceId: workspaceId, to: to, body: body, senderId: senderId),
            as: SendMessageResponse.self
        )
        return outcome
            .flatMap { ResponseEnvelope.affirm("SendMessageResponse", $0.success, $0) }
            .map(\.message)
    }

    /// Send an approved template, the only WhatsApp send a closed window allows.
    ///
    /// ⛔ METERED AND NON-IDEMPOTENT, and never retried. ⚠️ The returned message's `body` is
    /// the SERVER's fill of the template, which is what the thread shows; the request's own
    /// `body` is ``WhatsAppTemplate/filled(with:)``, which the route requires and does not
    /// store.
    ///
    /// - Parameter variables: one value per placeholder, in order
    ///   (``WhatsAppTemplate/variableCount``). A mismatch is 400 `whatsapp_template_invalid`.
    func sendWhatsAppTemplate(
        workspaceId: String,
        to: String,
        senderId: String?,
        template: WhatsAppTemplate,
        variables: [String]
    ) async -> Result<SentMessage, ApiError> {
        let outcome = await client.send(
            DistrictEndpoints.sendWhatsAppTemplate(
                workspaceId: workspaceId,
                to: to,
                senderId: senderId,
                template: template,
                variables: variables
            ),
            as: SendMessageResponse.self
        )
        return outcome
            .flatMap { ResponseEnvelope.affirm("SendMessageResponse", $0.success, $0) }
            .map(\.message)
    }

    // MARK: - Messenger and Instagram

    /// Whether a Messenger or Instagram reply may go to `to` now, and how.
    ///
    /// ⛔ A PREVIEW, NOT THE GATE: the send still answers 409 `messenger_window_closed` when
    /// the window shut in between. ``MetaWindowState/closed`` disables Send and says why;
    /// ``MetaWindowState/humanAgent`` says the reply is a human agent's and offers no AI draft;
    /// an ``MetaWindowState/unknown(_:)`` state, like a failed read, blocks nothing.
    ///
    /// - Parameter channel: ``MessageChannel/messenger`` or ``MessageChannel/instagram``.
    /// - Parameter to: that channel's ``ReplyOption/to``, `fb:<psid>` or `ig:<igsid>`.
    func metaWindow(workspaceId: String, channel: String, to: String) async -> Result<MetaWindow, ApiError> {
        let outcome = await client.send(
            DistrictEndpoints.metaWindow(workspaceId: workspaceId, channel: channel, to: to),
            as: MetaWindowResponse.self
        )
        return outcome
            .flatMap { ResponseEnvelope.affirm("MetaWindowResponse", $0.success, $0) }
            .map(\.window)
    }
}
