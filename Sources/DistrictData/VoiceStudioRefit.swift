import DistrictModel
import Foundation

/// What fitting a chain to a new persona language did.
public enum VoiceStudioRefitOutcome: Equatable, Sendable {
    /// The Studio read for the new language still accepts the stored chain; nothing was sent.
    case fits
    /// Moved to models that speak the new language, saved, and the read after it accepts it.
    case refitted
    /// No model this workspace may use speaks the new language for the ear or the voice.
    /// Nothing was sent.
    case noFit
    /// The Studio could not be read, or the moved chain's save was refused or failed.
    case failed(VoiceStudioRefusal)
    /// The moved chain was saved, and the read after it does not show it fitting, or could not
    /// be taken.
    case notSeen
}

/// A chain of the member's own, moved to models that speak a new persona language: the web's
/// `conformEngineMix`, from what the Studio's read says. The same flow as district-linux's.
///
/// ⛔ WHY THIS EXISTS. The persona screen saves a new language with the stored chain left as it
/// was, and a chain whose ear or voice does not speak the new language is one the service no
/// longer accepts: the Studio's read for the new language then holds `current.engineMix` null
/// for a `custom-pipeline` persona. The read is computed for the new language, so its catalogue
/// says which models fit (`forLanguage`); each speech leg that no longer fits moves to the
/// nearest model that does: the same vendor's first (for the ear, one that takes turns the
/// same way first), then any other in catalogue order. The voice is kept where the new model
/// has it, the location where it is offered. The brain does not depend on the language and
/// stays.
///
/// ⚠️ THE CHAIN TO FIT IS READ BEFORE THE LANGUAGE IS SAVED (``storedChain(workspaceId:in:)``):
/// the persona read the app holds does not carry the mix, and the read after the save no
/// longer does either.
public enum VoiceStudioRefit {
    /// The stored chain, when the persona runs a chain of the member's own; nil otherwise.
    public static func storedChain(
        workspaceId: String,
        in repository: VoiceStudioRepository
    ) async -> Result<EngineMix?, ApiError> {
        await repository.load(workspaceId: workspaceId).map(chain(of:))
    }

    /// Read the Studio for the new language and, when it no longer accepts `mix`, save `mix`
    /// moved to models that speak it, then read again to see that it fits.
    public static func run(
        from mix: EngineMix,
        workspaceId: String,
        in repository: VoiceStudioRepository
    ) async -> VoiceStudioRefitOutcome {
        let studio: VoiceStudioResponse
        switch await repository.load(workspaceId: workspaceId) {
        case let .success(read):
            studio = read
        case let .failure(error):
            return .failed(.failed(error))
        }
        if fits(studio) {
            return .fits
        }
        guard let moved = refit(mix, in: studio) else { return .noFit }
        let fields = VoiceStudioFields(
            modelId: VoiceStudioRules.customPipeline,
            voice: moved.tts.voice,
            engineMix: moved
        )
        switch await repository.save(workspaceId: workspaceId, fields: fields, keys: [.modelId, .voice, .engineMix]) {
        case let .saved(reread):
            return fits(reread) ? .refitted : .notSeen
        case .savedButStale:
            return .notSeen
        case let .notSaved(refusal):
            return .failed(refusal)
        }
    }

    /// Whether the service accepts the stored engine as it reads it now.
    static func fits(_ studio: VoiceStudioResponse) -> Bool {
        studio.current.modelId != VoiceStudioRules.customPipeline || studio.current.engineMix != nil
    }

    static func chain(of studio: VoiceStudioResponse) -> EngineMix? {
        studio.current.modelId == VoiceStudioRules.customPipeline ? studio.current.engineMix : nil
    }

    /// `mix` fitted to the language `studio` was read for, or nil when no offered model speaks
    /// it for the ear or the voice. A chain that already fits comes back unchanged.
    public static func refit(_ mix: EngineMix, in studio: VoiceStudioResponse) -> EngineMix? {
        guard let ear = ear(mix, in: studio), let mouth = mouth(mix, in: studio) else { return nil }
        var out = mix
        out.stt = ear
        out.tts.provider = mouth.provider
        out.tts.model = mouth.model
        let voices = VoiceStudioRecipes.voiceValues(
            VoiceStudioRecipes.ttsVoices(provider: mouth.provider, model: mouth.model, in: studio)
        )
        if !voices.contains(mix.tts.voice) {
            out.tts.voice = mouth.defaultVoice
        }
        if !mouth.locations.contains(where: { $0.value == mix.tts.location }) {
            out.tts.location = mouth.defaultLocation
        }
        return VoiceStudioTuning.conform(out, in: studio)
    }

    private static func ear(_ mix: EngineMix, in studio: VoiceStudioResponse) -> EngineMixStt? {
        let models = studio.catalog.stt
        let held = models.first { $0.provider == mix.stt.provider && $0.model == mix.stt.model }
        if let held, fitting(held.offered, held.forLanguage) {
            return mix.stt
        }
        let takesTurns = held?.takesTurns == true
        let ear = nearest(
            models.filter { fitting($0.offered, $0.forLanguage) },
            best: { $0.provider == mix.stt.provider && $0.takesTurns == takesTurns },
            good: { $0.provider == mix.stt.provider }
        )
        guard let ear else { return nil }
        let location = ear.locations.contains { $0.value == mix.stt.location } ? mix.stt.location : ear.defaultLocation
        return EngineMixStt(
            provider: ear.provider,
            model: ear.model,
            location: location,
            keyterms: ear.keyterms ? mix.stt.keyterms : nil
        )
    }

    private static func mouth(_ mix: EngineMix, in studio: VoiceStudioResponse) -> VoiceStudioTtsModel? {
        nearest(
            studio.catalog.tts.filter { fitting($0.offered, $0.forLanguage) },
            best: { $0.provider == mix.tts.provider && $0.model == mix.tts.model },
            good: { $0.provider == mix.tts.provider }
        )
    }

    private static func fitting(_ offered: Bool, _ forLanguage: Bool) -> Bool {
        offered && forLanguage
    }

    /// The first of `models` among the `best`, else among the `good`, else the first.
    private static func nearest<Model>(
        _ models: [Model],
        best: (Model) -> Bool,
        good: (Model) -> Bool
    ) -> Model? {
        if let model = models.first(where: best) {
            return model
        }
        if let model = models.first(where: good) {
            return model
        }
        return models.first
    }
}
