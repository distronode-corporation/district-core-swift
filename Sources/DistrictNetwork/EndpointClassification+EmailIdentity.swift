import Foundation

public extension TypedEndpoints {
    /// The workspace's email sender name and Reply-to.
    ///
    /// ⚠️ TWO ENTRIES FOR ONE PATH, a read and a write, so `EndpointTableTests` can assert a
    /// method per entry. Both bodies are pinned by fixtures (`district-email-identity.json`
    /// and `-patch.json`), decoded by `WorkspaceRepository.emailIdentity(workspaceId:)` and
    /// `saveEmailIdentity(workspaceId:senderName:replyTo:)`.
    ///
    /// ⚠️ ITS OWN FILE because `EndpointClassification.swift` sits under SwiftLint's 500-line
    /// limit; see ``TypedEndpoints/callHandling`` for the precedent.
    static let emailIdentity: Set<EndpointID> = [
        .emailIdentity,
        .saveEmailIdentity,
    ]
}
