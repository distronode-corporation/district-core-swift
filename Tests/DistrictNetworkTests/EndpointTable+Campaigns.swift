@testable import DistrictNetwork
import Foundation

extension EndpointTable {
    /// The AI campaign launcher and the campaign settings. ⛔ The launcher sends the web's five
    /// keys and never a `from`: the route picks the number the calls come from. A nil account
    /// is dropped, as the web drops `undefined`, and a nil setting is dropped and left alone.
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
            EndpointExpectation(
                .saveCampaignSettings,
                DistrictEndpoints.saveCampaignSettings(workspaceId: "ws_1", sdrBatchSize: 25, sdrCampaignGoal: nil),
                .patch,
                "\(host)/api/district/workspace/campaign-settings",
                .json(#"{"sdrBatchSize":25,"workspaceId":"ws_1"}"#)
            ),
        ]
    }
}
