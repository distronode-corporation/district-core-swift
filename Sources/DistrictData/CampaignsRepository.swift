import DistrictL10n
import DistrictModel
import DistrictNetwork
import Foundation

/// AI calling campaigns: the launcher, where the workspace's voice agent phones a list of
/// contacts with one goal, and the always-on campaign's batch size and goal.
///
/// ⛔ THE ONLY WAY TO `calls/outbound`, AND NOTHING SOFTPHONE-RELATED REACHES IT. The voice
/// agent places these calls and speaks on them, so a person who dialled through this route
/// would find the agent on their own line. ``CallsRepository`` and the softphone dial with
/// `calls/dial`; `EndpointSurfaceTests` pins that no other repository names this route.
public struct CampaignsRepository: Sendable {
    private let client: ApiClient

    public init(client: ApiClient) {
        self.client = client
    }

    /// Launches one AI campaign: the voice agent calls each contact with `prompt` as its
    /// goal.
    ///
    /// ⛔ THIS PLACES REAL, BILLED CALLS AND IS SENT ONCE. A resend dials every queued
    /// contact again, so a failure (a lost answer included) is reported, never retried.
    ///
    /// ⛔ A SUCCESS IS THE BATCH BEING PROCESSED, NOT A CALL GOING OUT: read
    /// ``AICampaignLaunchResponse/queuedCount`` before telling the operator anything was
    /// placed.
    ///
    /// ⚠️ ONLY THE ROUTE'S OWN LIMITS ARE CHECKED HERE, and they are refused before
    /// anything is sent: no contacts, more than
    /// ``DistrictEndpoints/aiCampaignMaxContacts``, or a blank prompt. Whether a contact
    /// may be called (DNC, calling hours, country, billing, dormancy) is the server's
    /// alone, answered per contact in the results or as a refusal of the whole batch with
    /// a `code`. So is the rate limit of five launches a minute (429 `rate_limited`).
    ///
    /// - Parameter prompt: the goal, sent exactly as written.
    /// - Parameter accountId: the carrier account to dial through, or nil for the
    ///   workspace's default.
    public func launchAICampaign(
        workspaceId: String,
        contactIds: [String],
        prompt: String,
        accountId: String? = nil
    ) async -> Result<AICampaignLaunchResponse, ApiError> {
        if contactIds.isEmpty {
            return .failure(.http(status: 400, message: CampaignCopy.noContacts))
        }
        if contactIds.count > DistrictEndpoints.aiCampaignMaxContacts {
            return .failure(.http(status: 400, message: CampaignCopy.tooManyContacts))
        }
        if prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .failure(.http(status: 400, message: CampaignCopy.promptBlank))
        }
        let outcome = await client.send(
            DistrictEndpoints.aiCampaignLaunch(
                workspaceId: workspaceId,
                contactIds: contactIds,
                prompt: prompt,
                accountId: accountId
            ),
            as: AICampaignLaunchResponse.self
        )
        return outcome.flatMap { ResponseEnvelope.affirm("AICampaignLaunchResponse", $0.success, $0) }
    }

    /// Saves the always-on campaign's batch size and goal. nil leaves a value as it is;
    /// `""` clears the goal.
    ///
    /// ⛔ NEVER THE ON SWITCH: pausing and resuming is
    /// `WorkflowsRepository.setCampaignEnabled(workspaceId:infiniteSdrEnabled:)`, on
    /// `campaign-status`.
    ///
    /// ⚠️ A BATCH SIZE OUTSIDE 1 TO ``DistrictEndpoints/campaignMaxBatchSize`` IS REFUSED
    /// WITHOUT A REQUEST, the route's own range. The route answers a bare `{success}`; the
    /// saved values are read back from `campaign-status`.
    public func saveCampaignSettings(
        workspaceId: String,
        sdrBatchSize: Int? = nil,
        sdrCampaignGoal: String? = nil
    ) async -> Result<Void, ApiError> {
        if let sdrBatchSize, !(1 ... DistrictEndpoints.campaignMaxBatchSize).contains(sdrBatchSize) {
            return .failure(.http(status: 400, message: CampaignCopy.batchSizeRange))
        }
        let outcome = await client.send(
            DistrictEndpoints.saveCampaignSettings(
                workspaceId: workspaceId,
                sdrBatchSize: sdrBatchSize,
                sdrCampaignGoal: sdrCampaignGoal
            ),
            as: SuccessResponse.self
        )
        return outcome
            .flatMap { ResponseEnvelope.affirm("CampaignSettingsResponse", $0.success, $0) }
            .map { _ in }
    }
}
