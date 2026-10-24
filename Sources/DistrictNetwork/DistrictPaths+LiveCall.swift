import Foundation

/// The two routes a person uses to act on a call they are not in: declining a ring,
/// and whispering to the agent on a live call.
///
/// ⚠️ A SIBLING FILE BECAUSE `DistrictPaths.swift` SITS AT SwiftLint's 500-LINE
/// `file_length`, the reason `DistrictPaths+Numbers.swift` exists. ``DistrictPaths/calls``
/// is internal rather than private for exactly this.
extension DistrictPaths {
    /// ⛔ A FUNCTION, LIKE ``callAnswer(_:)``, BECAUSE THE ID SITS IN THE MIDDLE OF THE
    /// PATH. `calls/{id}/decline` invites interpolation, and a `callId` carrying a `/`
    /// would address a different route; ``ApiPath/build(_:)`` encodes each element as
    /// one segment.
    static func callDecline(_ callId: String) -> [String] {
        calls + [callId, "decline"]
    }

    /// ⛔ NO ID IN THE PATH, UNLIKE EVERY OTHER PER-CALL WRITE. The call travels in the
    /// BODY (`callId`), so `calls/{id}/whisper` would 404.
    static let callsWhisper = calls + ["whisper"]
}
