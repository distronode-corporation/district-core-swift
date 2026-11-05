import Foundation

/// `POST /api/district/calls/token` with a `Call.id`: a listen-only seat on a live call.
///
/// ⛔ ITS OWN TYPE, NOT ``RoomTokenResponse``, ALTHOUGH THE ROUTE IS THE SAME. That type
/// models the `meet_` branch and says, correctly, that the call branch is unreachable
/// through it. This branch answers three keys and never the other three: no `e2ee` (a
/// call room carries a SIP leg, which no app-side key can protect, so the server's
/// `isE2eeRoom` excludes it), and no `guestInvite` or `guestPath` (an invite is a
/// meeting-room capability). A shared DTO would make a listener's join look as though it
/// might be encrypted.
///
/// ⛔ ``url`` IS THE SERVER'S CHOICE OF MEDIA NODE AND IS USED VERBATIM. It is resolved
/// from the ROOM: a phone call lives on whichever deployment carried it, which for a
/// Canadian or US number is the US hub whatever the workspace's region.
///
/// ⚠️ THE GRANT IS SUBSCRIBE ONLY. The token may not publish audio, video or data, so a
/// listener is heard by nobody and cannot whisper from inside the room (the whisper goes
/// through its own route). The agent unsubscribes this participant's microphone anyway.
/// Taking the call over is a second credential, ``CallTakeoverResponse``, never an
/// unmute of this one.
public struct CallMonitorResponse: Codable, Sendable, Equatable {
    public let success: Bool
    /// The LiveKit token, ~30 minutes. ⚠️ It authorises the JOIN; a connection already
    /// established is not re-checked against it, but a rejoin after it expires needs a
    /// fresh one.
    public let token: String
    /// ⛔ Used verbatim. See the type note.
    public let url: String

    public init(success: Bool, token: String, url: String) {
        self.success = success
        self.token = token
        self.url = url
    }
}

/// `POST /api/district/calls/{callId}/takeover`: the credential that takes a live call
/// over from the assistant, by voice.
///
/// ⛔ THE SAME FOUR KEYS AS ``CallAnswerResponse`` AND A DIFFERENT CREDENTIAL, which is why
/// it is its own type. An answer carries `handoff` and ends the assistant's part of the
/// call; this carries `mode: "barge-in"` without it, so the assistant announces a
/// supervisor, steps back and waits, and resumes when this person leaves the room. A
/// screen that treated one as the other would either strand the caller with nobody (an
/// answer read as reversible) or keep the assistant waiting for ever (a takeover read as
/// final).
///
/// ⚠️ THE GRANT IS THE MICROPHONE AND NOTHING ELSE: no camera, no screen share, no data
/// and no metadata updates (the agent authorises on metadata, so a client that could
/// rewrite its own could switch itself into the handoff branch).
///
/// ⚠️ THE IDENTITY IS THE SAME ONE THE LISTEN TOKEN CARRIES for this person, so joining
/// with this token REPLACES the listen-only participant rather than adding a second one.
/// The app still leaves the listen room first: a LiveKit `Room` serves one connection.
public struct CallTakeoverResponse: Codable, Sendable, Equatable {
    public let success: Bool
    /// ⛔ The websocket URL of the deployment that holds the room, found by asking each
    /// one (`locateSipRoom`). Used verbatim.
    public let url: String
    /// The supervisor's LiveKit token, ~70 minutes: they are a party to the call from here.
    public let token: String
    /// The `call_…` room. ⚠️ Modelled because the body carries it; nothing joins by it.
    public let roomName: String

    public init(success: Bool, url: String, token: String, roomName: String) {
        self.success = success
        self.url = url
        self.token = token
        self.roomName = roomName
    }
}
