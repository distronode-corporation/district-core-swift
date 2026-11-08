import DistrictModel
import Foundation

// The AI campaign launcher's fixture, in a file of its own because `ImplementedFixtures.swift`
// is at its 500-line ceiling.

extension ImplementedFixtures {
    /// ⚠️ THE FIXTURE'S DNC ROW IS KNOWN TO BE WRONG AND IS GATED AS IT IS. It says
    /// `do_not_call`, where the route sends `auto_dial_contact_opted_out`; the code is a plain
    /// `String?`, so the corrected fixture the service regenerates decodes unchanged.
    /// `CampaignContractTests` decodes the real code from an inline body.
    static var campaigns: [ImplementedFixture] {
        [
            gate("district-calls-outbound.json", AICampaignLaunchResponse.self),
        ]
    }
}
