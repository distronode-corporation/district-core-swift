import DistrictModel
import Foundation

// `CampaignsRepository`'s two fixtures, in a file of their own because
// `ImplementedFixtures.swift` is at its 500-line ceiling.

extension ImplementedFixtures {
    /// The launcher's answer carries one row per status and one skip per recipient rule,
    /// each from the service's real dialer; the settings save answers a bare `{success}`.
    static var campaigns: [ImplementedFixture] {
        [
            gate("district-calls-outbound.json", AICampaignLaunchResponse.self),
            gate("district-campaign-settings.json", SuccessResponse.self),
        ]
    }
}
