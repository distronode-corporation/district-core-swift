import DistrictModel
import Foundation

/// Every tuning key this package can read and write, by its PATCH path.
///
/// ⛔ A KEY THE SERVICE PUBLISHES AND THIS TABLE DOES NOT NAME IS SIMPLY NOT DRAWN. A control
/// that wrote nowhere would report a save that changed nothing.
///
/// ⛔ A MIX PATH IS NEVER DRAWN ON A REALTIME ENGINE, NOR A PERSONA KEY ON A CHAIN, whatever leg
/// the service files it under: a chain control on a realtime engine would have no mix to write.
public enum VoiceStudioTuningPath {
    /// `engineMix.stt.keyterms`, one term per line.
    public static let keyterms = "engineMix.stt.keyterms"
    /// `engineMix.preemptiveTts`, "Start speaking sooner".
    public static let preemptiveTts = "engineMix.preemptiveTts"
    /// The REALTIME model's temperature, 0 to 1, a top-level persona key.
    public static let realtimeTemperature = "temperature"
    /// Gemini 2.5 Live's voice style, a top-level persona key.
    public static let voiceStyle = "voiceStyle"

    /// The keys of a chain: paths inside its mix.
    public static let chainPaths: Set<String> = Set(VoiceStudioNumberPath.allCases.map(\.rawValue))
        .union(VoiceStudioChoicePath.allCases.map(\.rawValue))
        .union([keyterms, preemptiveTts])

    /// The keys of a realtime engine.
    public static let realtimePaths: Set<String> = [realtimeTemperature, voiceStyle]

    /// The keys a control may be drawn for on an engine.
    public static func paths(for engine: VoiceStudioEngine) -> Set<String> {
        engine.mix == nil ? realtimePaths : chainPaths
    }
}

/// A number inside a mix.
///
/// ⚠️ NIL IS "USE THE DEFAULT" FOR EVERY ONE OF THESE. The absent-when-unset keys
/// (`eagerEotThreshold`, `eotTimeoutMs`, `stability`, `expressivity`) become absent again; the
/// always-present ones (`minDelay`, `maxDelay`, `eotThreshold`, `llm.temperature`, `speed`) are
/// written as `null`, which the service reads the same way.
public enum VoiceStudioNumberPath: String, CaseIterable, Sendable {
    case minDelay = "engineMix.turn.minDelay"
    case maxDelay = "engineMix.turn.maxDelay"
    case eotThreshold = "engineMix.turn.eotThreshold"
    case eagerEotThreshold = "engineMix.turn.eagerEotThreshold"
    case eotTimeoutMs = "engineMix.turn.eotTimeoutMs"
    case interruptionMinDuration = "engineMix.turn.interruption.minDuration"
    case interruptionMinWords = "engineMix.turn.interruption.minWords"
    case interruptionFalseTimeout = "engineMix.turn.interruption.falseTimeout"
    case llmTemperature = "engineMix.llm.temperature"
    case ttsSpeed = "engineMix.tts.speed"
    case ttsStability = "engineMix.tts.stability"
    case ttsExpressivity = "engineMix.tts.expressivity"

    public func value(in mix: EngineMix) -> Double? {
        switch self {
        case .minDelay: mix.turn.minDelay
        case .maxDelay: mix.turn.maxDelay
        case .eotThreshold: mix.turn.eotThreshold
        case .eagerEotThreshold: mix.turn.eagerEotThreshold
        case .eotTimeoutMs: mix.turn.eotTimeoutMs
        case .interruptionMinDuration: mix.turn.interruption?.minDuration
        case .interruptionMinWords: mix.turn.interruption?.minWords
        case .interruptionFalseTimeout: mix.turn.interruption?.falseTimeout
        case .llmTemperature: mix.llm.temperature
        case .ttsSpeed: mix.tts.speed
        case .ttsStability: mix.tts.stability
        case .ttsExpressivity: mix.tts.expressivity
        }
    }

    public func setting(_ value: Double?, in mix: EngineMix) -> EngineMix {
        var next = mix
        switch self {
        case .minDelay: next.turn.minDelay = value
        case .maxDelay: next.turn.maxDelay = value
        case .eotThreshold: next.turn.eotThreshold = value
        case .eagerEotThreshold: next.turn.eagerEotThreshold = value
        case .eotTimeoutMs: next.turn.eotTimeoutMs = value
        case .interruptionMinDuration: next.turn.interruption = Self.interruption(mix) { $0.minDuration = value }
        case .interruptionMinWords: next.turn.interruption = Self.interruption(mix) { $0.minWords = value }
        case .interruptionFalseTimeout: next.turn.interruption = Self.interruption(mix) { $0.falseTimeout = value }
        case .llmTemperature: next.llm.temperature = value
        case .ttsSpeed: next.tts.speed = value
        case .ttsStability: next.tts.stability = value
        case .ttsExpressivity: next.tts.expressivity = value
        }
        return next
    }

    /// `turn.interruption` with one field changed.
    ///
    /// ⚠️ ALL FOUR NIL IS NO OBJECT AT ALL, as the service stores it: an empty object would read
    /// back as absent and the save as failed.
    static func interruption(
        _ mix: EngineMix,
        _ edit: (inout EngineMixInterruption) -> Void
    ) -> EngineMixInterruption? {
        var next = mix.turn.interruption ?? EngineMixInterruption()
        edit(&next)
        return next.isEmpty ? nil : next
    }
}

/// A choice inside a mix, as a select's value.
public enum VoiceStudioChoicePath: String, CaseIterable, Sendable {
    /// `auto` is the ABSENT key; `dynamic` and `fixed` are written.
    case turnMode = "engineMix.turn.mode"
    /// `default` is null, `on` true, `off` false.
    case interruptionResume = "engineMix.turn.interruption.resume"
    /// One of the held brain's `catalog.llm[].thinking` values.
    case llmThinking = "engineMix.llm.thinking"

    static let modeAuto = "auto"
    static let resumeDefault = "default"
    static let resumeOn = "on"
    static let resumeOff = "off"

    public func value(in mix: EngineMix) -> String {
        switch self {
        case .turnMode:
            return mix.turn.mode ?? Self.modeAuto
        case .interruptionResume:
            guard let resume = mix.turn.interruption?.resume else { return Self.resumeDefault }
            return resume ? Self.resumeOn : Self.resumeOff
        case .llmThinking:
            return mix.llm.thinking
        }
    }

    public func setting(_ value: String, in mix: EngineMix) -> EngineMix {
        var next = mix
        switch self {
        case .turnMode:
            next.turn.mode = value == Self.modeAuto ? nil : value
        case .interruptionResume:
            let resume: Bool? = value == Self.resumeDefault ? nil : value == Self.resumeOn
            next.turn.interruption = VoiceStudioNumberPath.interruption(mix) { $0.resume = resume }
        case .llmThinking:
            next.llm.thinking = value
        }
        return next
    }
}
