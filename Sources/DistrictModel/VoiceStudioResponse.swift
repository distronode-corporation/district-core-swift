import Foundation

/// `GET /api/district/workspace/persona/voice-studio?workspaceId=`: everything the native
/// Voice Studio draws, and everything it needs to build a save, in one read.
///
/// ⛔ EVERY LABEL ARRIVES LOCALIZED AND IS RENDERED VERBATIM. The service answers in the
/// reader's PORTAL locale (``locale``), the documented exception to "the native apps are
/// English": a French-preference member sees French Studio labels even where the app's own
/// chrome is English. Nothing in this package translates, shortens or rebuilds one of them.
/// Wire VALUES (ids, keys, channels, stages, leg names) never localize.
///
/// ⛔ EVERY OBJECT OF ONE KIND CARRIES THE SAME KEYS, AND A VALUE THAT DOES NOT APPLY IS
/// `null`, NEVER ABSENT. So every Optional below is an always-present key that may be null,
/// with one family of exceptions: the absent-when-unset keys of ``EngineMix``.
///
/// ⛔ NO NUMBER HERE IS A CONSTANT. The contract fixture's latencies come from the service's
/// TEST latency table; a value copied out of it into Swift would be a figure nobody measured.
///
/// ⚠️ KEYED ON THE WORKSPACE'S REGION (``region``). Every residency sentence is a claim about
/// one workspace, so one workspace's answer is never cached and shown for another.
public struct VoiceStudioResponse: Codable, Equatable, Sendable {
    public let success: Bool
    /// `us`, `ca`, `eu` or `apac`: the WORKSPACE's region.
    public let region: String
    /// `en` or `fr`: the language the labels are in.
    public let locale: String
    /// The persona language, `en-US` when unset.
    public let language: String
    /// Whether Preview-channel models are offered here (false in `eu`).
    public let previewAllowed: Bool
    public let labels: VoiceStudioLabels
    public let current: VoiceStudioCurrent
    /// The CURRENT engine's time-to-first-word meter, plus what a client needs to recompute
    /// one after an edit.
    public let latency: VoiceStudioCurrentMeter
    /// Tile order: in-region, fastest, natural, bilingual, realtime, custom.
    public let recipeIds: [String]
    /// Both tiers, stable first. ⚠️ A recipe that cannot be honoured here is simply absent.
    public let recipes: [VoiceStudioRecipe]
    public let catalog: VoiceStudioCatalog
    public let voices: [VoiceStudioVoiceList]
    public let advanced: [VoiceStudioTuningKey]
}

/// The Studio's own copy, in the portal locale.
public struct VoiceStudioLabels: Codable, Equatable, Sendable {
    public let heading: String
    public let description: String
    public let tierLabel: String
    public let tierStable: String
    public let tierLatest: String
    public let tierDescription: String
    public let recipesLabel: String
    public let defaultBadge: String
    public let reset: String
    public let chainLabel: String
    public let editLeg: String
    public let edit: String
    public let meterHeading: String
    public let meterDescription: String
    public let residencyHeading: String
    /// This region's "Every part of this call stays in ..." sentence.
    public let allInRegion: String
    public let leavesRegion: String
    public let providerLabel: String
    public let modelLabel: String
    public let locationLabel: String
    public let voiceLabel: String
    public let voicePlaceholder: String
    public let listen: String
    public let stopListening: String
    public let advanced: String
    public let interruptions: String
    public let notMeasured: String
    public let previewNote: String
    public let save: String
    public let saved: String
    public let saveFailed: String
    public let unsaved: String
    public let allSaved: String
    public let legs: VoiceStudioLegLabels
    public let stages: VoiceStudioStageLabels
    public let channels: VoiceStudioChannelLabels
}

/// The four leg titles ("Ear", "Turn-taking", "Brain", "Voice").
public struct VoiceStudioLegLabels: Codable, Equatable, Sendable {
    public let stt: String
    public let turn: String
    public let llm: String
    public let tts: String
}

/// The four meter stage names.
public struct VoiceStudioStageLabels: Codable, Equatable, Sendable {
    public let eou: String
    public let llmTtft: String
    public let ttsTtfb: String
    public let realtimeTtft: String

    enum CodingKeys: String, CodingKey {
        case eou
        case llmTtft = "llm_ttft"
        case ttsTtfb = "tts_ttfb"
        case realtimeTtft = "realtime_ttft"
    }
}

/// The four channel names.
public struct VoiceStudioChannelLabels: Codable, Equatable, Sendable {
    public let stable: String
    public let latest: String
    public let preview: String
    public let legacy: String
}

/// One leg's number: a measured median or a lab probe.
///
/// ⛔ OPTIONAL AT EVERY USE, AND NIL MEANS "NOT MEASURED YET". A client shows
/// ``VoiceStudioLabels/notMeasured`` and never estimates.
public struct VoiceStudioLatency: Codable, Equatable, Sendable {
    /// `measured` or `lab`. ⛔ Only a measured number counts towards a meter.
    public let source: String
    /// The measured median, or the lab probe's figure, in milliseconds.
    public let ms: Double
    /// Calls behind a measured median; null for a lab probe.
    public let samples: Int?
    /// Already formatted for the locale ("Median 420 ms over 268 calls").
    public let text: String

    public init(source: String, ms: Double, samples: Int?, text: String) {
        self.source = source
        self.ms = ms
        self.samples = samples
        self.text = text
    }

    /// The `source` of a median measured on live calls.
    public static let measuredSource = "measured"

    /// Whether this number may count towards a time-to-first-word meter.
    public var isMeasured: Bool {
        source == Self.measuredSource
    }
}

/// Where one leg, location or recipe is processed.
public struct VoiceStudioResidency: Codable, Equatable, Sendable {
    /// A closed label: `US`, `Canada`, `EU`, `APAC` or `Global (Google)`.
    public let processedIn: String
    public let inRegion: Bool
    /// "Processed in Canada" / "Leaves your region: United States".
    public let text: String
    /// Empty when in region.
    public let vendorsOutOfRegion: [String]
}

/// One stage of a time-to-first-word reading.
public struct VoiceStudioStage: Codable, Equatable, Sendable {
    /// `eou`, `llm_ttft`, `tts_ttfb` or `realtime_ttft`.
    public let stage: String
    public let label: String
    public let ms: Double?
    public let samples: Int?
    /// The measured sentence, or ``VoiceStudioLabels/notMeasured``.
    public let text: String
}

/// A recipe's time-to-first-word meter.
public struct VoiceStudioMeter: Codable, Equatable, Sendable {
    /// The sum of the measured medians; null when nothing is measured.
    public let ms: Double?
    /// ⛔ A stage is missing, so the headline says "at least" and never "about".
    public let atLeast: Bool
    /// "About 970 ms" / "At least 300 ms" / "Not measured yet".
    public let text: String
    /// The "some steps are not measured" sentence, when ``atLeast`` and ``ms`` is set.
    public let note: String?
    /// Call order: a chain's eou, llm_ttft, tts_ttfb; a realtime engine's eou, realtime_ttft.
    public let stages: [VoiceStudioStage]
}

/// The CURRENT engine's meter, which also carries what a client needs to recompute one.
///
/// ⚠️ A SEPARATE TYPE FROM ``VoiceStudioMeter``, NOT ONE WITH MORE OPTIONALS. The four extra
/// keys appear on the top-level meter and never on a recipe's; one type accepting both shapes
/// could not tell a recipe meter that lost them from one that never had them.
public struct VoiceStudioCurrentMeter: Codable, Equatable, Sendable {
    public let ms: Double?
    public let atLeast: Bool
    public let text: String
    public let note: String?
    public let stages: [VoiceStudioStage]
    /// The region's end-of-turn median: the first stage of every chain.
    public let eou: VoiceStudioLatency?
    /// "Measured on live calls over 30 days, to Oct 3, 2026. ..."
    public let sourceText: String
    /// `YYYY-MM-DD`.
    public let measuredThrough: String
    public let measuredDays: Int
}

/// A persona PATCH body for the Studio's keys, as the service computes it. Nil is "do not send".
///
/// ⛔ `current.fields` IS THE BASELINE AN EDIT IS DIFFED AGAINST, and after every save the
/// client reads the Studio again and compares it with what it sent: the PATCH answers 200 for
/// several values it silently ignores, and that comparison is the only way to see them.
public struct VoiceStudioFields: Codable, Equatable, Sendable {
    public var modelId: String
    public var voice: String
    /// Only with `modelId` `custom-pipeline`.
    public var engineMix: EngineMix?
    /// Chains only.
    public var preemptiveTts: Bool?
    /// Realtime only, 0 to 1.
    public var temperature: Double?
    /// Only on `custom-pipeline` or `gemini-3.8-live` with an English or French persona.
    public var bilingual: Bool?
    /// `gemini-live-2.5-flash-native-audio` only, once chosen.
    public var voiceStyle: String?

    public init(
        modelId: String,
        voice: String,
        engineMix: EngineMix? = nil,
        preemptiveTts: Bool? = nil,
        temperature: Double? = nil,
        bilingual: Bool? = nil,
        voiceStyle: String? = nil
    ) {
        self.modelId = modelId
        self.voice = voice
        self.engineMix = engineMix
        self.preemptiveTts = preemptiveTts
        self.temperature = temperature
        self.bilingual = bilingual
        self.voiceStyle = voiceStyle
    }
}

/// One block of the signal chain: Ear, Turn-taking, Brain, Voice, or one realtime block.
public struct VoiceStudioBlock: Codable, Equatable, Sendable {
    /// `stt`, `turn`, `llm`, `tts` or `realtime`.
    public let leg: String
    /// "Ear", "Turn-taking", "Brain", "Voice", "All-in-one".
    public let title: String
    /// "Speech recognition", "When to reply" ...
    public let role: String
    /// The model's display name.
    public let model: String
    public let channel: String
    public let channelLabel: String
    /// The residency sentence.
    public let `where`: String
    /// Null for the turn detector, which runs in the voice agent rather than at a vendor.
    public let inRegion: Bool?
    /// The Preview note on a Preview realtime model.
    public let note: String?
    public let latency: VoiceStudioLatency?
}

/// The whole call's residency for one engine.
public struct VoiceStudioChainResidency: Codable, Equatable, Sendable {
    public let inRegion: Bool
    public let text: String
    /// One sentence per leg that leaves the region.
    public let legsOut: [String]
}

/// A resolved engine: a chain of legs, or one realtime model.
///
/// ⚠️ ``engineMix`` IS SET EXACTLY WHEN ``kind`` IS `chained`, and ``realtimeModelId`` exactly
/// when it is `realtime`. The contract tests pin that pairing on every chain in the fixture.
public struct VoiceStudioChain: Codable, Equatable, Sendable {
    /// `chained` or `realtime`.
    public let kind: String
    public let engineMix: EngineMix?
    public let realtimeModelId: String?
    public let voice: String
    /// Four for a chain, one for a realtime engine.
    public let blocks: [VoiceStudioBlock]
    public let residency: VoiceStudioChainResidency
}

/// What the persona holds today, as the Studio holds it.
public struct VoiceStudioCurrent: Codable, Equatable, Sendable {
    /// The stored `aiPersona.modelId`; null when never set (the agent runs Gemini 2.5 Live).
    public let modelId: String?
    /// The stored mix, sanitized as the PATCH would accept it, else null.
    public let engineMix: EngineMix?
    public let preemptiveTts: Bool
    /// The realtime temperature as the Studio holds it, 0 to 1.
    public let temperature: Double
    public let bilingual: Bool
    public let voiceStyle: String?
    /// The tile the saved engine matches, `custom` when none.
    public let recipeId: String
    /// `stable` or `latest`.
    public let tier: String
    public let fields: VoiceStudioFields
    public let chain: VoiceStudioChain
}

/// One recipe tile.
public struct VoiceStudioRecipe: Codable, Equatable, Sendable {
    /// `in-region`, `fastest`, `natural`, `bilingual`, `realtime` or `custom`.
    public let id: String
    public let tier: String
    public let name: String
    public let description: String
    /// The region's default tile.
    public let isDefault: Bool
    public let channel: String
    public let channelLabel: String
    public let note: String?
    public let bilingual: Bool
    /// The whole call, by its weakest leg.
    public let residency: VoiceStudioResidency
    public let timeToFirstWord: VoiceStudioMeter
    /// The engine the tile applies.
    public let chain: VoiceStudioChain
    /// The PATCH body that applies it, computed against the SAVED engine's voice.
    public let save: VoiceStudioFields
}
