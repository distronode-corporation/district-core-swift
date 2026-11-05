import Foundation

// App parity's half of the manifest, in a file of its own for the same `file_length`
// reason as `ContractManifest+Setup.swift`.

extension ContractManifest {
    /// Five of the ten app parity fixtures gated in `ImplementedFixtures+Parity.swift` carry
    /// a null.
    ///
    /// ⚠️ TWENTY-SIX paths, each named with its column in `AllowedExplicitNulls+Parity.swift`.
    static let parityFixturesWithAllowedNulls: Set<String> = [
        "district-conversation-unassign.json",
        "district-conversations-assignee.json",
        "district-conversations-reply-options.json",
        "district-whatsapp-templates.json",
        "district-whatsapp-window-closed.json",
    ]
}
