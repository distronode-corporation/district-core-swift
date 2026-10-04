import Foundation

// The Voice Studio's per-leg catalogue, its voices and its tuning keys: what a leg editor
// may offer, and over what range.
//
// ⛔ SPLIT OUT OF `VoiceStudioResponse.swift` for SwiftLint's 500-line `file_length` and on
// a real seam: that file is what the Studio SAYS about the engine it holds, this one is what
// it may CHANGE it to. Both are one response.
//
// ⛔ A PICKER LISTS A MODEL WHEN IT IS `offered`, OR WHEN IT IS THE MODEL ALREADY HELD (so a
// stored choice still shows as selected). Chain pickers filter by `forLanguage`, or by
// `forBilingual` while the Studio holds bilingual on. That rule is the web Studio's and it
// lives in `DistrictData`'s `VoiceStudioPickers`, not in a view.

/// The fixed chained engines as chains, and every model each leg may hold.
public struct VoiceStudioCatalog: Codable, Equatable, Sendable {
    /// ⛔ ORDER MATTERS: when a chain equals more than one preset, the first one wins.
    public let presets: [VoiceStudioPreset]
    public let stt: [VoiceStudioSttModel]
    public let turn: VoiceStudioTurnCatalog
    public let llm: [VoiceStudioLlmModel]
    public let tts: [VoiceStudioTtsModel]
    public let realtime: [VoiceStudioRealtimeModel]
}

/// One fixed chained engine, as the chain it runs.
public struct VoiceStudioPreset: Codable, Equatable, Sendable {
    public let modelId: String
    public let engineMix: EngineMix
}

/// One location a model may run in.
public struct VoiceStudioLocation: Codable, Equatable, Sendable {
    /// The wire value (`auto`, `us-east4`, `northamerica-northeast1` ...).
    public let value: String
    public let label: String
    public let residency: VoiceStudioResidency
}

/// One `value`/`label` pair.
public struct VoiceStudioOption: Codable, Equatable, Sendable {
    public let value: String
    public let label: String
}

/// One ear model.
public struct VoiceStudioSttModel: Codable, Equatable, Sendable {
    public let provider: String
    public let providerLabel: String
    public let model: String
    public let label: String
    public let channel: String
    public let channelLabel: String
    /// Vendor readiness.
    public let available: Bool
    /// Shown in the picker to THIS account in THIS region.
    public let offered: Bool
    /// Transcribes the persona language.
    public let forLanguage: Bool
    /// Proven on both English and French: pick from these when bilingual is on.
    public let forBilingual: Bool
    /// The ear decides end of turn itself (Flux).
    public let takesTurns: Bool
    /// Accepts `engineMix.stt.keyterms`.
    public let keyterms: Bool
    public let defaultLocation: String?
    /// Empty for a vendor endpoint.
    public let locations: [VoiceStudioLocation]
    /// At ``defaultLocation``.
    public let residency: VoiceStudioResidency
    public let latency: VoiceStudioLatency?
}

/// The turn detector that runs in the voice agent.
public struct VoiceStudioTurnDetector: Codable, Equatable, Sendable {
    public let label: String
    public let `where`: String
}

/// Flux's own end of turn.
public struct VoiceStudioTurnEar: Codable, Equatable, Sendable {
    public let label: String
}

/// Turn-taking: the detector for every ear but Flux, Flux's own end of turn otherwise.
public struct VoiceStudioTurnCatalog: Codable, Equatable, Sendable {
    public let detector: VoiceStudioTurnDetector
    public let ear: VoiceStudioTurnEar
    /// The region's end-of-turn median, shown on Turn-taking for every ear.
    public let latency: VoiceStudioLatency?
}

/// One brain.
public struct VoiceStudioLlmModel: Codable, Equatable, Sendable {
    public let model: String
    public let label: String
    public let channel: String
    public let channelLabel: String
    public let available: Bool
    public let offered: Bool
    /// `auto` where the region serves the model, else its first location.
    public let defaultLocation: String
    public let locations: [VoiceStudioLocation]
    public let thinking: [VoiceStudioOption]
    public let defaultThinking: String
    /// 0 to 2 for Gemini.
    public let temperatureMin: Double
    public let temperatureMax: Double
    /// At ``defaultLocation`` and ``defaultThinking``.
    public let residency: VoiceStudioResidency
    /// ⚠️ Measured at the region's own location with thinking off, and only there.
    public let latency: VoiceStudioLatency?
}

/// One mouth.
public struct VoiceStudioTtsModel: Codable, Equatable, Sendable {
    public let provider: String
    public let providerLabel: String
    public let model: String
    public let label: String
    public let channel: String
    public let channelLabel: String
    public let available: Bool
    public let offered: Bool
    public let forLanguage: Bool
    public let forBilingual: Bool
    /// The voice a switch to this model starts on, for the persona language.
    public let defaultVoice: String
    public let defaultLocation: String?
    public let locations: [VoiceStudioLocation]
    public let residency: VoiceStudioResidency
    /// At ``defaultVoice``. ⚠️ Deepgram's number is per voice; see ``VoiceStudioVoiceOption/p50``.
    public let latency: VoiceStudioLatency?
}

/// One all-in-one realtime model.
public struct VoiceStudioRealtimeModel: Codable, Equatable, Sendable {
    public let model: String
    public let label: String
    public let channel: String
    public let channelLabel: String
    public let available: Bool
    /// Pickable here.
    public let offered: Bool
    /// ⛔ Refused in this region (`gemini-3.8-live` in `eu`): a save naming it answers 400
    /// `model_unavailable_in_region`.
    public let refusedInRegion: Bool
    public let note: String?
    public let residency: VoiceStudioResidency
    public let latency: VoiceStudioLatency?
}

/// One voice.
public struct VoiceStudioVoiceOption: Codable, Equatable, Sendable {
    /// The voice id a save sends.
    public let value: String
    /// Localized ("Asteria (US English - Feminine)").
    public let label: String
    /// A SITE-RELATIVE path of a pre-rendered sample; prefix the service origin.
    public let clip: String?
    /// Measured time to first audio for this voice in this region, ms.
    public let p50: Double?
}

/// One heading of voices.
public struct VoiceStudioVoiceGroup: Codable, Equatable, Sendable {
    /// Localized; `""` means no heading (Gemini Live's flat list).
    public let label: String
    public let options: [VoiceStudioVoiceOption]
}

/// One mouth's voices, or one realtime model's.
public struct VoiceStudioVoiceList: Codable, Equatable, Sendable {
    /// `tts` or `realtime`.
    public let kind: String
    /// `""` for realtime.
    public let provider: String
    public let model: String
    public let groups: [VoiceStudioVoiceGroup]
}

/// A model that honours a tuning key, with that model's own range.
public struct VoiceStudioHonouredBy: Codable, Equatable, Sendable {
    public let provider: String
    public let model: String
    public let min: Double?
    public let max: Double?
    public let `default`: Double?
    public let useDefaultLabel: String?
}

/// One tuning control.
///
/// ⛔ ``key`` IS A PATH INTO THE PERSONA PATCH, NOT A LABEL. A key this client cannot map is
/// not drawn: a control that wrote to a path nobody mapped would save nothing and say it had.
public struct VoiceStudioTuningKey: Codable, Equatable, Sendable {
    public let key: String
    /// `stt`, `turn`, `llm`, `tts` or `realtime`.
    public let leg: String
    /// `main` (on the leg editor) or `advanced` (behind the Advanced section).
    public let section: String
    /// `slider`, `select`, `checkbox` or `lines`.
    public let control: String
    public let label: String
    public let description: String?
    public let min: Double?
    public let max: Double?
    public let step: Double?
    /// Where the slider starts when first set.
    public let start: Double?
    /// The value in force while unset; null is the model's own.
    public let `default`: Double?
    /// The "Use the default (0.30)" checkbox label for a nullable key.
    public let useDefaultLabel: String?
    /// Nil (or absent) on the wire means the default.
    public let nullable: Bool
    public let options: [VoiceStudioOption]?
    public let maxCount: Int?
    public let maxLength: Int?
    /// Nil: every engine of that leg.
    public let honouredBy: [VoiceStudioHonouredBy]?
}
