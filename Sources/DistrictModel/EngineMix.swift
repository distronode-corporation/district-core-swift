import Foundation

/// `aiPersona.engineMix` version 1, exactly as the service's engine catalogue defines it:
/// a voice chain of an ear, a brain, a mouth and the turn-taking between them.
///
/// ⛔ TWO KINDS OF OPTIONAL LIVE HERE AND THEY ARE NOT THE SAME FACT ON THE WIRE.
/// Most nullable keys are ALWAYS PRESENT and carry `null` when unset (`stt.language`,
/// `llm.temperature`, `tts.speed`, `turn.minDelay` ...). A handful are ABSENT when unset
/// and never `null` (`stt.keyterms`, `tts.stability`, `tts.expressivity`, `turn.mode`,
/// `turn.eagerEotThreshold`, `turn.eotTimeoutMs`, `turn.interruption`,
/// `userAwayTimeout`). Both decode to nil here, which is why every one of them is an
/// Optional: a non-optional property for an absent-when-unset key fails to decode the
/// first stored mix that never set it.
///
/// ⚠️ ON THE WAY OUT THE DIFFERENCE IS RESTORED by the persona save's body builder in
/// `DistrictNetwork`, which writes `null` for the always-present keys and leaves the
/// others out, the exact shape the web Studio sends. The synthesized `Encodable` here
/// omits every nil, which is what the contract gate's re-encode expects.
///
/// ⚠️ `var` PROPERTIES ON PURPOSE. A leg editor changes one field at a time
/// (`mix.stt.model = ...`) and a value type with mutable fields is the plain Swift spelling
/// of that; there is no shared reference to corrupt.
public struct EngineMix: Codable, Equatable, Hashable, Sendable {
    /// `v` on the wire, always 1. The save refuses any other version with
    /// `invalid_engine_mix`. ⚠️ Renamed here only because SwiftLint's `identifier_name`
    /// floor is two characters.
    public var version: Int
    public var stt: EngineMixStt
    public var llm: EngineMixLlm
    public var tts: EngineMixTts
    public var turn: EngineMixTurn
    /// Speak sooner: start synthesising before the brain has finished its sentence.
    public var preemptiveTts: Bool
    /// ⚠️ Absent when unset. No Studio control writes it; it is carried so a save does not
    /// drop a value the web set.
    public var userAwayTimeout: Double?

    enum CodingKeys: String, CodingKey {
        case version = "v"
        case stt
        case llm
        case tts
        case turn
        case preemptiveTts
        case userAwayTimeout
    }

    public init(
        version: Int = 1,
        stt: EngineMixStt,
        llm: EngineMixLlm,
        tts: EngineMixTts,
        turn: EngineMixTurn,
        preemptiveTts: Bool,
        userAwayTimeout: Double? = nil
    ) {
        self.version = version
        self.stt = stt
        self.llm = llm
        self.tts = tts
        self.turn = turn
        self.preemptiveTts = preemptiveTts
        self.userAwayTimeout = userAwayTimeout
    }
}

/// The ear: speech recognition.
public struct EngineMixStt: Codable, Equatable, Hashable, Sendable {
    public var provider: String
    public var model: String
    /// Always present, null when the ear follows the persona language.
    public var language: String?
    /// Always present, null for a vendor endpoint with no location choice.
    public var location: String?
    /// ⚠️ Absent when unset. Accepted only by an ear whose catalogue entry says `keyterms`.
    public var keyterms: [String]?

    public init(
        provider: String,
        model: String,
        language: String? = nil,
        location: String? = nil,
        keyterms: [String]? = nil
    ) {
        self.provider = provider
        self.model = model
        self.language = language
        self.location = location
        self.keyterms = keyterms
    }
}

/// The brain.
public struct EngineMixLlm: Codable, Equatable, Hashable, Sendable {
    public var model: String
    /// `auto` (the workspace region's own) or a Vertex location.
    public var location: String
    public var thinking: String
    /// ⛔ THE CHAIN'S TEMPERATURE, 0 TO 2, AND NOT `aiPersona.temperature`. That top-level key
    /// is the REALTIME model's, 0 to 1, and is ignored with a 200 when a chain is held.
    /// Null is the model's own default.
    public var temperature: Double?

    public init(model: String, location: String, thinking: String, temperature: Double? = nil) {
        self.model = model
        self.location = location
        self.thinking = thinking
        self.temperature = temperature
    }
}

/// The mouth: speech synthesis.
public struct EngineMixTts: Codable, Equatable, Hashable, Sendable {
    public var provider: String
    public var model: String
    public var voice: String
    /// Always present, null for the model's own speed.
    public var speed: Double?
    public var location: String?
    /// ⚠️ Absent when unset (ElevenLabs only).
    public var stability: Double?
    /// ⚠️ Absent when unset (ElevenLabs stream-input only).
    public var expressivity: Double?

    public init(
        provider: String,
        model: String,
        voice: String,
        speed: Double? = nil,
        location: String? = nil,
        stability: Double? = nil,
        expressivity: Double? = nil
    ) {
        self.provider = provider
        self.model = model
        self.voice = voice
        self.speed = speed
        self.location = location
        self.stability = stability
        self.expressivity = expressivity
    }
}

/// When to reply, and when to stop for an interruption.
public struct EngineMixTurn: Codable, Equatable, Hashable, Sendable {
    public var minDelay: Double?
    public var maxDelay: Double?
    public var eotThreshold: Double?
    /// ⚠️ Absent for automatic; `dynamic` or `fixed` otherwise.
    public var mode: String?
    /// ⚠️ Absent when unset (Flux ears).
    public var eagerEotThreshold: Double?
    /// ⚠️ Absent when unset (Flux ears).
    public var eotTimeoutMs: Double?
    /// ⚠️ Absent when no interruption setting is held. ⛔ AN OBJECT OF FOUR NULLS IS NOT A
    /// THING THE SERVER STORES: it reads back as absent, so a client that kept one would
    /// report its own save as failed.
    public var interruption: EngineMixInterruption?

    public init(
        minDelay: Double? = nil,
        maxDelay: Double? = nil,
        eotThreshold: Double? = nil,
        mode: String? = nil,
        eagerEotThreshold: Double? = nil,
        eotTimeoutMs: Double? = nil,
        interruption: EngineMixInterruption? = nil
    ) {
        self.minDelay = minDelay
        self.maxDelay = maxDelay
        self.eotThreshold = eotThreshold
        self.mode = mode
        self.eagerEotThreshold = eagerEotThreshold
        self.eotTimeoutMs = eotTimeoutMs
        self.interruption = interruption
    }
}

/// Four nullable interruption settings.
public struct EngineMixInterruption: Codable, Equatable, Hashable, Sendable {
    public var minDuration: Double?
    /// Whole words; the server rounds.
    public var minWords: Double?
    /// Null is the default, `true` on, `false` off.
    public var resume: Bool?
    public var falseTimeout: Double?

    public init(
        minDuration: Double? = nil,
        minWords: Double? = nil,
        resume: Bool? = nil,
        falseTimeout: Double? = nil
    ) {
        self.minDuration = minDuration
        self.minWords = minWords
        self.resume = resume
        self.falseTimeout = falseTimeout
    }

    /// ⚠️ All four unset, which the server stores as no object at all.
    public var isEmpty: Bool {
        minDuration == nil && minWords == nil && resume == nil && falseTimeout == nil
    }
}
