import Foundation

/// `POST /api/district/conversations/assign`, one Inbox thread handed to a member, or
/// taken back.
///
/// ⛔ ``assignment`` IS NULL ON AN UNASSIGN, AND THAT IS THE SUCCESS. The request sends
/// `assigneeEmail: null` and the answer is `{success: true, assignment: null}`
/// (`district-conversation-unassign.json`), so a nil here is the goal state, not a
/// missing row.
///
/// ⚠️ THE REFUSALS ARE CODED: 400 `assignee_not_member` (not in this workspace),
/// 400 `assignee_is_viewer` (a Viewer cannot be assigned a thread, since they cannot
/// answer it: `district-conversation-assign-viewer.json`), and the route's role guard
/// (agency and client only) for a Viewer who tries to assign.
public struct ConversationAssignResponse: Codable, Sendable {
    public let success: Bool
    /// The thread's assignment as stored, or nil after an unassign.
    public let assignment: ThreadAssignment?
}

/// Who owns one Inbox thread, as the server stored it.
public struct ThreadAssignment: Codable, Sendable, Equatable {
    /// The thread, in ``ConversationSummary/threadKey``'s form.
    public let threadKey: String
    /// The member's email, normalised (lowercased) by the server.
    public let assigneeEmail: String
    /// ISO-8601, server-stamped. This module owns no date parsing.
    public let assignedAt: String
}
