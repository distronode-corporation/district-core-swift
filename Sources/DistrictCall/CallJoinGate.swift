/// Whether a call's join is still on its way, for the microphone command that must not
/// race it.
///
/// ⛔ ONE MICROPHONE TRACK PER CALL, AND THIS IS WHAT MAKES IT TRUE. Both apps join with
/// the microphone published concurrently with the join (LiveKit's
/// `ConnectOptions(enableMicrophone: true)`), and the SDK reports the room connected
/// BEFORE it publishes that track. Both reducers answer ``CallEngineEvent/connected`` with
/// ``CallCommand/setMuted(_:)`` `false` (``IncomingCallController``, ``SoftphoneSession``),
/// and the SDK's `setMicrophone(enabled: true)` arriving in that gap finds no microphone
/// publication yet and publishes a SECOND track. District AI for Mac 3.0.0 published two
/// on every answered call (2026-10-15, 14:07:23Z), and the second capture cost the first
/// its first audio frame: the join's own publish timed out ("Timed out") and the call
/// ended on screen while the room still held the participant.
///
/// ⚠️ THE ENGINE ASKS ``admitsMute(_:)`` BEFORE EVERY MUTE COMMAND. An unmute while the
/// join is out is dropped (the join publishes the microphone live); anything else waits
/// for the join and goes through only if it succeeded, when the SDK finds the one
/// publication and mutes or unmutes it. A decision, so it lives here, tested on Linux;
/// the engine stays thin.
///
/// ⚠️ ONE PER ENGINE, AND AN ENGINE IS ONE PER CALL (``CallEngine``), so a gate never sees
/// a second join.
public actor CallJoinGate {
    private enum Stage {
        case notStarted
        case joining
        case joined
        case failed
    }

    private var stage = Stage.notStarted
    private var waiters: [CheckedContinuation<Bool, Never>] = []

    public init() {}

    /// The join has started. Called immediately before the SDK's connect.
    public func begin() {
        stage = .joining
    }

    /// The join has returned, with or without a room. Every waiting command is released.
    public func finish(joined: Bool) {
        stage = joined ? .joined : .failed
        let waiting = waiters
        waiters = []
        for waiter in waiting {
            waiter.resume(returning: joined)
        }
    }

    /// Whether a mute command (`muted`, CallKit's polarity) should reach the SDK.
    ///
    /// ⛔ AN UNMUTE DURING THE JOIN IS DROPPED, NOT QUEUED. The join is already publishing
    /// the microphone live, and queuing it would hold the reducer's event loop for the
    /// whole publish only to unmute a track that is not muted.
    ///
    /// ⚠️ A MUTE DURING THE JOIN WAITS for it, and is dropped if the join failed: there is
    /// no microphone left to mute. With no join begun the command goes through, which is
    /// the engine's own business (no reducer sends one before ``CallEngineEvent/connected``).
    public func admitsMute(_ muted: Bool) async -> Bool {
        switch stage {
        case .notStarted, .joined:
            return true
        case .failed:
            return false
        case .joining:
            guard muted else { return false }
            return await withCheckedContinuation { waiters.append($0) }
        }
    }
}
