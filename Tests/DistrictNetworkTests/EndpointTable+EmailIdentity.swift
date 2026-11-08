@testable import DistrictNetwork
import Foundation

extension EndpointTable {
    /// The workspace's email identity. ⚠️ The PATCH row pins that a nil field is dropped and
    /// `""` is sent: the route treats `""` as a clear and refuses a body with neither field.
    static func emailIdentity() -> [EndpointExpectation] {
        [
            EndpointExpectation(
                .emailIdentity,
                DistrictEndpoints.emailIdentity(workspaceId: "ws_1"),
                .get,
                "\(host)/api/district/workspace/email-identity?workspaceId=ws_1"
            ),
            EndpointExpectation(
                .saveEmailIdentity,
                DistrictEndpoints.saveEmailIdentity(workspaceId: "ws_1", senderName: nil, replyTo: ""),
                .patch,
                "\(host)/api/district/workspace/email-identity",
                .json(#"{"replyTo":"","workspaceId":"ws_1"}"#)
            ),
        ]
    }
}
