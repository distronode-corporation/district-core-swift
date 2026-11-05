@testable import DistrictNetwork
import Foundation

extension EndpointTable {
    /// Live supervision: the listen seat and the takeover. (The whisper is in `telephony()`.)
    static func supervise() -> [EndpointExpectation] {
        [
            // ⛔ THE CALL ID UNDER THE KEY `roomName`, the route's historical naming, on the
            // same path as a meeting room's token. `identity` is required and ignored.
            EndpointExpectation(
                .monitorCall,
                DistrictEndpoints.monitorCall(callId: SupervisedCallID("3f2a9c1e-call")!),
                .post,
                "\(host)/api/district/calls/token",
                .json(#"{"identity":"ios","roomName":"3f2a9c1e-call"}"#)
            ),
            // ⛔ THE CALL IN THE PATH, THE WORKSPACE IN THE BODY, exactly like `answer`,
            // one segment away and a different credential.
            EndpointExpectation(
                .takeOverCall,
                DistrictEndpoints.takeOverCall(callId: "call_1", workspaceId: "ws_1"),
                .post,
                "\(host)/api/district/calls/call_1/takeover",
                .json(#"{"workspaceId":"ws_1"}"#)
            ),
        ]
    }
}
