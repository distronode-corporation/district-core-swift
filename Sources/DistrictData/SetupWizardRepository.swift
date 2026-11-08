import DistrictModel
import DistrictNetwork
import Foundation

/// The setup wizard, for the workspace's owner: its state, the step saves, the website lookup,
/// the test call and the forwarding check.
///
/// ⛔ OWNER ONLY. A member or an admin gets 403 on every `setup/*` route and a workspace from
/// before the wizard gets 409 `setup_not_available`; both keep the service's code. Buying a
/// number, choosing a plan and connecting a calendar provider are not here: they charge a card
/// or need a browser, and stay on the web.
public struct SetupWizardRepository: Sendable {
    private let client: ApiClient

    public init(client: ApiClient) {
        self.client = client
    }

    public func load(workspaceId: String) async -> Result<DistrictSetupResponse, ApiError> {
        await client.send(DistrictEndpoints.districtSetup(workspaceId: workspaceId), as: DistrictSetupResponse.self)
    }

    /// Saves step states and business-facts sections, and answers the state after the write.
    public func save(
        workspaceId: String,
        steps: [SetupStep: SetupStepState] = [:],
        businessFacts: WireJSON? = nil
    ) async -> Result<DistrictSetupResponse, ApiError> {
        await client.send(
            DistrictEndpoints.districtSetupPatch(workspaceId: workspaceId, steps: steps, businessFacts: businessFacts),
            as: DistrictSetupResponse.self
        )
    }

    /// A draft of the business's facts from its website. A page the service cannot read is
    /// 422 `website_unreadable`.
    public func lookUp(
        workspaceId: String,
        websiteUrl: String,
        locale: String
    ) async -> Result<SetupLookupResponse, ApiError> {
        await client.send(
            DistrictEndpoints.setupLookup(workspaceId: workspaceId, websiteUrl: websiteUrl, locale: locale),
            as: SetupLookupResponse.self
        )
    }

    /// Has the receptionist call the owner's phone. Answers the call's id.
    public func placeTestCall(workspaceId: String, phone: String) async -> Result<String, ApiError> {
        let outcome = await client.send(
            DistrictEndpoints.setupTestCall(workspaceId: workspaceId, phone: phone),
            as: SetupTestCallResponse.self
        )
        return outcome.flatMap { ResponseEnvelope.affirm("SetupTestCallResponse", $0.success, $0.callId) }
    }

    public func forwardingCheck(workspaceId: String) async -> Result<ForwardingCheckResponse, ApiError> {
        await client.send(DistrictEndpoints.forwardingCheck(workspaceId: workspaceId), as: ForwardingCheckResponse.self)
    }

    /// Starts a check of the business line's forwarding. Poll ``forwardingCheck(workspaceId:)``
    /// while the answer ``ForwardingCheck/isPending``.
    public func startForwardingCheck(
        workspaceId: String,
        businessLine: String,
        mode: ForwardingCheckMode
    ) async -> Result<ForwardingCheckResponse, ApiError> {
        await client.send(
            DistrictEndpoints.forwardingCheckStart(workspaceId: workspaceId, businessLine: businessLine, mode: mode),
            as: ForwardingCheckResponse.self
        )
    }

    public func connections(workspaceId: String) async -> Result<ConnectionsResponse, ApiError> {
        await client.send(
            DistrictEndpoints.workspaceConnections(workspaceId: workspaceId),
            as: ConnectionsResponse.self
        )
    }
}
