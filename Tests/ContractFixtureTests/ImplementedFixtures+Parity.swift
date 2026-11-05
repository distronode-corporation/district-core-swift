import DistrictModel
import Foundation

// App parity's ten fixtures (monorepo !105 and !106), in a file of their own because
// `ImplementedFixtures.swift` is at its 500-line ceiling.

extension ImplementedFixtures {
    /// ⛔ EACH LEAVES `ContractManifest.unimplemented` WITH ITS DTO, ITS DESCRIPTOR AND THE
    /// REPOSITORY METHOD THAT DECODES IT, in one commit.
    ///
    /// ⚠️ THREE OF THEM ARE EXISTING TYPES ON A NEW BRANCH OF THEIR ROUTE: the two
    /// `conversations` reads with `metaChannels=1` and `assignments=1`, the timeline with
    /// its Meta rows, and the template send's echo (`provider: "meta"`). The Viewer refusal
    /// is the plain `{success, error, code}` envelope.
    static var parity: [ImplementedFixture] {
        [
            gate("district-conversations-reply-options.json", ConversationsResponse.self),
            gate("district-conversations-assignee.json", ConversationsResponse.self),
            gate("district-timeline-meta.json", TimelineResponse.self),
            gate("district-conversation-assign.json", ConversationAssignResponse.self),
            gate("district-conversation-unassign.json", ConversationAssignResponse.self),
            gate("district-conversation-assign-viewer.json", ApiErrorEnvelope.self),
            gate("district-whatsapp-window.json", WhatsAppWindowResponse.self),
            gate("district-whatsapp-window-closed.json", WhatsAppWindowResponse.self),
            gate("district-whatsapp-templates.json", WhatsAppTemplatesResponse.self),
            gate("district-message-send-whatsapp-template.json", SendMessageResponse.self),
        ]
    }
}
