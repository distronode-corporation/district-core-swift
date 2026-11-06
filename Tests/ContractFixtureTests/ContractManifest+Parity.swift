import Foundation

// App parity's half of the manifest, in a file of its own for the same `file_length`
// reason as `ContractManifest+Setup.swift`.

extension ContractManifest {
    /// Six of the thirteen app parity fixtures gated in `ImplementedFixtures+Parity.swift`
    /// carry a null.
    ///
    /// ⚠️ TWENTY-SEVEN paths, each named with its column in `AllowedExplicitNulls+Parity.swift`.
    static let parityFixturesWithAllowedNulls: Set<String> = [
        "district-conversation-unassign.json",
        "district-conversations-assignee.json",
        "district-conversations-reply-options.json",
        "district-meta-window-closed.json",
        "district-whatsapp-templates.json",
        "district-whatsapp-window-closed.json",
    ]
}
