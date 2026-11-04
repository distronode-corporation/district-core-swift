@testable import DistrictNetwork
import Foundation

extension EndpointTable {
    /// App parity's three new routes: the thread assignment write and the WhatsApp
    /// composer's two reads. Read off the routes on the service (`conversations/assign`,
    /// `workspace/whatsapp/window`, `workspace/whatsapp/templates`).
    ///
    /// ⚠️ THE REST OF APP PARITY IS NOT A ROW: the opt-in flags, the capabilities and the
    /// template send are new BODIES or QUERIES on existing ids, pinned in
    /// `ParityEndpointTests`.
    static func parity() -> [EndpointExpectation] {
        [
            // ⛔ THE ONE BODY IN THE CLIENT WITH AN EXPLICIT NULL is the unassign; this row is
            // the assign, and `ParityEndpointTests` pins the null.
            EndpointExpectation(
                .assignConversation,
                DistrictEndpoints.assignConversation(
                    workspaceId: "ws_1",
                    threadKey: "contact:c_1",
                    assigneeEmail: "a@b.test"
                ),
                .post,
                "\(host)/api/district/conversations/assign",
                .json(#"{"assigneeEmail":"a@b.test","threadKey":"contact:c_1","workspaceId":"ws_1"}"#)
            ),
            // ⚠️ UNDER `workspace/whatsapp`, and the `+` is percent-encoded: a literal one
            // decodes to a space server-side and the number no longer parses.
            EndpointExpectation(
                .whatsAppWindow,
                DistrictEndpoints.whatsAppWindow(workspaceId: "ws_1", to: "+14165550177"),
                .get,
                "\(host)/api/district/workspace/whatsapp/window?workspaceId=ws_1&to=%2B14165550177"
            ),
            EndpointExpectation(
                .whatsAppTemplates,
                DistrictEndpoints.whatsAppTemplates(workspaceId: "ws_1", senderId: "wa_1"),
                .get,
                "\(host)/api/district/workspace/whatsapp/templates?workspaceId=ws_1&senderId=wa_1"
            ),
        ]
    }
}
