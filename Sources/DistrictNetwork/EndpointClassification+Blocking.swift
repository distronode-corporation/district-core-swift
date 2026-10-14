import Foundation

public extension TypedEndpoints {
    /// The two Guideline 1.2 moderation routes.
    ///
    /// ⛔ NEVER UNTYPED: ``ContactBlockResponse``, ``BlockedContactsResponse`` and the
    /// two ``ContactsRepository`` methods belong with the descriptors, so no screen can
    /// reach these routes and get bytes back.
    ///
    /// ⚠️ BOTH ARE FIXTURE-GATED: `district-contact-block.json`,
    /// `district-contact-unblock.json` and `district-contacts-blocked.json`, recorded by
    /// the server's own suite, in `ImplementedFixtures+CarrierAndAccount.swift`. The
    /// request bodies are pinned by `EndpointTableTests`' byte-exact rows and
    /// `ContactsBlockRepositoryTests` against ``ContactBlockBodies``.
    ///
    /// ⚠️ ITS OWN FILE RATHER THAN TWO MORE LINES IN `EndpointClassification.swift`,
    /// for the reason `EndpointClassification+Desk.swift` gives: that file is at
    /// SwiftLint's 500-line ceiling and the commentary on those lists is the point of
    /// them. ⛔ A family declared here and not unioned into ``TypedEndpoints/all``
    /// fails `EndpointSurfaceTests`' partition assertion rather than defaulting to
    /// "raw".
    static let blocking: Set<EndpointID> = [
        .setContactBlocked,
        .blockedContacts,
    ]
}
