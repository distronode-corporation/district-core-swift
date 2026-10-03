import Foundation

public extension TypedEndpoints {
    /// The desktop's live updates.
    ///
    /// ⚠️ ITS OWN FILE FOR THE REASON ``TypedEndpoints/softphone`` HAS ONE: the main
    /// classification file is a lint ceiling rather than a taxonomy. ⛔ Unioned into
    /// ``TypedEndpoints/all``, or `EndpointSurfaceTests`' partition assertion fails.
    ///
    /// ⛔ TYPED FROM ITS FIRST COMMIT, so it never visited ``UntypedEndpoints``:
    /// ``ApiClient/telemetryToken(workspaceId:)`` decodes ``TelemetryTokenResponse``,
    /// which `DesktopContractFixtureTests` gates against
    /// `contracts/desktop/district-telemetry-token.json`. ⛔ That is the DESKTOP set,
    /// so `ContractManifest.expectedFixtureCount` (the mobile set) does not move.
    static let live: Set<EndpointID> = [.telemetryToken]
}
