import Foundation

/// Live supervision: listening in on a call the assistant is handling, and taking it over.
/// (The third action, the text whisper, is ``DistrictEndpoints/whisper(workspaceId:callId:text:)``.)
///
/// ⚠️ ITS OWN FILE FOR SwiftLint's 500-LINE `file_length`, like the other `+` families.
public extension DistrictEndpoints {
    /// A listen-only seat on a live call.
    ///
    /// ⛔ THE SAME ROUTE AS ``roomToken(roomName:platform:)`` AND THE OPPOSITE ROLE. Given a
    /// `Call.id` rather than a `meet_` name, `calls/token` mints a token that may SUBSCRIBE
    /// and publish nothing (no audio, no data), with metadata `role: "supervisor"` (or
    /// `"viewer"`), and the voice agent then unsubscribes this person's microphone. That
    /// is right for a listener and is why a meeting join may never come through here; the
    /// ``SupervisedCallID`` type is the refusal in that direction.
    ///
    /// ⛔ NEVER RETRIED AUTOMATICALLY. Each send mints a credential; a retry loop would
    /// outlive a call that ended. Roles `["agency","client","viewer"]`: a viewer may listen.
    ///
    /// ⚠️ The body key is `roomName` and the value is the call id, the route's historical
    /// naming. `identity` is required and ignored, as for a room (see ``RoomIdentity``).
    static func monitorCall(callId: SupervisedCallID, platform: ClientPlatform = .ios) -> ApiRequestDescriptor {
        ApiRequestDescriptor(
            .monitorCall,
            .post,
            DistrictPaths.callsToken,
            body: .json(.object([
                ("roomName", .string(callId.value)),
                ("identity", .string(RoomIdentity.value(for: platform))),
            ]))
        )
    }

    /// The microphone-only credential that takes a live call over from the assistant.
    ///
    /// ⛔ NOT ``answerCall(callId:workspaceId:)``. Answer stamps `handoff` and the agent
    /// leaves the call to the humans for good; this stamps `mode: "barge-in"` with no
    /// `handoff`, so the agent announces a supervisor, steps back, and picks the call up
    /// again when this person LEAVES the room. There is no other way to hand back.
    ///
    /// ⛔ NEVER RETRIED AUTOMATICALLY: a credential that answered after the person gave up
    /// would put a live microphone in a customer's call. Roles `["agency","client"]`; the
    /// route also answers 409 `call_not_in_progress` (not live, or no deployment holds the
    /// room), 409 `call_has_no_room`, 409 `call_has_no_receptionist` (a team member's own
    /// softphone call), 404 `call_not_found`, 429 (20 a minute per workspace) and 503
    /// `service_unavailable` / `service_not_configured`.
    static func takeOverCall(callId: String, workspaceId: String) -> ApiRequestDescriptor {
        ApiRequestDescriptor(
            .takeOverCall,
            .post,
            DistrictPaths.callTakeover(callId),
            body: .json(.object([("workspaceId", .string(workspaceId))]))
        )
    }
}
