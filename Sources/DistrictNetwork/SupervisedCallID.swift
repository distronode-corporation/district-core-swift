import Foundation

/// The `Call.id` of a live call somebody is about to listen in on, proven not to be a
/// room name.
///
/// ⛔ `POST /api/district/calls/token` READS ITS `roomName` BY PREFIX, AND THIS TYPE IS
/// WHAT KEEPS A CALL ID ON THE RIGHT SIDE OF THAT TEST. The route treats a value
/// starting `meet_` or `video_` as a standalone ROOM (and `video_` silently starts a
/// billable Tavus avatar, see ``RoomName``) and anything else as a `Call.id`, whereupon
/// the caller is stamped `supervisor`. The listen-in is the one request on this surface
/// that sends a call id under the key `roomName`, so the refusal lives in the type
/// rather than in a comment at the call site. ``RoomName`` makes the mirror-image refusal.
///
/// ⛔ ANY UNDERSCORE IS REFUSED, NOT ONLY THE TWO PREFIXES, matching core-rust's
/// `LiveCallId`. A call id is a server UUID (`Call.id @default(uuid())`) and never
/// carries one, while every room family the server mints (`meet_`, `video_`, `call_`,
/// `direct_`, `preview_`) does. Refusing the separator rather than a list of prefixes
/// means a room prefix the server adds later is refused too.
///
/// ⚠️ NOT AN AUTHORIZATION CLAIM. The server looks the call up across regions and runs
/// `requireWorkspaceRole` against the workspace that owns it, so another tenant's id is
/// a 404, never a token.
public struct SupervisedCallID: Sendable, Equatable, Hashable {
    /// The wire value, exactly as the server will read it.
    public let value: String

    /// - Returns: nil for a blank id, or for one carrying an underscore (``separator``).
    public init?(_ callId: String) {
        guard !callId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        guard !callId.contains(Self.separator) else { return nil }
        value = callId
    }

    /// ⛔ THE ROOM-NAME SEPARATOR. Named so a test can build ids with it and require
    /// ``init(_:)`` to refuse every one.
    public static let separator: Character = "_"
}
