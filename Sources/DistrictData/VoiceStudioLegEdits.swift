import DistrictModel
import Foundation

/// The legs of the signal chain, as the service names them.
public enum VoiceStudioLeg: String, CaseIterable, Sendable {
    /// The ear: speech recognition.
    case stt
    /// Turn-taking: when to reply.
    case turn
    /// The brain.
    case llm
    /// The mouth: speech synthesis.
    case tts
    /// One all-in-one realtime model, spanning every leg.
    case realtime
}

/// The edits a leg editor makes, each keeping the chain one the PATCH accepts.
///
/// ⛔ SECTION 3.3 OF THE SERVICE'S STUDIO SPEC, AND EVERY RULE IS THERE BECAUSE THE PATCH
/// REFUSES THE ALTERNATIVE. A mix the catalogue does not accept (a voice the new mouth does not
/// have, a location the new model is not offered in, key terms on an ear that takes none)
/// answers 400 `invalid_engine_mix` and writes nothing, so a vendor or model switch moves the
/// dependent fields with it rather than leaving them for the service to refuse. Every edit then
/// goes through ``VoiceStudioTuning/conform(_:in:)``, which drops a tuning value the new model
/// does not honour: the service would drop it silently and the re-read would then report the
/// save as failed.
public enum VoiceStudioLegEdits {
    /// A new ear vendor: its first model for the language (an offered one first), at that
    /// model's default location, with no key terms.
    public static func earVendor(
        _ mix: EngineMix,
        provider: String,
        bilingual: Bool,
        in studio: VoiceStudioResponse
    ) -> EngineMix {
        let fit = studio.catalog.stt.filter {
            $0.provider == provider && (bilingual ? $0.forBilingual : $0.forLanguage)
        }
        guard let model = fit.first(where: \.offered) ?? fit.first else { return mix }
        var next = mix
        next.stt = EngineMixStt(provider: provider, model: model.model, location: model.defaultLocation)
        return VoiceStudioTuning.conform(next, in: studio)
    }

    /// A new ear model of the same vendor: its location kept where offered, key terms only
    /// where taken.
    public static func earModel(_ mix: EngineMix, model: String, in studio: VoiceStudioResponse) -> EngineMix {
        let entry = studio.catalog.stt.first { $0.provider == mix.stt.provider && $0.model == model }
        guard let entry else { return mix }
        var next = mix
        next.stt.model = model
        next.stt.location = kept(mix.stt.location, in: entry.locations) ?? entry.defaultLocation
        next.stt.keyterms = entry.keyterms ? mix.stt.keyterms : nil
        return VoiceStudioTuning.conform(next, in: studio)
    }

    /// A new brain: its location kept where offered, its own default thinking, the temperature
    /// kept.
    public static func brainModel(_ mix: EngineMix, model: String, in studio: VoiceStudioResponse) -> EngineMix {
        guard let entry = studio.catalog.llm.first(where: { $0.model == model }) else { return mix }
        var next = mix
        next.llm.model = model
        next.llm.location = kept(mix.llm.location, in: entry.locations) ?? entry.defaultLocation
        next.llm.thinking = entry.defaultThinking
        return VoiceStudioTuning.conform(next, in: studio)
    }

    /// A new mouth vendor: its first model for the language (an offered one first), on that
    /// model's starting voice, at its default location.
    public static func voiceVendor(
        _ mix: EngineMix,
        provider: String,
        bilingual: Bool,
        in studio: VoiceStudioResponse
    ) -> EngineMix {
        let fit = studio.catalog.tts.filter {
            $0.provider == provider && (bilingual ? $0.forBilingual : $0.forLanguage)
        }
        guard let model = fit.first(where: \.offered) ?? fit.first else { return mix }
        var next = mix
        next.tts = EngineMixTts(
            provider: provider,
            model: model.model,
            voice: model.defaultVoice,
            location: model.defaultLocation
        )
        return VoiceStudioTuning.conform(next, in: studio)
    }

    /// A new mouth model of the same vendor: the voice kept if the new model has it, else its
    /// starting voice; the location kept where offered.
    public static func voiceModel(_ mix: EngineMix, model: String, in studio: VoiceStudioResponse) -> EngineMix {
        let entry = studio.catalog.tts.first { $0.provider == mix.tts.provider && $0.model == model }
        guard let entry else { return mix }
        let voices = VoiceStudioRecipes.voiceValues(
            VoiceStudioRecipes.ttsVoices(provider: mix.tts.provider, model: model, in: studio)
        )
        var next = mix
        next.tts.model = model
        next.tts.voice = voices.contains(mix.tts.voice) ? mix.tts.voice : entry.defaultVoice
        next.tts.location = kept(mix.tts.location, in: entry.locations) ?? entry.defaultLocation
        return VoiceStudioTuning.conform(next, in: studio)
    }

    /// A location from the held model's own list (the picker offers nothing else).
    public static func location(_ mix: EngineMix, leg: VoiceStudioLeg, location: String) -> EngineMix {
        var next = mix
        switch leg {
        case .stt: next.stt.location = location
        case .llm: next.llm.location = location
        case .tts: next.tts.location = location
        case .turn, .realtime: break
        }
        return next
    }

    /// Another realtime model: the voice kept if the new model speaks it, else its first voice.
    /// (Gemini 3.8 Live speaks 2.5 Live's five voices, so a switch between them keeps it.)
    public static func realtimeModel(
        voice: String,
        model: String,
        in studio: VoiceStudioResponse
    ) -> VoiceStudioEngine {
        let voices = VoiceStudioRecipes.voiceValues(
            VoiceStudioRecipes.voices(for: .realtime(modelId: model, voice: ""), in: studio)
        )
        let next = voices.contains(voice) ? voice : (voices.first ?? voice)
        return .realtime(modelId: model, voice: next)
    }

    /// The held location when the new model offers it, else nil.
    private static func kept(_ held: String?, in locations: [VoiceStudioLocation]) -> String? {
        guard let held, locations.contains(where: { $0.value == held }) else { return nil }
        return held
    }
}
