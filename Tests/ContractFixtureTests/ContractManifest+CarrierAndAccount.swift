import Foundation

// The carrier-account, blocking and account settings half of the manifest, in a file of its
// own for the same `file_length` reason as `ContractManifest+Setup.swift`.

extension ContractManifest {
    /// Six of the twenty-one fixtures gated in `ImplementedFixtures+CarrierAndAccount.swift`
    /// carry a null.
    ///
    /// ⚠️ NINE paths, each named with its column in
    /// `AllowedExplicitNulls+CarrierAndAccount.swift`.
    static let carrierFixturesWithAllowedNulls: Set<String> = [
        "district-contact-unblock.json",
        "district-contacts-blocked.json",
        "district-number-lookup-invalid.json",
        "district-provider-status-none.json",
        "district-settings-unset.json",
        "district-sip-trunks.json",
    ]
}
