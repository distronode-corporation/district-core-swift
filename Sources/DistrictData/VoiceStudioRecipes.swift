import DistrictModel
import Foundation

/// Recipes, voices, and the engine a tile applies.
///
/// ⚠️ PORTED FROM THE WEB STUDIO (`choiceEngine`, `appliedEngine`), with every list read from
/// the Studio response rather than from a catalogue in this package.
public enum VoiceStudioRecipes {
    /// "Your chain": the saved chain, or the region's starting chain when a realtime engine is
    /// saved.
    public static let custom = "custom"
    public static let stable = "stable"
    public static let latest = "latest"

    private static let ttsKind = "tts"
    private static let realtimeKind = "realtime"

    /// One tier's tiles, in the service's tile order.
    public static func tiles(_ studio: VoiceStudioResponse, tier: String) -> [VoiceStudioRecipe] {
        studio.recipeIds.compactMap { id in
            studio.recipes.first { $0.id == id && $0.tier == tier }
        }
    }

    /// The engine a recipe tile applies.
    ///
    /// ⛔ "YOUR CHAIN" IS THE SAVED CHAIN ITSELF, voice included, when the saved engine is a
    /// chain. Any other recipe keeps the voice the Studio holds now where the new mouth (or
    /// realtime model) has it: picking "Fastest" must not silently change who the caller hears
    /// when it need not. Otherwise the recipe's own voice, which the service chose for that
    /// mouth.
    public static func applied(
        _ recipe: VoiceStudioRecipe,
        saved: VoiceStudioEngine,
        current: VoiceStudioEngine,
        studio: VoiceStudioResponse
    ) -> VoiceStudioEngine {
        if recipe.id == custom, saved.mix != nil {
            return saved
        }
        let engine = VoiceStudioEngine(chain: recipe.chain)
        let keeps = voiceValues(voices(for: engine, in: studio)).contains(current.voice)
        return keeps ? engine.withVoice(current.voice) : engine
    }

    /// The voices an engine's mouth (or realtime model) speaks, or nil when the service lists
    /// none.
    public static func voices(for engine: VoiceStudioEngine, in studio: VoiceStudioResponse) -> VoiceStudioVoiceList? {
        switch engine {
        case let .chained(mix):
            ttsVoices(provider: mix.tts.provider, model: mix.tts.model, in: studio)
        case let .realtime(modelId, _):
            studio.voices.first { $0.kind == realtimeKind && $0.model == modelId }
        }
    }

    /// One text-to-speech model's voices.
    public static func ttsVoices(
        provider: String,
        model: String,
        in studio: VoiceStudioResponse
    ) -> VoiceStudioVoiceList? {
        studio.voices.first { $0.kind == ttsKind && $0.provider == provider && $0.model == model }
    }

    /// Every voice id of a list.
    public static func voiceValues(_ list: VoiceStudioVoiceList?) -> [String] {
        (list?.groups ?? []).flatMap { group in group.options.map(\.value) }
    }

    /// The held voice option, or nil when the list does not carry it.
    public static func voiceOption(_ voice: String, in list: VoiceStudioVoiceList?) -> VoiceStudioVoiceOption? {
        (list?.groups ?? []).lazy.flatMap(\.options).first { $0.value == voice }
    }
}
