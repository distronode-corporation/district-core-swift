import DistrictModel
import DistrictNetwork
import Foundation

/// The workspace's email identity, the sender name and Reply-to its email goes out under.
///
/// ⚠️ ON ``WorkspaceRepository`` BECAUSE IT IS A WORKSPACE SETTING, BUT NOT UNDER THAT FILE'S
/// LOAD-BEFORE-SAVE RULE. The config writes there replace a stored array, so a save not built
/// on a read can delete something; this PATCH writes two scalars, either alone, and echoes
/// them, so a failed read is a blank form rather than a deletion and no re-read follows a save.
public extension WorkspaceRepository {
    /// Read the sender name, the Reply-to and the caller's own address. Every role may read.
    ///
    /// ⚠️ `""` IS "NOT SET" for both values, never null. See ``EmailIdentityResponse``.
    func emailIdentity(workspaceId: String) async -> Result<EmailIdentityResponse, ApiError> {
        let outcome = await client.send(
            DistrictEndpoints.emailIdentity(workspaceId: workspaceId),
            as: EmailIdentityResponse.self
        )
        return outcome.flatMap { ResponseEnvelope.affirm("EmailIdentityResponse", $0.success, $0) }
    }

    /// Change the sender name, the Reply-to, or both. `agency` and `client` only.
    ///
    /// ⛔ nil LEAVES A VALUE ALONE AND `""` CLEARS IT, and both nil is refused here rather than
    /// spent on a round trip the route answers 400. A value over the route's length bound is
    /// refused here too, counted as the route counts it (UTF-16, before trimming).
    ///
    /// ⚠️ THE RESPONSE IS THE NEW BASELINE: the values as stored, trimmed, and the Reply-to
    /// normalised. A Reply-to that is not one address keeps the route's 400 and its
    /// `invalid_request` code.
    func saveEmailIdentity(
        workspaceId: String,
        senderName: String?,
        replyTo: String?
    ) async -> Result<EmailIdentitySaveResponse, ApiError> {
        guard senderName != nil || replyTo != nil else {
            return .failure(.decoding("saveEmailIdentity was given neither field, which the route answers 400"))
        }
        if let senderName, senderName.utf16.count > EmailIdentity.maximumSenderNameLength {
            return .failure(.decoding("saveEmailIdentity was given a sender name over 100 characters"))
        }
        if let replyTo, replyTo.utf16.count > EmailIdentity.maximumReplyToLength {
            return .failure(.decoding("saveEmailIdentity was given a Reply-to over 320 characters"))
        }
        let outcome = await client.send(
            DistrictEndpoints.saveEmailIdentity(workspaceId: workspaceId, senderName: senderName, replyTo: replyTo),
            as: EmailIdentitySaveResponse.self
        )
        return outcome.flatMap { ResponseEnvelope.affirm("EmailIdentitySaveResponse", $0.success, $0) }
    }
}
