import Foundation

public extension TypedEndpoints {
    /// The setup wizard: its state, its writes, and the reads its steps make.
    ///
    /// ⛔ TYPED, WITH THEIR CONTRACT FIXTURES. `district-setup.json` and the eight
    /// `district-setup-*`, `district-forwarding-check*` and `district-connections*` files come
    /// from the shared corpus and are gated in `ImplementedFixtures+Setup.swift`;
    /// ``DistrictSetupResponse`` is decoded by `OverviewRepository.needsWebSetup(workspaceId:)`
    /// and `SetupWizardRepository`, the rest by `SetupWizardRepository`.
    ///
    /// ⚠️ ITS OWN FILE because `EndpointClassification.swift` sits near SwiftLint's
    /// 500-line ceiling, the same reason ``TypedEndpoints/callHandling`` has one.
    static let setup: Set<EndpointID> = [
        .districtSetup,
        .districtSetupPatch,
        .setupLookup,
        .setupTestCall,
        .forwardingCheck,
        .forwardingCheckStart,
        .workspaceConnections,
    ]
}
