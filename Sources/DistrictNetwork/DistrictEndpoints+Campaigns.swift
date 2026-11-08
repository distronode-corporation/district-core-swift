import Foundation

/// The AI campaign launcher: the workspace's voice agent phones a list of contacts with
/// one goal.
public extension DistrictEndpoints {
    /// The most contacts one launch may name: the route's `MAX_CONTACTS_PER_REQUEST`.
    ///
    /// ⚠️ THE ROUTE ALSO ALLOWS 5 LAUNCHES A MINUTE PER WORKSPACE, and that limit is not
    /// mirrored here: only the server can count launches across devices, and it answers
    /// 429 `rate_limited`.
    static let aiCampaignMaxContacts = 100

    /// One campaign launch, the web's body exactly: `workspaceId`, `contactIds`, `prompt`,
    /// `accountId` (dropped when nil) and `channel: "voice"`.
    ///
    /// ⛔ NO `from` AND NO CALLER ID, EVER. The route resolves the number the calls come
    /// from itself; a `from` this client chose would be a caller identity the operator
    /// never picked on the web.
    ///
    /// ⛔ PLACES REAL, BILLED CALLS AND IS NEVER RETRIED: a resend dials every queued
    /// contact a second time.
    ///
    /// - Parameter prompt: the campaign's goal, sent exactly as written (the route
    ///   refuses a blank one but does not trim a valid one).
    /// - Parameter accountId: the carrier account to dial through, or nil for the
    ///   workspace's default.
    static func aiCampaignLaunch(
        workspaceId: String,
        contactIds: [String],
        prompt: String,
        accountId: String?
    ) -> ApiRequestDescriptor {
        ApiRequestDescriptor(
            .aiCampaignLaunch,
            .post,
            DistrictPaths.aiCampaignLaunch,
            body: .json(.object([
                ("workspaceId", .string(workspaceId)),
                ("contactIds", .array(contactIds.map { JSONValue.string($0) })),
                ("prompt", .string(prompt)),
                ("accountId", .optional(accountId)),
                ("channel", .string("voice")),
            ]))
        )
    }
}
