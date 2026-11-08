import DistrictModel
import Foundation

// The workspace's email identity and call handling, in a file of their own because
// `ImplementedFixtures.swift` is at its 500-line ceiling.

extension ImplementedFixtures {
    /// ⚠️ CALL HANDLING WAS TYPED BEFORE IT HAD A FIXTURE, pinned then only by the route
    /// source and `CallHandlingRepositoryTests`; these gate the same DTO against the
    /// service's recorded bodies. Both verbs answer one shape, so one type gates both.
    ///
    /// ⚠️ THE EMAIL IDENTITY'S TWO BODIES DIFFER BY `memberEmail`, which only the read
    /// carries, so each has its own type.
    static var workspaceSettings: [ImplementedFixture] {
        [
            gate("district-email-identity.json", EmailIdentityResponse.self),
            gate("district-email-identity-patch.json", EmailIdentitySaveResponse.self),
            gate("district-call-handling.json", CallHandlingResponse.self),
            gate("district-call-handling-patch.json", CallHandlingResponse.self),
        ]
    }
}
