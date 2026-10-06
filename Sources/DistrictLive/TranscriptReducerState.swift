import DistrictModel

// What `TranscriptReducer` reports and asks for.

/// Where one call's live transcript stands.
public enum LiveTranscriptPhase: Sendable, Equatable {
    /// Subscribed; the first snapshot has not arrived. ⚠️ THIS CAN LAST UP TO 30 SECONDS: the
    /// server holds a subscribe until the assistant's first line, then answers with a
    /// snapshot that already has it (or with `not_live`).
    case subscribing
    /// The transcript is live: lines arrive as they are spoken.
    case live
    /// The assistant stopped with an error (`transcript_ended`, reason `agent_error`), and the
    /// call may be handed to a fresh one, whose lines arrive as a new epoch. The lines on
    /// screen stay. Ends with a new epoch (back to ``live``) or the call's end (``ended(_:)``).
    case reconnecting
    /// The assistant stopped transcribing (or the call ended). The lines on screen stay;
    /// the full transcript is fetched (``TranscriptReducer/finalTranscript``).
    case ended(TranscriptEndReason)
    /// No live transcript can be shown for this call. The client offers the transcript
    /// after the call instead, the way it did before there was a live one.
    /// ⚠️ `not_live` IS FINAL FOR THAT SUBSCRIBE: only a new call-status signal subscribes
    /// again (``TranscriptReducer/callStatusChanged(to:)``), never a timer.
    case unavailable(TranscriptErrorCode)
}

/// The full transcript, fetched once the live one ended.
public enum FinalTranscriptState: Sendable, Equatable {
    /// Not asked for: the transcript has not ended.
    case notRequested
    /// Being fetched; `attempt` counts from 1.
    case fetching(attempt: Int)
    /// The transcript the server keeps for the call.
    case loaded(String)
    /// Still empty after every attempt: nothing was said, or it was never written.
    case empty
    /// The fetch failed, for good or after every attempt.
    case failed(ApiError)
}

/// What a ``TranscriptReducer`` asks its owner to do.
///
/// ⚠️ AT MOST ONE OF EACH KIND IS PENDING: a new one replaces any earlier one of its kind.
public enum TranscriptCommand: Sendable, Equatable {
    /// Subscribe to the call again, as a new subscription: the last one ended in `not_live`
    /// and a call-status signal says the call changed since. `TelemetryConnectionRunner
    /// .subscribeTranscript(callId:)` does that.
    case subscribe
    /// Send `transcript.subscribe` for the call again after the delay (0: now), for a fresh
    /// snapshot. `TelemetryConnectionRunner.resubscribeTranscript(callId:)` does that.
    case resubscribe(afterMilliseconds: Int64)
    /// Call ``TranscriptReducer/gapCheck(atMilliseconds:)`` after the delay.
    case checkGap(afterMilliseconds: Int64)
    /// After the delay, fetch `GET /api/district/calls/{id}/transcript` and hand the answer
    /// to ``TranscriptReducer/finalFetched(_:)``.
    case fetchFinal(afterMilliseconds: Int64)
    /// Stop receiving this call's transcript (`transcript.unsubscribe`): nothing more is
    /// wanted from the server.
    case unsubscribe
}
