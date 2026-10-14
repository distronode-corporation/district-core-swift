import DistrictModel
import Foundation

// The carrier-account, number provisioning, contact blocking and account settings fixtures,
// in a file of their own because `ImplementedFixtures.swift` is at its 500-line ceiling.

extension ImplementedFixtures {
    /// ⛔ TWENTY-ONE FIXTURES, AND EVERY TYPE THEY GATE WAS ALREADY DECODED BY A REPOSITORY.
    /// The server recorded these bodies in one batch (monorepo 49019be80); until then the
    /// shapes were pinned only by the route source and each repository's tests. Gating them
    /// here is what makes a field the server adds fail in this package rather than on a phone.
    ///
    /// ⚠️ SIX OF THEM CARRY EXPLICIT NULLS, each path named with its column in
    /// `AllowedExplicitNulls+CarrierAndAccount.swift`.
    static var carrierAndAccount: [ImplementedFixture] {
        numbersAndCarrier + blockingAndSettings
    }

    private static var numbersAndCarrier: [ImplementedFixture] {
        [
            // `configureNumber` lands on the shared envelope; `releaseNumber` has its own type
            // for the `warnings` a release that worked can still carry.
            gate("district-number-configure.json", SuccessResponse.self),
            gate("district-number-release.json", NumberReleaseResponse.self),
            gate("district-number-release-warnings.json", NumberReleaseResponse.self),
            // A valid number and one the carrier could not resolve: the second nulls the three
            // fields a lookup fills in.
            gate("district-number-lookup.json", NumberLookupResponse.self),
            gate("district-number-lookup-invalid.json", NumberLookupResponse.self),
            // A managed, a connected and a failing carrier; and a workspace with no carrier,
            // which answers `provider: null` and no `providers` map at all.
            gate("district-provider-status.json", ProviderStatusResponse.self),
            gate("district-provider-status-none.json", ProviderStatusResponse.self),
            gate("district-sip-trunks.json", SipTrunksResponse.self),
            gate("district-sip-trunk-create.json", SipTrunkCreatedResponse.self),
            // ⚠️ The disable answer OMITS `verifyServiceSid` rather than nulling it.
            gate("district-verify.json", VerifyServiceResponse.self),
            gate("district-verify-enable.json", VerifyServiceResponse.self),
            gate("district-verify-disable.json", VerifyServiceResponse.self),
            gate("district-a2p-registration.json", A2PRegistrationResponse.self),
            gate("district-tfv-submission.json", TollFreeVerificationResponse.self),
        ]
    }

    private static var blockingAndSettings: [ImplementedFixture] {
        [
            gate("district-contact-block.json", ContactBlockResponse.self),
            gate("district-contact-unblock.json", ContactBlockResponse.self),
            gate("district-contacts-blocked.json", BlockedContactsResponse.self),
            gate("district-settings.json", AccountSettingsResponse.self),
            gate("district-settings-unset.json", AccountSettingsResponse.self),
            gate("district-settings-save.json", AccountSettingsSaveResponse.self),
            // ⚠️ THE SAME TYPE AS `district-persona-options.json`, IN FRENCH. Labels localize;
            // every wire value (`id`, `value`, the voice ids) is the English body's.
            gate("district-persona-options-fr.json", PersonaOptionsResponse.self),
        ]
    }
}
