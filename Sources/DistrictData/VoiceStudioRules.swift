import DistrictModel
import DistrictNetwork
import Foundation

/// What a Studio state saves as, which keys a save sends, whether the re-read agrees, and how
/// far an edit is from the recipe it started from.
///
/// ⛔ A PORT OF THE WEB STUDIO'S `fieldsOf`, `changedFields`, `canonicalModelId` AND
/// `countChanges` (`studioModel.ts`), and the preset rule is the one that matters: a chain equal
/// to one of the service's presets saves as that FIXED engine's id (its voice and speak-sooner
/// at top level), never as `custom-pipeline` with a mix. Saving it as custom would move a
/// workspace off a fixed engine nobody asked it to leave.
public enum VoiceStudioRules {
    /// The engine id of every chain that is not exactly a preset.
    public static let customPipeline = "custom-pipeline"
    /// Gemini 2.5 Live, the one engine with a voice style.
    public static let geminiLive25 = "gemini-live-2.5-flash-native-audio"
    /// Gemini 3.8 Live, refused in `eu` (`model_unavailable_in_region`).
    public static let gemini38Live = "gemini-3.8-live"

    /// The two engines that carry `aiPersona.bilingual` (the voice agent's `BILINGUAL_MODEL_IDS`).
    private static let bilingualEngines: Set<String> = [customPipeline, gemini38Live]

    /// English and French are the only bilingual pair.
    private static let bilingualLanguages: Set<String> = ["en", "fr"]

    /// ⚠️ A slider's worth of float noise: a wire round trip of a double is not bit-identical.
    private static let numberEpsilon = 0.0005

    // MARK: - Bilingual

    /// Whether a persona language has a bilingual counterpart (English or French).
    public static func bilingualPair(_ language: String) -> Bool {
        let base = language.split(separator: "-").first.map(String.init) ?? language
        return bilingualLanguages.contains(base.lowercased())
    }

    /// Whether `bilingual` applies to an engine id and a persona language.
    public static func bilingualAvailable(modelId: String, language: String) -> Bool {
        bilingualEngines.contains(modelId) && bilingualPair(language)
    }

    // MARK: - What a state saves as

    /// The engine id a chain saves as: the first preset it equals, else `custom-pipeline`.
    ///
    /// ⛔ ANY STUDIO TUNING KEY MAKES IT CUSTOM, because a fixed engine cannot carry one. Then
    /// equality covers the ear (provider, model, language, location), the brain (model,
    /// location, thinking, temperature), the mouth (provider, model, speed, location) and
    /// turn-taking's three numbers. The VOICE and speak-sooner are ignored (a fixed engine takes
    /// any voice of its model and its own speak-sooner flag), and so is `userAwayTimeout`.
    public static func canonicalModelId(_ mix: EngineMix, presets: [VoiceStudioPreset]) -> String {
        guard !hasChainTuning(mix) else { return customPipeline }
        return presets.first { sameCore($0.engineMix, mix) }?.modelId ?? customPipeline
    }

    /// What a state saves as, for a persona speaking `language`.
    public static func fields(
        of state: VoiceStudioState,
        presets: [VoiceStudioPreset],
        language: String
    ) -> VoiceStudioFields {
        var fields: VoiceStudioFields
        switch state.engine {
        case let .chained(mix):
            // ⛔ A bilingual chain is the custom engine by definition: only the two preview
            // engines carry `aiPersona.bilingual`.
            let modelId = state.bilingual && bilingualPair(language)
                ? customPipeline
                : canonicalModelId(mix, presets: presets)
            fields = VoiceStudioFields(
                modelId: modelId,
                voice: mix.tts.voice,
                engineMix: modelId == customPipeline ? mix : nil,
                preemptiveTts: mix.preemptiveTts
            )
        case let .realtime(modelId, voice):
            fields = VoiceStudioFields(
                modelId: modelId,
                voice: voice,
                temperature: state.realtimeTemperature,
                voiceStyle: modelId == geminiLive25 ? state.voiceStyle : nil
            )
        }
        fields.bilingual = bilingualAvailable(modelId: fields.modelId, language: language) ? state.bilingual : nil
        return fields
    }

    // MARK: - What a save sends, and whether it landed

    /// The keys of `current` that differ from `saved`: what the PATCH sends.
    ///
    /// ⛔ ONLY CHANGED KEYS, so a teammate's save of a key this screen never touched is not
    /// undone. ⛔ `modelId` AND `engineMix` TRAVEL TOGETHER: the route reads a mix only beside
    /// the id it belongs to. ⚠️ An absent bilingual flag and `false` say the same thing, so
    /// only a real change is sent; a key `current` does not carry (nil) is never sent.
    public static func changedKeys(saved: VoiceStudioFields, current: VoiceStudioFields) -> Set<VoiceStudioKey> {
        var changed = Set(VoiceStudioKey.allCases.filter { key in
            guard let now = value(of: key, in: current) else { return false }
            return normalised(key, value(of: key, in: saved)) != normalised(key, now)
        })
        if changed.contains(.modelId) || changed.contains(.engineMix) {
            changed.insert(.modelId)
            if current.engineMix != nil {
                changed.insert(.engineMix)
            }
        }
        return changed
    }

    /// Whether the re-read holds what was sent, key by key.
    ///
    /// ⛔ THE ONLY WAY TO SEE A SILENT REFUSAL. The PATCH answers 200 for an unknown `modelId`
    /// (coerced), a wrong-typed `temperature` (ignored) and more; comparing the re-read with
    /// the body is the client rule the service's spec states.
    public static func landed(sent: VoiceStudioFields, keys: Set<VoiceStudioKey>, reread: VoiceStudioFields) -> Bool {
        keys.allSatisfy { key in
            let want = normalised(key, value(of: key, in: sent))
            let got = normalised(key, value(of: key, in: reread))
            if case let .number(wanted) = want, case let .number(received) = got {
                return abs(wanted - received) < numberEpsilon
            }
            return want == got
        }
    }

    // MARK: - How far an edit is from its recipe

    /// How many settings differ between two engines ("Based on Fastest, 2 changes").
    ///
    /// ⚠️ COUNTED OVER LEAVES, AS THE WEB COUNTS THEM: a key present on one side and absent on
    /// the other is a change, and a null is a value. The leaves are taken from the mix in the
    /// PATCH's own shape (``JSONValue/engineMix(_:)``), which is the web object's shape: an
    /// always-present key is a `null` leaf, an absent-when-unset one is no leaf.
    public static func countChanges(base: VoiceStudioEngine, current: VoiceStudioEngine) -> Int {
        let before = leaves(of: base)
        let after = leaves(of: current)
        return Set(before.keys).union(after.keys).filter { before[$0] != after[$0] }.count
    }

    // MARK: - Internals

    private static func hasChainTuning(_ mix: EngineMix) -> Bool {
        mix.stt.keyterms != nil || mix.tts.stability != nil || mix.tts.expressivity != nil
            || mix.turn.mode != nil || mix.turn.eagerEotThreshold != nil || mix.turn.eotTimeoutMs != nil
            || mix.turn.interruption != nil
    }

    private static func sameCore(_ preset: EngineMix, _ mix: EngineMix) -> Bool {
        var presetMouth = preset.tts
        presetMouth.voice = ""
        var mouth = mix.tts
        mouth.voice = ""
        return preset.stt == mix.stt && preset.llm == mix.llm && presetMouth == mouth && preset.turn == mix.turn
    }

    /// A key's value as a comparable JSON value, nil when the fields do not carry it.
    private static func value(of key: VoiceStudioKey, in fields: VoiceStudioFields) -> JSONValue? {
        switch key {
        case .modelId: .string(fields.modelId)
        case .voice: .string(fields.voice)
        case .engineMix: fields.engineMix.map { JSONValue.engineMix($0) }
        case .preemptiveTts: fields.preemptiveTts.map { JSONValue.bool($0) }
        case .temperature: fields.temperature.map { JSONValue.number($0) }
        case .bilingual: fields.bilingual.map { JSONValue.bool($0) }
        case .voiceStyle: fields.voiceStyle.map { JSONValue.string($0) }
        }
    }

    /// ⚠️ An absent bilingual flag is `false`; every other key compares as it is.
    private static func normalised(_ key: VoiceStudioKey, _ value: JSONValue?) -> JSONValue? {
        key == .bilingual ? .bool(value == .bool(true)) : value
    }

    private static func leaves(of engine: VoiceStudioEngine) -> [String: String] {
        var out: [String: String] = [:]
        switch engine {
        case let .chained(mix):
            out[".kind"] = "chained"
            flatten(JSONValue.engineMix(mix), at: ".mix", into: &out)
        case let .realtime(modelId, voice):
            out[".kind"] = "realtime"
            out[".modelId"] = modelId
            out[".voice"] = voice
        }
        return out
    }

    private static func flatten(_ value: JSONValue, at path: String, into out: inout [String: String]) {
        guard case let .object(fields) = value else {
            out[path] = String(describing: value)
            return
        }
        for (key, child) in fields {
            flatten(child, at: "\(path).\(key)", into: &out)
        }
    }
}
