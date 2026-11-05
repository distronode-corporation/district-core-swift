import DistrictModel

/// Which of a supervise session's two room connections an engine event or command
/// belongs to.
///
/// ⛔ TWO LEGS BECAUSE A LiveKit `Room` DOES NOT RECONNECT AFTER IT DISCONNECTS, AND A
/// TAKEOVER IS A SECOND CONNECTION ON A SECOND CREDENTIAL. The listen seat can publish
/// nothing; the takeover token is a different grant that the server mints on its own
/// route. So taking over is: leave the listen room, join again as a coach. Tagging
/// every event with its leg is what stops the listen engine's own late `disconnected`,
/// which arrives AFTER the takeover join has begun, from ending the call the person has
/// just taken.
public enum SuperviseLeg: Sendable, Equatable, Hashable {
    /// The listen-only seat (``DistrictModel/CallMonitorResponse``).
    case listen
    /// The microphone-only coach seat (``DistrictModel/CallTakeoverResponse``).
    case takeover
}

/// Where a person supervising one live call is.
public enum SupervisePhase: Sendable, Equatable {
    /// Not in the call. The whisper box still works from here (it needs no room).
    case idle
    /// The listen credential has been asked for. ⚠️ No engine exists yet.
    case requestingListen
    /// The listen room is being joined.
    case joiningListen
    /// Hearing the call, heard by nobody.
    case listening
    /// ⛔ STILL LISTENING. The takeover credential has been asked for, and the listen room
    /// is kept until it arrives, so a refusal leaves the person where they were.
    case requestingTakeover
    /// The listen room has been left and the coach room is being joined. ⚠️ Nothing is
    /// heard for this moment, and no whisper may be sent: the assistant is about to step
    /// back.
    case joiningTakeover
    /// On the call with a live microphone; the assistant has stepped back and waits.
    case takenOver
    /// The call itself is over. ⛔ Terminal: everything after it is absorbed.
    case over
}

/// Why the last attempt went wrong, for the sentence beside the control that made it.
///
/// ⚠️ CLEARED BY THE NEXT ATTEMPT, never by time, like the website's per-call errors.
public enum SuperviseProblem: Sendable, Equatable {
    /// The server refused the listen seat. ⚠️ The error carries its `code`; the
    /// sentence is `DistrictL10n`'s for that code.
    case listenRefused(ApiError)
    /// The listen room could not be joined.
    case listenFailed(message: String?)
    /// The listen room dropped while the person was listening.
    case listenDropped(reason: String?)
    /// The server refused the takeover. ⛔ The person is STILL LISTENING when this is set.
    case takeoverRefused(ApiError)
    /// The coach room could not be joined, or the microphone would not start. ⛔ The listen
    /// room is already gone by then, so the person is out of the call, not back to
    /// listening (the website's `takeoverJoinFailed`).
    case takeoverJoinFailed(message: String?)
    /// The coach room dropped while the person held the call.
    case takeoverDropped(reason: String?)
}

/// Everything one supervised call is, as one person sees it.
public struct SuperviseState: Sendable, Equatable {
    /// The `Call.id` being supervised.
    public let callId: String

    /// The person's role in the call's workspace. ⛔ nil means the role could not be
    /// established, and grants nothing, not even listening (``WorkspaceRole/fromWire(_:)``).
    public let role: WorkspaceRole?

    public internal(set) var phase: SupervisePhase = .idle

    /// The leg whose engine exists right now, if any.
    public internal(set) var leg: SuperviseLeg?

    /// ⚠️ THE MICROPHONE STARTS OFF, unlike a softphone call's: a listener publishes
    /// nothing. ``CallMediaState/microphoneEnabled`` turns true only once the engine
    /// reports the takeover's microphone started.
    public internal(set) var media = SuperviseState.listenMedia()

    public internal(set) var problem: SuperviseProblem?

    /// The assistant's answer to the latest note, if one has arrived since it was sent.
    public internal(set) var receipt: WhisperReceipt?

    /// Whether the assistant is on the call (``CallSummary/hasReceptionist``). ⛔ `false` for
    /// a team member's own softphone call: Listen is still offered, Whisper and Take over
    /// are not. The routes' 409 `call_has_no_receptionist` stays the fallback for a summary
    /// read before the call changed hands.
    public let receptionistOnCall: Bool

    public init(callId: String, role: WorkspaceRole?, receptionistOnCall: Bool = true) {
        self.callId = callId
        self.role = role
        self.receptionistOnCall = receptionistOnCall
    }

    /// Whether Listen may be offered: any established role, while not in the call.
    public var mayListen: Bool {
        role != nil && phase == .idle
    }

    /// Whether a note may be sent. ⛔ Never by a viewer (the route refuses them), and never
    /// while this person holds the call or is about to: a note would make the assistant
    /// speak again over them (the website's `whisperTakenOverPlaceholder`).
    public var mayWhisper: Bool {
        guard role?.canMutate == true, receptionistOnCall else { return false }
        switch phase {
        case .idle, .requestingListen, .joiningListen, .listening, .requestingTakeover:
            return true
        case .joiningTakeover, .takenOver, .over:
            return false
        }
    }

    /// Whether Take over may be offered. ⛔ Only while listening: the listen call is the
    /// one the system already holds (CallKit on iOS), and the takeover continues it.
    public var mayTakeOver: Bool {
        role?.canMutate == true && receptionistOnCall && phase == .listening
    }

    /// Whether this person's microphone is live on the call.
    public var holdsTheCall: Bool {
        phase == .takenOver
    }

    static func listenMedia() -> CallMediaState {
        var media = CallMediaState()
        media.microphoneEnabled = false
        return media
    }
}

/// Everything that can happen while one person supervises one call.
public enum SuperviseEvent: Sendable, Equatable {
    /// The person pressed Listen. ⚠️ On iOS the app has already put a `CXStartCallAction`
    /// through CallKit.
    case listenPressed
    /// The server minted the listen seat. ⛔ Both halves verbatim.
    case listenGranted(url: String, token: String)
    /// The server refused the listen seat, or it could not be asked.
    case listenRefused(ApiError)
    /// The person pressed Take over and confirmed it.
    case takeOverPressed
    /// The server minted the coach seat. ⛔ Both halves verbatim.
    case takeoverGranted(url: String, token: String)
    /// The server refused the takeover, or it could not be asked.
    case takeoverRefused(ApiError)
    /// Something one leg's media session reported.
    case engine(SuperviseLeg, CallEngineEvent)
    /// Stop listening, or Hand back: both are leaving the room. ⛔ On iOS every producer
    /// has already put a `CXEndCallAction` through CallKit, so nothing reports it again.
    case stopPressed
    /// The call itself ended (a telemetry `call_ended`, or its status left `in-progress`).
    case callEnded
    case muteToggled
    case speakerToggled
    /// A note was sent: the previous receipt is not this one's.
    case whisperSent
    /// The assistant answered the latest note (``TelemetryEnvelope/whisperReceipt``).
    case whisperReceipt(WhisperReceipt)
}

public extension SuperviseEvent {
    /// Build ``listenGranted(url:token:)`` from the route's own body.
    static func listenGranted(_ response: CallMonitorResponse) -> SuperviseEvent {
        .listenGranted(url: response.url, token: response.token)
    }

    /// Build ``takeoverGranted(url:token:)`` from the route's own body.
    static func takeoverGranted(_ response: CallTakeoverResponse) -> SuperviseEvent {
        .takeoverGranted(url: response.url, token: response.token)
    }
}

/// What a supervise session asks the app to do.
///
/// ⛔ THE ORDER IS PART OF THE CONTRACT. A takeover grant answers
/// `[.engine(.listen, .disconnect), .join(.takeover, …)]`: the listen room is left before
/// the coach room is joined, and both happen only after the credential has arrived.
///
/// ⛔ ``reportCallEnded`` FOLLOWS ``SoftphoneCommand/reportCallEnded``'S DIVIDING LINE.
/// ``SuperviseEvent/stopPressed`` is the only ending CallKit performed itself; every other
/// ending (a refusal, a failed join, a dropped room, the call ending) is reported. The Mac,
/// which has no CallKit, ignores it.
public enum SuperviseCommand: Sendable, Equatable {
    /// Ask the server for the listen seat (`CallsRepository.monitor`). ⛔ Once.
    case requestListen
    /// Ask the server for the coach seat (`CallsRepository.takeOver`). ⛔ Once.
    case requestTakeover
    /// Build a FRESH engine for `leg` and connect it with this credential. ⚠️ Publishing
    /// nothing: the microphone, for the takeover leg only, follows as a separate
    /// ``engine(_:_:)`` command once the join is done.
    case join(SuperviseLeg, url: String, token: String)
    /// Something for `leg`'s engine. ⚠️ A command for a leg whose engine is already gone is
    /// a no-op, which ``CallEngine/disconnect()``'s idempotence already guarantees.
    case engine(SuperviseLeg, CallCommand)
    /// Tell the OS the call it holds for this supervision is over.
    case reportCallEnded
}
