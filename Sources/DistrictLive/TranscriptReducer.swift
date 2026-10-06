import DistrictModel
import Foundation

/// One call's live transcript, as a pure state machine: the client algorithm of the
/// `transcript` v1 contract (§4.6, with the §4.12 clarifications).
///
/// ⛔ NO SOCKET, NO TIMER AND NO NETWORK CALL IN HERE, like ``TelemetryConnection``: events
/// in, commands out, every rule tested on Linux with an injected time. The app performs
/// the commands.
///
/// The rules:
///
/// 1. **Stale frames.** Per epoch, a high-water mark `lastSeq[epoch]` (0 before the first
///    frame) and the set of missing seqs below it. A frame above the mark raises it, and
///    the seqs it skipped join the missing set; a frame whose seq is missing fills its gap
///    and is applied; anything else is a duplicate and is dropped. ⚠️ Delivery is at least
///    once and unordered, so a late frame is normal: a bare "drop `seq` at or below the
///    mark" would lose it for good.
/// 2. **Revisions.** Each segment keeps its latest revision by `rev`; a lower one is
///    ignored, and a final always beats an interim at any `rev`.
/// 3. **Order.** (epoch, index), then the segment id so ties are stable.
/// 4. **Gaps.** If the missing set has been non-empty for ``gapHealMilliseconds``, the call
///    is subscribed again and the snapshot replaces the state. ⛔ ONE HEAL IN FLIGHT: no
///    subscribe goes out while an earlier one is unanswered (its snapshot's last part, or a
///    refusal, has not arrived).
/// 5. **Snapshot.** Its parts arrive back to back with the same header (`live`, `complete`,
///    `epoch`, `lastSeq`); the union replaces the state once the last arrives. It sets
///    `lastSeq[epoch]` with an empty missing set, and every older epoch is closed: a later
///    frame of one is dropped. A broken snapshot (a part out of order, a header that
///    changed, or another frame between parts) is asked for again. Its `endedReason` says
///    why it is not live. One with no epoch follows an `all: true` purge: the next frame of
///    each epoch sets its baseline.
/// 6. **End.** `transcript_ended` with `call_ended` or `handed_off` (or `call_ended` on a
///    socket that takes broadcasts) is terminal: not live, and the full transcript is
///    fetched, which is written only after the call's session closes, so an empty answer is
///    retried with backoff. ⚠️ `agent_error` is not: the call may get a fresh assistant, so
///    the transcript is ``LiveTranscriptPhase/reconnecting`` until a new epoch or the end.
public struct TranscriptReducer: Sendable, Equatable {
    /// How long a gap may stay open before the call is subscribed again.
    public static let gapHealMilliseconds: Int64 = 2000

    /// The wait before re-subscribing after `rate_limited` that gave no `retryAfterMs`.
    public static let rateLimitFallbackMilliseconds: Int64 = 2000

    /// The least time between two subscribes after `not_live` (§4.12 Q10).
    public static let notLiveResubscribeMilliseconds: Int64 = 30000

    /// How many times the full transcript is asked for before giving up.
    public static let finalFetchAttempts = 8

    /// The wait before final-transcript attempt `attempt` (1 for the first): 2 s, doubling
    /// up to 30 s. Eight attempts span two and a half minutes.
    public static func finalFetchDelayMilliseconds(attempt: Int) -> Int64 {
        min(2000 << Int64(min(max(attempt, 1) - 1, 8)), 30000)
    }

    /// The op a `transcript_error` about a subscribe carries: the server echoes the exact
    /// `op` string the client sent (`not_live` carries it too).
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
    /// The newest snapshot's epoch: every older epoch is closed.
    private var closedBelow: Int64?
    /// The newest epoch any frame or snapshot named.
    private var newestEpoch: Int64?
    /// Since when the missing set has been non-empty.
    private var gapOpenedAt: Int64?
    /// ⛔ A SUBSCRIBE IS UNANSWERED: no other may be sent. True from the start, since the
    /// owner subscribes before the first event.
    private var awaitingSnapshot = true
    /// The snapshot whose parts are still arriving.
    private var assembly: Assembly?
    /// The epoch the last end applied to.
    private var endedEpoch: Int64?
    /// The end is known to be final (`call_ended`, `handed_off`, or the call's own end), as
    /// opposed to `agent_error` or a snapshot that says only "not live".
    private var terminal = false
    /// When the call was last subscribed again after `not_live`.
    private var resubscribedAfterNotLiveAt: Int64?
    /// An `all: true` purge left no baseline: the first frame of an epoch sets one, with no
    /// earlier seq counted as missing (§4.12 Q12).
    private var unbaselined = false

    /// What has been seen of one epoch's `seq` counter.
    private struct SeqTrack: Sendable, Equatable {
        var high: Int
        /// The seqs below ``high`` not yet seen, as ranges: a jump of any size costs one.
        var missing: [ClosedRange<Int>] = []

        /// Take `seq` out of the missing set; whether it was there.
        mutating func fill(_ seq: Int) -> Bool {
            guard let index = missing.firstIndex(where: { $0.contains(seq) }) else { return false }
            let range = missing.remove(at: index)
            if seq < range.upperBound {
                missing.insert(seq + 1 ... range.upperBound, at: index)
            }
            if range.lowerBound < seq {
                missing.insert(range.lowerBound ... seq - 1, at: index)
            }
            return true
        }
    }

    /// A snapshot being put together from its parts.
    private struct Assembly: Sendable, Equatable {
        let header: TranscriptSnapshotData
        var segments: [TranscriptSegment]
        var nextPart: Int
        var broken: Bool
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
        switch event {
        case let .snapshot(data):
            return snapshotPart(data, now: now)
        case let .segment(data):
            let commands = interruptAssembly()
            return commands + segment(data.segment, now: now)
        case let .ended(data):
            let commands = interruptAssembly()
            return commands + ended(data, now: now)
        case let .retracted(data):
            let commands = interruptAssembly()
            return commands + retracted(data, now: now)
        case let .error(data):
            // An error answers an op, not the transcript's flow: it leaves a snapshot that is
            // arriving alone.
            return error(data)
        }
    }

    /// ⚠️ A SNAPSHOT'S PARTS ARRIVE BACK TO BACK (§4.12 Q6), so a segment, end or
    /// retraction for the call while one is being put together means the rest of it was
    /// lost: ask for a whole one.
    private mutating func interruptAssembly() -> [TranscriptCommand] {
        guard assembly != nil else { return [] }
        assembly = nil
        return heal(after: 0)
    }

    /// The socket opened again after a gap, and the connection has re-sent the subscribe:
    /// a snapshot is on its way and will replace the state. ⚠️ So a half-received snapshot
    /// from the old socket is dropped. The lines on screen stay until the snapshot lands.
    public mutating func reconnected() {
        assembly = nil
        awaitingSnapshot = true
    }

    /// A `call_ended` for this call arrived (on a socket that takes broadcasts), or the
    /// call row shows the call is over. ⚠️ Nothing for a call with no live transcript: the
    /// client already offers the one after the call.
    public mutating func callEnded() -> [TranscriptCommand] {
        if case .unavailable = phase {
            return []
        }
        return end(.callEnded, terminal: true)
    }

    /// A call-status signal shows the call in progress: `call_started` or `call_updated`
    /// on a socket that takes broadcasts, or the call row as the app already reads it
    /// (§4.12 Q4, Q10). ⛔ THE ONLY WAY BACK FROM `not_live`, and at most once per
    /// ``notLiveResubscribeMilliseconds`` per call: never a timer, and never more often
    /// than the reads that report it. While the transcript is anything but `not_live`, it
    /// asks for nothing.
    public mutating func callShownInProgress(atMilliseconds now: Int64) -> [TranscriptCommand] {
        guard phase == .unavailable(.notLive) else { return [] }
        if let last = resubscribedAfterNotLiveAt, now &- last < Self.notLiveResubscribeMilliseconds {
            return []
        }
        resubscribedAfterNotLiveAt = now
        phase = .subscribing
        awaitingSnapshot = true
        return [.subscribe]
    }

    /// The ``TranscriptCommand/checkGap(afterMilliseconds:)`` delay ran out.
    ///
    /// ⚠️ RE-CHECKS THE FACT RATHER THAN TRUSTING THE TIMER: a gap that closed meanwhile
    /// asks for nothing, one opened later is given the rest of its time, and while a
    /// subscribe is unanswered nothing is sent, since its snapshot will settle the gap.
    public mutating func gapCheck(atMilliseconds now: Int64) -> [TranscriptCommand] {
        guard let opened = gapOpenedAt, !awaitingSnapshot else { return [] }
        let waited = now &- opened
        guard waited >= Self.gapHealMilliseconds else {
            return [.checkGap(afterMilliseconds: Self.gapHealMilliseconds - waited)]
        }
        return heal(after: 0)
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
        var whole: Assembly
        if data.part == 0 {
            whole = Assembly(header: data, segments: data.segments, nextPart: 1, broken: false)
        } else if var current = assembly, current.nextPart == data.part, Self.sameHeader(current.header, data) {
            current.segments += data.segments
            current.nextPart += 1
            whole = current
        } else {
            // ⚠️ A PART OUT OF ORDER, ONE WITH NO PART 0, OR A HEADER THAT CHANGED: nothing
            // can be put together from it. The rest of it is let through, then a whole
            // snapshot is asked for, so two heals are never in flight at once.
            whole = Assembly(header: data, segments: [], nextPart: data.part + 1, broken: true)
        }
        guard !data.more else {
            assembly = whole
            return []
        }
        assembly = nil
        awaitingSnapshot = false
        guard !whole.broken else { return heal(after: 0) }
        return replace(with: whole, now: now)
    }

    /// §4.12 Q6: `live`, `endedReason`, `complete`, `epoch` and `lastSeq` are the same on
    /// every part.
    private static func sameHeader(_ lhs: TranscriptSnapshotData, _ rhs: TranscriptSnapshotData) -> Bool {
        (lhs.live, lhs.complete, lhs.epoch, lhs.lastSeq) == (rhs.live, rhs.complete, rhs.epoch, rhs.lastSeq)
            && lhs.endedReason == rhs.endedReason
    }

    private mutating func replace(with whole: Assembly, now: Int64) -> [TranscriptCommand] {
        let header = whole.header
        segments = [:]
        for segment in whole.segments where !tombstones.contains(segment.segmentId) {
            merge(segment)
        }
        complete = header.complete
        // ⚠️ `lastSeq` COVERS THE SNAPSHOT'S EPOCH ONLY, the newest the server holds. Older
        // epochs' lines stay for display and the epochs are closed.
        if let epoch = header.epoch, let lastSeq = header.lastSeq {
            seqs = [epoch: SeqTrack(high: lastSeq)]
            closedBelow = max(closedBelow ?? epoch, epoch)
            newestEpoch = max(newestEpoch ?? epoch, epoch)
            unbaselined = false
        } else {
            // ⚠️ PURGED (§4.12 Q12): no mark and no missing seq, until a frame sets one.
            seqs = [:]
            unbaselined = true
        }
        gapOpenedAt = nil
        // ⚠️ A FINAL END STAYS FINAL, whatever a later snapshot says.
        guard !terminal else { return [] }
        guard !header.live else {
            revive()
            return []
        }
        endedEpoch = header.epoch
        switch header.endedReason {
        case .agentError?:
            // §4.12 Q9: the wait for a fresh assistant, as after the live frame.
            phase = .reconnecting
            finalTranscript = .notRequested
            return []
        case let reason?:
            return end(reason, terminal: true)
        case nil:
            // ⚠️ A SERVER OLDER THAN §4.12 Q9 SENDS NO REASON: an end a newer epoch may still
            // undo (see ``awaitingNewEpoch``).
            return end(.callEnded, terminal: false)
        }
    }

    // MARK: - Live frames

    private mutating func segment(_ segment: TranscriptSegment, now: Int64) -> [TranscriptCommand] {
        let (fresh, commands) = admit(epoch: segment.epoch, seq: segment.seq, now: now)
        guard fresh, !tombstones.contains(segment.segmentId) else { return commands }
        merge(segment)
        // ⚠️ A NEWER EPOCH AFTER AN END THAT WAS NOT FINAL IS A FRESH ASSISTANT: live again.
        if awaitingNewEpoch, endedEpoch.map({ segment.epoch > $0 }) ?? true {
            revive()
        }
        return commands
    }

    /// After `agent_error`, or a snapshot that said only "not live".
    private var awaitingNewEpoch: Bool {
        guard !terminal else { return false }
        switch phase {
        case .reconnecting, .ended: return true
        case .subscribing, .live, .unavailable: return false
        }
    }

    private mutating func revive() {
        phase = .live
        finalTranscript = .notRequested
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

    /// ⚠️ ONLY THE NEWEST EPOCH'S END CHANGES THE PHASE: a late end of an older one is
    /// counted and nothing more.
    private mutating func ended(_ data: TranscriptEndedData, now: Int64) -> [TranscriptCommand] {
        let (fresh, commands) = admit(epoch: data.epoch, seq: data.seq, now: now)
        guard fresh, data.epoch == newestEpoch else { return commands }
        endedEpoch = data.epoch
        guard data.reason == .agentError else {
            return commands + end(data.reason, terminal: true)
        }
        if !terminal {
            phase = .reconnecting
        }
        return commands
    }

    private mutating func end(_ reason: TranscriptEndReason, terminal: Bool) -> [TranscriptCommand] {
        phase = .ended(reason)
        self.terminal = self.terminal || terminal
        guard finalTranscript == .notRequested else { return [] }
        finalTranscript = .fetching(attempt: 1)
        return [.fetchFinal(afterMilliseconds: Self.finalFetchDelayMilliseconds(attempt: 1))]
    }

    /// ⚠️ A RETRACTION IS APPLIED EVEN WHEN ITS `seq` WAS SEEN, OR ITS EPOCH IS CLOSED:
    /// dropping lines twice is harmless, and leaving one on screen is not. The agent's
    /// carries `epoch` and `seq`, which are counted; the website's carries neither and
    /// bypasses the counter.
    private mutating func retracted(_ data: TranscriptRetractedData, now: Int64) -> [TranscriptCommand] {
        var commands: [TranscriptCommand] = []
        if let epoch = data.epoch, let seq = data.seq {
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
    /// only one about a subscribe changes anything: the server echoes the op exactly, so a
    /// refused unsubscribe (or a frame with no op) is not one, and re-subscribing after it
    /// would undo it.
    private mutating func error(_ data: TranscriptErrorData) -> [TranscriptCommand] {
        guard data.op == Self.subscribeOp else { return [] }
        switch data.code {
        case .rateLimited:
            // The refused subscribe will bring no snapshot; this one replaces it.
            return heal(after: data.retryAfterMs ?? Self.rateLimitFallbackMilliseconds)
        case .notLive:
            awaitingSnapshot = false
            // ⚠️ AN ENDED TRANSCRIPT STAYS ENDED: `not_live` also answers a subscribe more
            // than two minutes after the end, which changes nothing about the lines shown.
            // One still reconnecting gives up: no fresh assistant came before the server let
            // the call go (§4.12 Q11), so the screen takes the path after the call.
            if case .ended = phase {
                return []
            }
            phase = .unavailable(data.code)
            return [.unsubscribe]
        case .badRequest, .unsupportedVersion, .forbiddenRole, .tooManySubscriptions, .other:
            awaitingSnapshot = false
            phase = .unavailable(data.code)
            return [.unsubscribe]
        }
    }

    // MARK: - Sequence tracking

    /// Subscribe again for a fresh snapshot. ⛔ Every caller has settled that no other
    /// subscribe is in flight.
    private mutating func heal(after delay: Int64) -> [TranscriptCommand] {
        awaitingSnapshot = true
        return [.resubscribe(afterMilliseconds: delay)]
    }

    /// Whether the frame `(epoch, seq)` is new (rule 1), and the gap check it may start.
    ///
    /// ⚠️ A `seq` BELOW 1 IS NOT ONE THE SERVER SENDS, and an epoch older than the newest
    /// snapshot's is closed: both are dropped.
    private mutating func admit(epoch: Int64, seq: Int, now: Int64) -> (fresh: Bool, commands: [TranscriptCommand]) {
        guard seq >= 1, epoch >= (closedBelow ?? epoch) else { return (false, []) }
        var track = seqs[epoch] ?? SeqTrack(high: unbaselined ? seq - 1 : 0)
        if seq <= track.high {
            guard track.fill(seq) else { return (false, []) }
        } else {
            if seq > track.high + 1 {
                track.missing.append(track.high + 1 ... seq - 1)
            }
            track.high = seq
        }
        seqs[epoch] = track
        newestEpoch = max(newestEpoch ?? epoch, epoch)
        return (true, updateGap(now: now))
    }

    private mutating func updateGap(now: Int64) -> [TranscriptCommand] {
        guard seqs.values.contains(where: { !$0.missing.isEmpty }) else {
            gapOpenedAt = nil
            return []
        }
        guard gapOpenedAt == nil else { return [] }
        gapOpenedAt = now
        return [.checkGap(afterMilliseconds: Self.gapHealMilliseconds)]
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
