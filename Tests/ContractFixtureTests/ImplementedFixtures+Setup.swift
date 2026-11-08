import DistrictModel
import Foundation

// The setup wizard's state, writes and step reads, in a file of its own because `ImplementedFixtures.swift` is at its
// 500-line ceiling (the same reason `+Persona` and `+MessageThread` exist).

extension ImplementedFixtures {
    /// ⛔ GATED FROM ITS FIRST COMMIT, WITH THE DTO, THE DESCRIPTOR AND THE REPOSITORY
    /// METHOD THAT READS IT. ``DistrictSetupResponse``, `DistrictEndpoints.districtSetup(workspaceId:)` and
    /// `OverviewRepository.needsWebSetup(workspaceId:)` land beside this entry, so the name
    /// is never in `ContractManifest.unimplemented`.
    ///
    /// ⚠️ THE THREE OPAQUE FIELDS (`businessFacts`, `testCallConsent`, `forwardingCheck`) ARE
    /// ``WireJSON``, which round-trips whatever it is handed, so the gate still compares their
    /// contents key for key the day a fixture carries one. This one carries none of them as
    /// an object: `businessFacts` is null (allowlisted) and the other two are absent.
    static var setup: [ImplementedFixture] {
        [
            gate("district-setup.json", DistrictSetupResponse.self),
            // The PATCH answers the whole state after the write, the same body as the GET.
            gate("district-setup-patch.json", DistrictSetupResponse.self),
            gate("district-setup-lookup.json", SetupLookupResponse.self),
            gate("district-setup-lookup-unreadable.json", SetupLookupRefusal.self),
            gate("district-setup-test-call.json", SetupTestCallResponse.self),
            gate("district-forwarding-check.json", ForwardingCheckResponse.self),
            gate("district-forwarding-check-start.json", ForwardingCheckResponse.self),
            gate("district-connections.json", ConnectionsResponse.self),
            // A viewer's answer: the rows without the calendar resolution.
            gate("district-connections-viewer.json", ConnectionsResponse.self),
        ]
    }
}
