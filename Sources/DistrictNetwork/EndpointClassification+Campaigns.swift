import Foundation

public extension TypedEndpoints {
    /// The AI campaign launcher, decoded as ``AICampaignLaunchResponse`` by
    /// `CampaignsRepository.launchAICampaign(workspaceId:contactIds:prompt:accountId:)` and
    /// pinned by `district-calls-outbound.json`.
    ///
    /// ⛔ NOT IN ``softphone``: the voice agent places these calls, never the operator.
    static let campaigns: Set<EndpointID> = [
        .aiCampaignLaunch,
    ]
}
