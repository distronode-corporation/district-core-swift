@testable import DistrictNetwork
import Foundation

extension EndpointTable {
    /// The desktop's live updates. Read off `app/api/district/telemetry/token/route.ts`:
    /// a POST whose `workspaceId` is read from the BODY, 400 without it.
    static func live() -> [EndpointExpectation] {
        [
            EndpointExpectation(
                .telemetryToken,
                DistrictEndpoints.telemetryToken(workspaceId: "ws_1"),
                .post,
                "\(host)/api/district/telemetry/token",
                .json(#"{"workspaceId":"ws_1"}"#)
            ),
        ]
    }
}
