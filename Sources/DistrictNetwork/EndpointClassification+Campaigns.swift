import Foundation

public extension TypedEndpoints {
    /// `CampaignsRepository`'s two routes. The AI campaign launcher is decoded as
    /// ``AICampaignLaunchResponse`` by
    /// `launchAICampaign(workspaceId:contactIds:prompt:accountId:)` and pinned by
    /// `district-calls-outbound.json`; the settings save is decoded as ``SuccessResponse``
    /// by `saveCampaignSettings(workspaceId:sdrBatchSize:sdrCampaignGoal:)` and pinned by
    /// `district-campaign-settings.json`.
    ///
    /// ⛔ THE LAUNCHER IS NOT IN ``softphone``: the voice agent places these calls, never
    /// the operator.
    static let campaigns: Set<EndpointID> = [
        .aiCampaignLaunch,
        .saveCampaignSettings,
    ]
}
