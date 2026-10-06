import DistrictModel
import Foundation

/// Where one call's live transcript stands.
public enum LiveTranscriptPhase: Sendable, Equatable {
    /// Subscribed; the first snapshot has not arrived.
    case subscribing
    /// The transcript is live: lines arrive as they are spoken.
    case live
    /// The assistant stopped transcribing (or the call ended). The lines on screen stay;
    /// the full transcript is fetched (``TranscriptReducer/finalTranscript``).
    case ended(TranscriptEndReason)
    /// No live transcript can be shown for this call. The client offers the transcript
    /// after the call instead, the way it did before there was a live one.
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
    /// Send `transcript.subscribe` for the call again after the delay (0: now), for a fresh
    /// snapshot. `TelemetryConnectionRunner.resubscribeTranscript(callId:)` does that.
    case resubscribe(afterMilliseconds: Int64)
    /// Call ``TranscriptReducer/gapCheck(atMilliseconds:)`` after the delay.
    case checkGap(afterMilliseconds: Int64)
    /// After the delay, fetch `GET /api/district/calls/{id}/transcript` and hand the answer
    /// to ``TranscriptReducer/finalFetched(_:atMilliseconds:)``.
    case fetchFinal(afterMilliseconds: Int64)
    /// Stop receiving this call's transcript (`transcript.unsubscribe`): nothing more is
    /// wanted from the server.
    case unsubscribe
}

/// One call's live transcript, as a pure state machine: the client algorithm of the
/// `transcript` v1 contract.
///
/// ⛔ NO SOCKET, NO TIMER AND NO NETWORK CALL IN HERE, like ``TelemetryConnection``: events
/// in, commands out, every rule tested on Linux with an injected time. The app performs
/// the commands.
///
/// The rules:
///
/// 1. **Stale frames.** A frame's `seq` counts per (call, epoch). One already seen is
///    dropped: delivery is at least once and unordered. ⚠️ "Already seen" is tracked as
///    the highest `seq` plus the gaps below it, NOT as the highest alone: a frame that
///    arrives after a later one fills its gap rather than being dropped as stale, which a
///    bare high-water mark would do, losing the line for good.
/// 2. **Revisions.** Each segment keeps its latest revision by `rev`; a lower one is
///    ignored, and a final always beats an interim at any `rev`.
/// 3. **Order.** (epoch, index), then the segment id so ties are stable.
/// 4. **Gaps.** A `seq` that skips ahead opens a gap. If one is still open
///    ``gapHealMilliseconds`` later, the call is subscribed again and the snapshot
///    replaces the state.
/// 5. **Snapshot.** Replaces the state with the union of its parts once the last arrives;
///    live frames that arrive meanwhile are held and applied after it, where any at or
///    below its `lastSeq` is a duplicate.
/// 6. **End.** `transcript_ended` (or `call_ended`, on a socket that takes broadcasts)
///    marks it not live and starts fetching the full transcript, which is written only
///    after the call's session closes: an empty answer is retried with backoff.
public struct TranscriptReducer: Sendable, Equatable {
    /// How long a gap may stay open before the call is subscribed again.
    public static let gapHealMilliseconds: Int64 = 2000

    /// The wait before re-subscribing after `rate_limited` that gave no `retryAfterMs`.
    public static let rateLimitFallbackMilliseconds: Int64 = 2000

    /// The longest gap tracked seq by seq. A larger jump is a gap only a snapshot heals.
    public static let trackedGapLimit = 1000

    /// How many times the full transcript is asked for before giving up.
    public static let finalFetchAttempts = 8

    /// The wait before final-transcript attempt `attempt` (1 for the first): 2 s, doubling
    /// up to 30 s. Eight attempts span two and a half minutes.
    public static func finalFetchDelayMilliseconds(attempt: Int) -> Int64 {
        min(2000 << Int64(min(max(attempt, 1) - 1, 8)), 30000)
    }

    /// The op name a `transcript_error` carries for a refused subscribe.
    static let subscribeOp = "transcript.subscribe"

    public let callId: String
    public private(set) var phase: LiveTranscriptPhase = .subscribing
    /// False when the server's memory did not reach back to the call's first line: the
    /// client says the earlier lines will be in the full transcript after the call.
    public private(set) var complete = true
    public private(set) var finalTranscript: FinalTranscriptState = .notRequested

    private var segments: [String: TranscriptSegment] = [:]
    /// Segment ids retracted one by one, so a late copy cannot bring one back.
    private var tombstones: Set<String> = []
    private var seqs: [Int64: SeqTrack] = [:]
    private var gapOpenedAt: Int64?
    /// The parts of a snapshot still arriving, and the live frames held until it is whole.
    private var pendingSnapshot: [TranscriptSnapshotData]?
    private var heldFrames: [LiveFrame] = []
    /// The epoch whose `transcript_ended` was applied.
    private var endedEpoch: Int64?

    /// A frame that is not a snapshot.
    private enum LiveFrame: Sendable, Equatable {
        case segment(TranscriptSegment)
        case ended(TranscriptEndedData)
        case retracted(TranscriptRetractedData)
        case error(TranscriptErrorData)
    }

    /// What has been seen of one epoch's `seq` counter.
    private struct SeqTrack: Sendable, Equatable {
        var high: Int
        var missing: Set<Int> = []
        /// A jump beyond ``TranscriptReducer/trackedGapLimit``: only a snapshot heals it.
        var overflowed = false

        var hasGap: Bool {
            overflowed || !missing.isEmpty
        }
    }

    public init(callId: String) {
        self.callId = callId
    }

    /// The lines to show, in order. An interim one (`final == false`) is drawn as
    /// provisional.
    public var lines: [TranscriptSegment] {
        segments.values.sorted { lhs, rhs in
            (lhs.epoch, lhs.index, lhs.segmentId) < (rhs.epoch, rhs.index, rhs.segmentId)
        }
    }

    // MARK: - Inputs

    /// Apply one transcript event received at `now` (milliseconds). ⚠️ Events for another
    /// call change nothing.
    public mutating func apply(_ event: TranscriptEvent, atMilliseconds now: Int64) -> [TranscriptCommand] {
        guard event.callId == callId else { return [] }
        let frame: LiveFrame
        switch event {
        case let .snapshot(data):
            return snapshotPart(data, now: now)
        case let .segment(data):
            frame = .segment(data.segment)
        case let .ended(data):
            frame = .ended(data)
        case let .retracted(data):
            frame = .retracted(data)
        case let .error(data):
            frame = .error(data)
        }
        guard pendingSnapshot == nil else {
            heldFrames.append(frame)
            return []
        }
        return live(frame, now: now)
    }

    /// The socket opened again after a gap, and the connection has re-sent the subscribe:
    /// a snapshot is on its way and will replace the state. ⚠️ So a half-received snapshot
    /// from the old socket, and the frames held behind it, are dropped, and any open gap is
    /// closed. The lines on screen stay until the snapshot lands.
    public mutating func reconnected() {
        pendingSnapshot = nil
        heldFrames = []
        clearGaps()
    }

    /// A `call_ended` for this call arrived (on a socket that takes broadcasts).
    public mutating func callEnded() -> [TranscriptCommand] {
        end(.callEnded)
    }

    /// The ``TranscriptCommand/checkGap(afterMilliseconds:)`` delay ran out.
    ///
    /// ⚠️ RE-CHECKS THE FACT RATHER THAN TRUSTING THE TIMER: a gap that closed meanwhile
    /// asks for nothing, and one opened later is given the rest of its time.
    public mutating func gapCheck(atMilliseconds now: Int64) -> [TranscriptCommand] {
        guard let opened = gapOpenedAt else { return [] }
        let waited = now &- opened
        guard waited >= Self.gapHealMilliseconds else {
            return [.checkGap(afterMilliseconds: Self.gapHealMilliseconds - waited)]
        }
        clearGaps()
        return [.resubscribe(afterMilliseconds: 0)]
    }

    /// The answer to ``TranscriptCommand/fetchFinal(afterMilliseconds:)``.
    public mutating func finalFetched(_ result: Result<String, ApiError>) -> [TranscriptCommand] {
        guard case let .fetching(attempt) = finalTranscript else { return [] }
        let retryable: Bool
        switch result {
        case let .success(text):
            guard text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                finalTranscript = .loaded(text)
                return [.unsubscribe]
            }
            retryable = true
        case let .failure(error):
            retryable = Self.isTransient(error)
        }
        guard retryable, attempt < Self.finalFetchAttempts else {
            finalTranscript = result.failureOnly.map(FinalTranscriptState.failed) ?? .empty
            return [.unsubscribe]
        }
        finalTranscript = .fetching(attempt: attempt + 1)
        return [.fetchFinal(afterMilliseconds: Self.finalFetchDelayMilliseconds(attempt: attempt + 1))]
    }

    // MARK: - Snapshots

    private mutating func snapshotPart(_ data: TranscriptSnapshotData, now: Int64) -> [TranscriptCommand] {
        var parts = data.part == 0 ? [] : (pendingSnapshot ?? [])
        // ⚠️ A PART OUT OF ORDER means parts were lost between two subscribes; nothing can
        // be assembled from them, so ask for a whole snapshot again.
        guard parts.count == data.part else {
            pendingSnapshot = nil
            return [.resubscribe(afterMilliseconds: 0)]
        }
        parts.append(data)
        guard !data.more else {
            pendingSnapshot = parts
            return []
        }
        pendingSnapshot = nil
        var commands = replace(with: parts)
        let held = heldFrames
        heldFrames = []
        for event in held {
            commands += live(event, now: now)
        }
        return commands
    }

    private mutating func replace(with parts: [TranscriptSnapshotData]) -> [TranscriptCommand] {
        let last = parts[parts.count - 1]
        segments = [:]
        for segment in parts.flatMap(\.segments) where !tombstones.contains(segment.segmentId) {
            merge(segment)
        }
        complete = last.complete
        for epoch in seqs.keys {
            seqs[epoch]?.missing = []
            seqs[epoch]?.overflowed = false
        }
        if let epoch = last.epoch, let lastSeq = last.lastSeq {
            seqs[epoch] = SeqTrack(high: lastSeq)
        }
        gapOpenedAt = nil
        guard last.live else {
            endedEpoch = last.epoch
            return end(.callEnded)
        }
        phase = .live
        return []
    }

    // MARK: - Live frames

    private mutating func live(_ frame: LiveFrame, now: Int64) -> [TranscriptCommand] {
        switch frame {
        case let .segment(segment):
            self.segment(segment, now: now)
        case let .ended(data):
            ended(data, now: now)
        case let .retracted(data):
            retracted(data, now: now)
        case let .error(data):
            error(data)
        }
    }

    private mutating func segment(_ segment: TranscriptSegment, now: Int64) -> [TranscriptCommand] {
        let (fresh, commands) = admit(epoch: segment.epoch, seq: segment.seq, now: now)
        guard fresh, !tombstones.contains(segment.segmentId) else { return commands }
        merge(segment)
        // ⚠️ A NEWER EPOCH AFTER AN END IS A RE-DISPATCHED ASSISTANT: the call is live again.
        if case .ended = phase, let endedEpoch, segment.epoch > endedEpoch {
            phase = .live
        }
        return commands
    }

    /// Rule 2: the latest revision wins, and a final beats an interim at any revision.
    private mutating func merge(_ incoming: TranscriptSegment) {
        guard let stored = segments[incoming.segmentId] else {
            segments[incoming.segmentId] = incoming
            return
        }
        let wins = stored.final == incoming.final ? incoming.rev >= stored.rev : incoming.final
        if wins {
            segments[incoming.segmentId] = incoming
        }
    }

    private mutating func ended(_ data: TranscriptEndedData, now: Int64) -> [TranscriptCommand] {
        let (fresh, commands) = admit(epoch: data.epoch, seq: data.seq, now: now)
        guard fresh else { return commands }
        endedEpoch = max(endedEpoch ?? data.epoch, data.epoch)
        return commands + end(data.reason)
    }

    private mutating func end(_ reason: TranscriptEndReason) -> [TranscriptCommand] {
        phase = .ended(reason)
        guard finalTranscript == .notRequested else { return [] }
        finalTranscript = .fetching(attempt: 1)
        return [.fetchFinal(afterMilliseconds: Self.finalFetchDelayMilliseconds(attempt: 1))]
    }

    /// ⚠️ A RETRACTION IS APPLIED EVEN WHEN ITS `seq` WAS SEEN: dropping lines twice is
    /// harmless, and leaving one on screen is not. Its `seq` is still recorded, so the
    /// counter shows no gap. With no epoch on the frame (the v1 contract carries none),
    /// the seq is taken as the newest epoch's.
    private mutating func retracted(_ data: TranscriptRetractedData, now: Int64) -> [TranscriptCommand] {
        var commands: [TranscriptCommand] = []
        if let seq = data.seq, let epoch = data.epoch ?? seqs.keys.max() {
            commands = admit(epoch: epoch, seq: seq, now: now).commands
        }
        let gone = data.all ? Array(segments.keys) : data.segmentIds
        for segmentId in gone {
            segments[segmentId] = nil
            tombstones.insert(segmentId)
        }
        return commands
    }

    /// ⚠️ ONLY ERRORS ABOUT THIS CALL REACH HERE (see ``apply(_:atMilliseconds:)``), and
    /// only one about a subscribe changes anything: a refused unsubscribe needs no answer,
    /// and re-subscribing after it would undo it.
    private mutating func error(_ data: TranscriptErrorData) -> [TranscriptCommand] {
        guard data.op == nil || data.op == Self.subscribeOp else { return [] }
        switch data.code {
        case .rateLimited:
            return [.resubscribe(afterMilliseconds: data.retryAfterMs ?? Self.rateLimitFallbackMilliseconds)]
        case .notLive:
            // ⚠️ AN ENDED TRANSCRIPT STAYS ENDED: `not_live` also answers a subscribe more
            // than two minutes after the end, which changes nothing about the lines shown.
            if case .ended = phase {
                return []
            }
            phase = .unavailable(data.code)
            return [.unsubscribe]
        case .badRequest, .unsupportedVersion, .forbiddenRole, .tooManySubscriptions, .other:
            phase = .unavailable(data.code)
            return [.unsubscribe]
        }
    }

    // MARK: - Sequence tracking

    /// Whether the frame `(epoch, seq)` is new, and the gap check it may start.
    ///
    /// ⚠️ NO GAP IS OPENED BEFORE THE FIRST SNAPSHOT (it sets the baseline), NOR FOR THE
    /// FIRST FRAME OF AN EPOCH OLDER THAN ONE ALREADY SEEN: that is a late copy of a
    /// session the snapshot already summarised, not a sign of lost frames.
    private mutating func admit(epoch: Int64, seq: Int, now: Int64) -> (fresh: Bool, commands: [TranscriptCommand]) {
        let older = seqs.keys.contains { $0 > epoch }
        var track = seqs[epoch] ?? SeqTrack(high: phase == .subscribing || older ? seq - 1 : 0)
        if seq <= track.high {
            guard track.missing.remove(seq) != nil else { return (false, []) }
        } else {
            let skipped = seq - track.high - 1
            if skipped > Self.trackedGapLimit {
                track.overflowed = true
            } else if skipped > 0 {
                track.missing.formUnion(track.high + 1 ..< seq)
            }
            track.high = seq
        }
        seqs[epoch] = track
        return (true, updateGap(now: now))
    }

    private mutating func updateGap(now: Int64) -> [TranscriptCommand] {
        guard seqs.values.contains(where: \.hasGap) else {
            gapOpenedAt = nil
            return []
        }
        guard gapOpenedAt == nil else { return [] }
        gapOpenedAt = now
        return [.checkGap(afterMilliseconds: Self.gapHealMilliseconds)]
    }

    private mutating func clearGaps() {
        for epoch in seqs.keys {
            seqs[epoch]?.missing = []
            seqs[epoch]?.overflowed = false
        }
        gapOpenedAt = nil
    }

    /// Whether a failed fetch may succeed later: no answer, a 5xx, a 429 or a 401 (see
    /// ``TelemetryConnection/isTransient(_:)``, the same rule).
    private static func isTransient(_ error: ApiError) -> Bool {
        TelemetryConnection.isTransient(error)
    }
}

private extension Result {
    var failureOnly: Failure? {
        guard case let .failure(error) = self else { return nil }
        return error
    }
}
