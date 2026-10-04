import DistrictModel
import Foundation

/// The engine the Voice Studio holds: a chain of legs, or one realtime model.
///
/// ⚠️ EQUATABLE ON PURPOSE: "is this the engine the saved persona (or a recipe) runs" is
/// equality, and ``VoiceStudioReadout`` uses exactly that to show the service's own words and
/// numbers whenever it has described the held engine.
public enum VoiceStudioEngine: Equatable, Hashable, Sendable {
    case chained(EngineMix)
    case realtime(modelId: String, voice: String)

    /// A resolved chain as the Studio holds it.
    ///
    /// ⚠️ ONE TEST, NOT A `kind` SWITCH. The service sets `engineMix` exactly when `kind` is
    /// `chained` (the contract tests pin it), so "has a mix" is the same question with no
    /// third arm to leave unreachable.
    public init(chain: VoiceStudioChain) {
        if let mix = chain.engineMix {
            self = .chained(mix)
        } else {
            self = .realtime(modelId: chain.realtimeModelId ?? "", voice: chain.voice)
        }
    }

    /// The voice the caller hears, whichever kind this is.
    public var voice: String {
        switch self {
        case let .chained(mix): mix.tts.voice
        case let .realtime(_, voice): voice
        }
    }

    /// The chain's mix, or nil for a realtime engine.
    public var mix: EngineMix? {
        guard case let .chained(mix) = self else { return nil }
        return mix
    }

    /// The realtime model's id, or `""` for a chain.
    public var realtimeModelId: String {
        guard case let .realtime(modelId, _) = self else { return "" }
        return modelId
    }

    /// The same engine speaking with another voice.
    public func withVoice(_ voice: String) -> VoiceStudioEngine {
        switch self {
        case var .chained(mix):
            mix.tts.voice = voice
            return .chained(mix)
        case let .realtime(modelId, _):
            return .realtime(modelId: modelId, voice: voice)
        }
    }
}

/// Everything a Studio save is computed from (the web Studio's `StudioState`).
///
/// ⛔ TWO TEMPERATURES EXIST AND THEY ARE DIFFERENT KEYS. ``realtimeTemperature`` is
/// `aiPersona.temperature`, the REALTIME model's, 0 to 1; a chain's brain temperature lives in
/// its mix (`engineMix.llm.temperature`, 0 to 2). Sending one for the other is ignored with a
/// 200, so the re-read would report the save as failed.
public struct VoiceStudioState: Equatable, Sendable {
    public var engine: VoiceStudioEngine
    public var realtimeTemperature: Double
    /// English and French on one call.
    public var bilingual: Bool
    /// Gemini 2.5 Live's voice style; nil until chosen.
    public var voiceStyle: String?

    public init(engine: VoiceStudioEngine, realtimeTemperature: Double, bilingual: Bool, voiceStyle: String?) {
        self.engine = engine
        self.realtimeTemperature = realtimeTemperature
        self.bilingual = bilingual
        self.voiceStyle = voiceStyle
    }

    /// The state the Studio opens on: the persona as saved, as the service describes it.
    public init(current: VoiceStudioCurrent) {
        self.init(
            engine: VoiceStudioEngine(chain: current.chain),
            realtimeTemperature: current.temperature,
            bilingual: current.bilingual,
            voiceStyle: current.voiceStyle
        )
    }
}
