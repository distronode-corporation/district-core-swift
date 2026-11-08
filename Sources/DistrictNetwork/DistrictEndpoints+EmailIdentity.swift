import Foundation

/// The workspace's email identity: the sender name and the Reply-to address its email goes
/// out under.
///
/// ⚠️ A WORKSPACE SETTING, READ BY EVERY ROLE AND WRITTEN BY `agency` AND `client` ONLY. A
/// viewer's PATCH is a 403.
public extension DistrictEndpoints {
    /// Read the sender name, the Reply-to and the caller's own address.
    ///
    /// ⛔ THE WORKSPACE IS ALWAYS SENT. The route answers a missing `workspaceId` with a 400
    /// before the role check, because the role check would otherwise resolve the caller's
    /// default workspace, which need not be the one the form is about.
    static func emailIdentity(workspaceId: String) -> ApiRequestDescriptor {
        ApiRequestDescriptor(
            .emailIdentity,
            .get,
            DistrictPaths.workspaceEmailIdentity,
            query: [ApiQueryItem("workspaceId", workspaceId)]
        )
    }

    /// Change the sender name, the Reply-to, or both.
    ///
    /// ⛔ AT LEAST ONE IS REQUIRED: a body with neither is a 400, and a nil field is dropped
    /// from the body through ``JSONValue/object(_:)``. `""` is sent as itself and CLEARS the
    /// value, so nil ("leave it alone") and `""` must not be merged by a caller.
    ///
    /// ⚠️ A Reply-to that is not exactly one email address is a 400 (`invalid_request`).
    static func saveEmailIdentity(
        workspaceId: String,
        senderName: String?,
        replyTo: String?
    ) -> ApiRequestDescriptor {
        ApiRequestDescriptor(
            .saveEmailIdentity,
            .patch,
            DistrictPaths.workspaceEmailIdentity,
            body: .json(.object([
                ("workspaceId", .string(workspaceId)),
                ("senderName", .optional(senderName)),
                ("replyTo", .optional(replyTo)),
            ]))
        )
    }
}
