import Foundation

// The live call transcript on the telemetry socket (`transcript` v1).
//
// ⛔ OPT-IN, PER CALL, PER CONNECTION. The five `transcript_*` events reach only a socket
// that sent a `transcript.subscribe` for that call (``TranscriptClientOp``), and a
// subscription lasts as long as the connection: after any reconnect or renewal it is sent
// again. The envelope is the ordinary ``TelemetryEnvelope``; everything new lives in its
// `data`, which ``TelemetryEnvelope/transcriptEvent`` reads into the types below.
//
// ⛔ CUSTOMER DATA. A segment's `text` is what a caller said. Every type here that can hold
// one leaves the text out of `description`, `debugDescription` and the mirror (it prints
// the length), so a log line, an interpolation or an `XCTAssert` message never carries it.
//
// ⚠️ UNKNOWN `data` KEYS ARE IGNORED, as everywhere in this module: the server may add an
// optional field without bumping `v`. A breaking change is `v: 2`, which the server sends
// only to a socket that subscribed with `v: 2`, so a frame whose `v` is not 1 is not read.

/// One utterance of a live transcript, as `transcript_segment` and `transcript_snapshot`
/// carry it.
///
/// ⚠️ A SEGMENT IS REVISED IN PLACE. ``segmentId`` stays the same from the first interim
/// hypothesis to the final, ``rev`` grows with each revision, and a ``final`` segment is
/// frozen. Order on screen is (``epoch``, ``index``); ``seq`` is for dedupe and gap
/// detection only. See `DistrictLive.TranscriptReducer` for the rules.
public struct TranscriptSegment: Codable, Sendable, Equatable {
    /// Stable id of the utterance, unique within the call (at most 64 characters).
    public let segmentId: String
    /// Display order within ``epoch``, assigned when the segment opens. Never reused.
    public let index: Int
    /// The assistant session that produced the segment, as its start time in epoch
    /// milliseconds. A re-dispatched assistant for the same call starts a new epoch.
    public let epoch: Int64
    /// The message counter of (call, ``epoch``) at this update, 1 or more.
    public let seq: Int
    /// The revision of this segment, 0 or more.
    public let rev: Int
    public let speaker: TranscriptSpeaker
    /// The persona's name for an `agent` line; always nil for a `caller` line.
    public let speakerName: String?
    /// What was said: 1 to 2000 UTF-16 units. ⛔ Never log it; see the file note.
    public let text: String
    /// `false`: an interim hypothesis that will be replaced. `true`: frozen.
    public let final: Bool
    /// For an `agent` final: the speech was cut off, and ``text`` is what was played.
    public let interrupted: Bool
    /// A BCP-47 primary subtag (`en`, `fr`) when known.
    public let language: String?
    /// When the segment started, an ISO 8601 instant.
    public let startedAt: String
    /// When it ended; nil while interim.
    public let endedAt: String?

    public init(
        segmentId: String,
        index: Int,
        epoch: Int64,
        seq: Int,
        rev: Int,
        speaker: TranscriptSpeaker,
        speakerName: String?,
        text: String,
        final: Bool,
        interrupted: Bool,
        language: String?,
        startedAt: String,
        endedAt: String?
    ) {
        self.segmentId = segmentId
        self.index = index
        self.epoch = epoch
        self.seq = seq
        self.rev = rev
        self.speaker = speaker
        self.speakerName = speakerName
        self.text = text
        self.final = final
        self.interrupted = interrupted
        self.language = language
        self.startedAt = startedAt
        self.endedAt = endedAt
    }

    private enum CodingKeys: String, CodingKey {
        case segmentId, index, epoch, seq, rev, speaker, speakerName, text, final, interrupted, language
        case startedAt, endedAt
    }

    /// ⚠️ WRITTEN BY HAND SO THE THREE NULLABLE KEYS ARE ENCODED AS AN EXPLICIT `null`, the
    /// way the server sends them, rather than dropped the way synthesised `Encodable` drops
    /// a nil Optional. The contract gate compares re-encoded keys with the fixture's.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(segmentId, forKey: .segmentId)
        try container.encode(index, forKey: .index)
        try container.encode(epoch, forKey: .epoch)
        try container.encode(seq, forKey: .seq)
        try container.encode(rev, forKey: .rev)
        try container.encode(speaker, forKey: .speaker)
        try container.encode(speakerName, forKey: .speakerName)
        try container.encode(text, forKey: .text)
        try container.encode(final, forKey: .final)
        try container.encode(interrupted, forKey: .interrupted)
        try container.encode(language, forKey: .language)
        try container.encode(startedAt, forKey: .startedAt)
        try container.encode(endedAt, forKey: .endedAt)
    }
}

extension TranscriptSegment: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var description: String {
        "TranscriptSegment(segmentId: \(segmentId), epoch: \(epoch), index: \(index), seq: \(seq), rev: \(rev), "
            + "speaker: \(speaker.wire), text: <\(text.utf16.count) units>, final: \(final))"
    }

    public var debugDescription: String {
        description
    }

    /// ⚠️ THE MIRROR TOO, because `dump(_:)` and XCTest's failure messages walk the mirror
    /// rather than calling `description`.
    public var customMirror: Mirror {
        Mirror(self, children: [
            "segmentId": segmentId,
            "index": index,
            "epoch": epoch,
            "seq": seq,
            "rev": rev,
            "speaker": speaker.wire,
            "text": "<\(text.utf16.count) units>",
            "final": final,
        ])
    }
}

/// `transcript_segment`'s data: one new or updated segment.
public struct TranscriptSegmentData: Codable, Sendable, Equatable {
    /// The `transcript` payload version (`v` on the wire).
    public let version: Int
    public let callId: String
    public let segment: TranscriptSegment

    public init(version: Int, callId: String, segment: TranscriptSegment) {
        self.version = version
        self.callId = callId
        self.segment = segment
    }

    private enum CodingKeys: String, CodingKey {
        case version = "v"
        case callId, segment
    }
}

/// `transcript_snapshot`'s data: the transcript so far, in reply to a subscribe, in one or
/// more parts.
///
/// ⚠️ A CLIENT REPLACES ITS STATE FOR THE CALL WITH THE UNION OF THE PARTS once the part
/// with ``more`` false has arrived, and not before.
public struct TranscriptSnapshotData: Codable, Sendable, Equatable {
    /// The `transcript` payload version (`v` on the wire).
    public let version: Int
    public let callId: String
    /// False once the transcript has ended (a `transcript_ended` is buffered).
    public let live: Bool
    /// False when the server's memory does not reach back to the call's first line (it
    /// started, or evicted lines, after the call began). The earlier lines appear in the
    /// full transcript after the call, and a client says so.
    public let complete: Bool
    /// The epoch ``lastSeq`` belongs to; nil before the first line.
    public let epoch: Int64?
    /// The highest `seq` this snapshot includes; nil before the first line.
    public let lastSeq: Int?
    /// The latest revision of each segment, in (epoch, index) order.
    public let segments: [TranscriptSegment]
    /// This part's number, from 0.
    public let part: Int
    /// True until the last part.
    public let more: Bool

    public init(
        version: Int,
        callId: String,
        live: Bool,
        complete: Bool,
        epoch: Int64?,
        lastSeq: Int?,
        segments: [TranscriptSegment],
        part: Int,
        more: Bool
    ) {
        self.version = version
        self.callId = callId
        self.live = live
        self.complete = complete
        self.epoch = epoch
        self.lastSeq = lastSeq
        self.segments = segments
        self.part = part
        self.more = more
    }

    private enum CodingKeys: String, CodingKey {
        case version = "v"
        case callId, live, complete, epoch, lastSeq, segments, part, more
    }

    /// ⚠️ BY HAND, for the explicit nulls; see ``TranscriptSegment/encode(to:)``.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(callId, forKey: .callId)
        try container.encode(live, forKey: .live)
        try container.encode(complete, forKey: .complete)
        try container.encode(epoch, forKey: .epoch)
        try container.encode(lastSeq, forKey: .lastSeq)
        try container.encode(segments, forKey: .segments)
        try container.encode(part, forKey: .part)
        try container.encode(more, forKey: .more)
    }
}

/// `transcript_ended`'s data: the assistant stopped transcribing the call, and no segment
/// follows in this epoch.
public struct TranscriptEndedData: Codable, Sendable, Equatable {
    /// The `transcript` payload version (`v` on the wire).
    public let version: Int
    public let callId: String
    public let epoch: Int64
    public let seq: Int
    /// The last segment index of the epoch; nil when nothing was said.
    public let lastIndex: Int?
    public let reason: TranscriptEndReason

    public init(version: Int, callId: String, epoch: Int64, seq: Int, lastIndex: Int?, reason: TranscriptEndReason) {
        self.version = version
        self.callId = callId
        self.epoch = epoch
        self.seq = seq
        self.lastIndex = lastIndex
        self.reason = reason
    }

    private enum CodingKeys: String, CodingKey {
        case version = "v"
        case callId, epoch, seq, lastIndex, reason
    }

    /// ⚠️ BY HAND, for the explicit null; see ``TranscriptSegment/encode(to:)``.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(callId, forKey: .callId)
        try container.encode(epoch, forKey: .epoch)
        try container.encode(seq, forKey: .seq)
        try container.encode(lastIndex, forKey: .lastIndex)
        try container.encode(reason, forKey: .reason)
    }
}

/// `transcript_retracted`'s data: lines that must come off every screen.
///
/// ⚠️ ``seq`` IS NIL WHEN THE WEBSITE RETRACTS (a contact erase) and set when the
/// assistant does. ``epoch`` is NOT IN THE v1 CONTRACT: a `seq` is counted per (call,
/// epoch), so it is read here when the server sends one and is otherwise nil. See
/// `DistrictLive.TranscriptReducer` for what a nil epoch means.
public struct TranscriptRetractedData: Codable, Sendable, Equatable {
    /// The `transcript` payload version (`v` on the wire).
    public let version: Int
    public let callId: String
    /// True: drop every line of the call.
    public let all: Bool
    /// The segments to drop when ``all`` is false.
    public let segmentIds: [String]
    public let reason: TranscriptRetractReason
    public let seq: Int?
    public let epoch: Int64?

    public init(
        version: Int,
        callId: String,
        all: Bool,
        segmentIds: [String],
        reason: TranscriptRetractReason,
        seq: Int?,
        epoch: Int64? = nil
    ) {
        self.version = version
        self.callId = callId
        self.all = all
        self.segmentIds = segmentIds
        self.reason = reason
        self.seq = seq
        self.epoch = epoch
    }

    private enum CodingKeys: String, CodingKey {
        case version = "v"
        case callId, all, segmentIds, reason, seq, epoch
    }

    /// ⚠️ BY HAND: ``seq`` as an explicit null, the way the website sends it, and ``epoch``
    /// only when it was sent, since the v1 contract has no such key.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(callId, forKey: .callId)
        try container.encode(all, forKey: .all)
        try container.encode(segmentIds, forKey: .segmentIds)
        try container.encode(reason, forKey: .reason)
        try container.encode(seq, forKey: .seq)
        try container.encodeIfPresent(epoch, forKey: .epoch)
    }
}

/// `transcript_error`'s data: an op could not be honoured. The socket stays open.
public struct TranscriptErrorData: Codable, Sendable, Equatable {
    /// The `transcript` payload version (`v` on the wire).
    public let version: Int
    /// The call the op named; nil for an op that names none (or that did not parse).
    public let callId: String?
    /// The op that failed, as sent; nil when it did not parse.
    public let op: String?
    public let code: TranscriptErrorCode
    /// How long to wait before trying again; set with ``TranscriptErrorCode/rateLimited``.
    public let retryAfterMs: Int64?

    public init(version: Int, callId: String?, op: String?, code: TranscriptErrorCode, retryAfterMs: Int64?) {
        self.version = version
        self.callId = callId
        self.op = op
        self.code = code
        self.retryAfterMs = retryAfterMs
    }

    private enum CodingKeys: String, CodingKey {
        case version = "v"
        case callId, op, code, retryAfterMs
    }

    /// ⚠️ BY HAND, for the explicit nulls; see ``TranscriptSegment/encode(to:)``.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(callId, forKey: .callId)
        try container.encode(op, forKey: .op)
        try container.encode(code, forKey: .code)
        try container.encode(retryAfterMs, forKey: .retryAfterMs)
    }
}

/// A `transcript_*` event, read.
public enum TranscriptEvent: Sendable, Equatable {
    case snapshot(TranscriptSnapshotData)
    case segment(TranscriptSegmentData)
    case ended(TranscriptEndedData)
    case retracted(TranscriptRetractedData)
    case error(TranscriptErrorData)

    /// The `transcript` payload version the event was sent as.
    public var version: Int {
        switch self {
        case let .snapshot(data): data.version
        case let .segment(data): data.version
        case let .ended(data): data.version
        case let .retracted(data): data.version
        case let .error(data): data.version
        }
    }

    /// The call the event is about, from its data; nil for an error that names none.
    public var callId: String? {
        switch self {
        case let .snapshot(data): data.callId
        case let .segment(data): data.callId
        case let .ended(data): data.callId
        case let .retracted(data): data.callId
        case let .error(data): data.callId
        }
    }
}

extension TelemetryEnvelope {
    /// This event's `data` as a transcript event, or nil when it is not one this client
    /// can read.
    ///
    /// nil for: an event type other than the five `transcript_*` names; data that does not
    /// decode; a `v` other than ``TranscriptClientOp/version``; and data whose `callId`
    /// disagrees with the envelope's. ⚠️ An error that names no call (`callId: null`) is
    /// read whatever the envelope's `callId` says, since there is nothing to compare.
    public var transcriptEvent: TranscriptEvent? {
        let event: TranscriptEvent? = switch eventType {
        case .transcriptSnapshot:
            decodeData(TranscriptSnapshotData.self).map(TranscriptEvent.snapshot)
        case .transcriptSegment:
            decodeData(TranscriptSegmentData.self).map(TranscriptEvent.segment)
        case .transcriptEnded:
            decodeData(TranscriptEndedData.self).map(TranscriptEvent.ended)
        case .transcriptRetracted:
            decodeData(TranscriptRetractedData.self).map(TranscriptEvent.retracted)
        case .transcriptError:
            decodeData(TranscriptErrorData.self).map(TranscriptEvent.error)
        case .callStarted, .callUpdated, .callEnded, .callRinging, .toolOutcome, .messageReceived, .messageSent,
             .unknown:
            nil
        }
        guard let event, event.version == TranscriptClientOp.version else { return nil }
        guard let named = event.callId else { return event }
        return named == callId ? event : nil
    }

    /// ⚠️ THROUGH JSON AND BACK, because ``data`` is carried as ``WireJSON``. Lossless for
    /// these shapes: ``WireJSON`` keeps an integer an integer.
    private func decodeData<Value: Decodable>(_: Value.Type) -> Value? {
        guard let bytes = try? JSONEncoder().encode(data) else { return nil }
        return try? JSONDecoder().decode(Value.self, from: bytes)
    }
}
