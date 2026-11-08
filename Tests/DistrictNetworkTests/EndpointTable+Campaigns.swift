@testable import DistrictNetwork
import Foundation

extension EndpointTable {
    /// The AI campaign launcher. ⛔ The web's five keys and never a `from`: the route picks
    /// the number the calls come from. A nil account is dropped, as the web drops `undefined`.
    static func campaigns() -> [EndpointExpectation] {
        [
            EndpointExpectation(
                .aiCampaignLaunch,
                DistrictEndpoints.aiCampaignLaunch(
                    workspaceId: "ws_1",
                    contactIds: ["c_1", "c_2"],
                    prompt: "Confirm Tuesday.",
                    accountId: nil
                ),
                .post,
                "\(host)/api/district/calls/outbound",
                .json(
                    #"{"channel":"voice","contactIds":["c_1","c_2"],"prompt":"Confirm Tuesday.","workspaceId":"ws_1"}"#
                )
            ),
        ]
    }
}
