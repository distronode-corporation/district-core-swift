import DistrictModel
import Foundation

/// The credential for a workspace's live telemetry socket.
///
/// ⛔ A DESKTOP SURFACE. A Mac has no PushKit ring, so calls and messages reach it
/// as they happen over `/ws/telemetry`, one socket per workspace, and this route is
/// how that socket is authenticated. The phone apps never call it.
public extension DistrictEndpoints {
    /// Mint a fifteen-minute credential for `workspaceId`'s socket.
    ///
    /// ⛔ THE WORKSPACE TRAVELS IN THE BODY, NOT THE QUERY. The route reads
    /// `body.workspaceId` and answers 400 `invalid_request` without it, which reads
    /// like a broken client rather than a misplaced parameter.
    ///
    /// ⚠️ MEMBERSHIP IS PROVEN HERE (403 `workspace_access_denied` for a workspace
    /// the account cannot read) and again by the broadcaster on connect and every
    /// sixty seconds after. ⚠️ Rate limited at 30/min PER ACCOUNT; a socket renews
    /// about every fourteen minutes, so only a runaway loop reaches it.
    static func telemetryToken(workspaceId: String) -> ApiRequestDescriptor {
        ApiRequestDescriptor(
            .telemetryToken,
            .post,
            DistrictPaths.telemetryToken,
            body: .json(.object([("workspaceId", .string(workspaceId))]))
        )
    }
}

public extension ApiClient {
    /// `POST /api/district/telemetry/token`, decoded and envelope-checked.
    ///
    /// ⛔ ON THE CLIENT RATHER THAN IN A `DistrictData` REPOSITORY, because its one
    /// caller is `DistrictLive`'s connection, which reaches the API through
    /// `TelemetryTokenMinter` and has no other use for the data layer.
    ///
    /// ⚠️ A 200 THAT DOES NOT AFFIRM `success: true` IS ``ApiError/decoding(_:)``,
    /// the same reading `ResponseEnvelope.affirm` gives every other route: a socket
    /// opened on a credential the server declined to affirm is a socket that
    /// connects and is then closed with 4401.
    ///
    /// ⛔ NOT RETRIED HERE, like everything on ``ApiClient``. The connection decides
    /// which failures are worth another attempt and how long to wait.
    func telemetryToken(workspaceId: String) async -> Result<TelemetryTokenResponse, ApiError> {
        let outcome = await send(
            DistrictEndpoints.telemetryToken(workspaceId: workspaceId),
            as: TelemetryTokenResponse.self
        )
        return outcome.flatMap { response in
            guard response.success else {
                return .failure(.decoding("TelemetryTokenResponse did not affirm success=true"))
            }
            return .success(response)
        }
    }
}
