import DistrictModel
import Foundation

/// The readout for an engine the service has not described: an unsaved edit.
///
/// ⛔ ASSEMBLED, NEVER ESTIMATED. Every sentence is one the same response already carries (a
/// model's residency, a location's residency, a leg's latency text) and every number is a
/// measured median the service sent. A stage with no measured median is MISSING, and a missing
/// stage makes the meter "at least". This is section 4 of the service's Studio spec: a chain's
/// meter is the region's end-of-turn median, plus the brain's only at the region's own location
/// with thinking off (the setting it was measured on), plus the mouth's (per voice for
/// Deepgram, per model for every other vendor); a realtime meter is a missing end of turn plus
/// the model's.
public enum VoiceStudioLocalReadout {
    private static let auto = "auto"
    private static let thinkingOff = "off"
    private static let perVoiceVendor = "deepgram"
    private static let stableChannel = "stable"

    /// Each leg's title and role, by leg.
    typealias Roles = [String: (title: String, role: String)]

    /// The catalogue entries a chain's three model legs name, and where each is processed.
    struct Legs {
        let ear: VoiceStudioSttModel
        let brain: VoiceStudioLlmModel
        let mouth: VoiceStudioTtsModel
        let earPlace: VoiceStudioResidency
        let brainPlace: VoiceStudioResidency
        let mouthPlace: VoiceStudioResidency
    }

    /// ⚠️ Nil when a leg names a model the catalogue does not list, which the service never
    /// holds; the readout then claims nothing rather than guessing.
    static func resolve(_ mix: EngineMix, in studio: VoiceStudioResponse) -> Legs? {
        let catalog = studio.catalog
        guard
            let ear = catalog.stt.first(where: { $0.provider == mix.stt.provider && $0.model == mix.stt.model }),
            let brain = catalog.llm.first(where: { $0.model == mix.llm.model }),
            let mouth = catalog.tts.first(where: { $0.provider == mix.tts.provider && $0.model == mix.tts.model })
        else { return nil }
        return Legs(
            ear: ear,
            brain: brain,
            mouth: mouth,
            earPlace: placed(ear.locations, mix.stt.location, fallback: ear.residency),
            brainPlace: placed(brain.locations, mix.llm.location, fallback: brain.residency),
            mouthPlace: placed(mouth.locations, mix.tts.location, fallback: mouth.residency)
        )
    }

    public static func blocks(
        _ engine: VoiceStudioEngine,
        in studio: VoiceStudioResponse
    ) -> [VoiceStudioBlockView] {
        switch engine {
        case let .chained(mix):
            guard let legs = resolve(mix, in: studio) else { return [] }
            return chainBlocks(mix, legs: legs, in: studio)
        case let .realtime(modelId, _):
            guard let model = realtime(modelId, in: studio) else { return [] }
            return [realtimeBlock(model, in: studio)]
        }
    }

    public static func meter(_ engine: VoiceStudioEngine, in studio: VoiceStudioResponse) -> VoiceStudioMeterView {
        let labels = studio.labels.stages
        let stages: [(String, VoiceStudioLatency?)]
        switch engine {
        case let .chained(mix):
            let legs = resolve(mix, in: studio)
            stages = [
                (labels.eou, studio.latency.eou.flatMap { $0.isMeasured ? $0 : nil }),
                (labels.llmTtft, legs.flatMap { brainMeasured(mix, $0.brain) }),
                (labels.ttsTtfb, legs.flatMap { mouthMeasured(mix, $0.mouth, in: studio) }),
            ]
        case let .realtime(modelId, _):
            stages = [
                (labels.eou, nil),
                (labels.realtimeTtft, realtime(modelId, in: studio)?.latency.flatMap { $0.isMeasured ? $0 : nil }),
            ]
        }
        let measured = stages.compactMap { $0.1?.ms }
        let missing = measured.count < stages.count
        let headline: VoiceStudioMeterHeadline = measured.isEmpty
            ? .none
            : .local(ms: measured.reduce(0, +), atLeast: missing)
        // The "some steps are not measured" sentence is the service's template, in the portal
        // language, shown under an "at least" headline and never under "not measured yet".
        return VoiceStudioMeterView(
            headline: headline,
            note: missing && !measured.isEmpty ? studio.labels.meterPartial : nil,
            stages: stages.map { VoiceStudioStageView(label: $0.0, value: stageText($0.1)) }
        )
    }

    public static func residency(
        _ engine: VoiceStudioEngine,
        in studio: VoiceStudioResponse
    ) -> VoiceStudioResidencyView {
        let labels = studio.labels
        let legs: [(String, VoiceStudioResidency)]? = switch engine {
        case let .chained(mix):
            resolve(mix, in: studio).map { resolved in
                [
                    (labels.legs.stt, resolved.earPlace),
                    (labels.legs.llm, resolved.brainPlace),
                    (labels.legs.tts, resolved.mouthPlace),
                ]
            }
        case let .realtime(modelId, _):
            realtime(modelId, in: studio).map { [(realtimeTitle($0, in: studio), $0.residency)] }
        }
        // ⛔ AN ENGINE NOTHING CAN DESCRIBE IS NOT CLAIMED TO STAY IN REGION.
        guard let legs else {
            return VoiceStudioResidencyView(inRegion: false, text: labels.leavesRegion, legsOut: [])
        }
        let out = legs.filter { !$0.1.inRegion }.map { "\($0.0): \($0.1.text)" }
        return VoiceStudioResidencyView(
            inRegion: out.isEmpty,
            text: out.isEmpty ? labels.allInRegion : labels.leavesRegion,
            legsOut: out
        )
    }

    // MARK: - Per-leg facts

    static func placed(
        _ locations: [VoiceStudioLocation],
        _ location: String?,
        fallback: VoiceStudioResidency
    ) -> VoiceStudioResidency {
        locations.first { $0.value == location }?.residency ?? fallback
    }

    /// Whether the brain runs where its median was measured: the region's own location
    /// (`auto`, or the location `auto` names) with thinking off.
    static func brainLocal(_ mix: EngineMix, _ brain: VoiceStudioLlmModel) -> Bool {
        guard mix.llm.thinking == thinkingOff else { return false }
        if mix.llm.location == auto {
            return true
        }
        guard let regional = brain.locations.first(where: { $0.value == auto })?.residency else { return false }
        let chosen = placed(brain.locations, mix.llm.location, fallback: brain.residency)
        return chosen.inRegion && chosen.processedIn == regional.processedIn
    }

    static func brainMeasured(_ mix: EngineMix, _ brain: VoiceStudioLlmModel) -> VoiceStudioLatency? {
        guard let latency = brain.latency, latency.isMeasured, brainLocal(mix, brain) else { return nil }
        return latency
    }

    /// The mouth's measured median: per voice for Deepgram, the model's for every other vendor.
    static func mouthMeasured(
        _ mix: EngineMix,
        _ mouth: VoiceStudioTtsModel,
        in studio: VoiceStudioResponse
    ) -> VoiceStudioLatency? {
        if mix.tts.provider != perVoiceVendor || mix.tts.voice == mouth.defaultVoice {
            return mouth.latency.flatMap { $0.isMeasured ? $0 : nil }
        }
        guard let p50 = voiceP50(mix, in: studio) else { return nil }
        return VoiceStudioLatency(source: VoiceStudioLatency.measuredSource, ms: p50, samples: nil, text: "")
    }

    static func mouthText(
        _ mix: EngineMix,
        _ mouth: VoiceStudioTtsModel,
        in studio: VoiceStudioResponse
    ) -> VoiceStudioLatencyText {
        if mix.tts.provider != perVoiceVendor || mix.tts.voice == mouth.defaultVoice {
            return VoiceStudioLatencyText(mouth.latency)
        }
        return voiceP50(mix, in: studio).map { .milliseconds($0) } ?? .none
    }

    static func voiceP50(_ mix: EngineMix, in studio: VoiceStudioResponse) -> Double? {
        let list = VoiceStudioRecipes.ttsVoices(provider: mix.tts.provider, model: mix.tts.model, in: studio)
        return VoiceStudioRecipes.voiceOption(mix.tts.voice, in: list)?.p50
    }

    /// A stage's words: the service's sentence where it wrote one, else the bare measured number.
    static func stageText(_ latency: VoiceStudioLatency?) -> VoiceStudioLatencyText {
        guard let latency else { return .none }
        return latency.text.isEmpty ? .milliseconds(latency.ms) : .server(latency.text)
    }

    // MARK: - Blocks

    private static func chainBlocks(
        _ mix: EngineMix,
        legs: Legs,
        in studio: VoiceStudioResponse
    ) -> [VoiceStudioBlockView] {
        let titles = roles(in: studio)
        return [
            earBlock(legs, roles: titles, in: studio),
            turnBlock(legs, roles: titles, in: studio),
            brainBlock(mix, legs: legs, roles: titles, in: studio),
            mouthBlock(mix, legs: legs, roles: titles, in: studio),
        ]
    }

    private static func earBlock(_ legs: Legs, roles: Roles, in studio: VoiceStudioResponse) -> VoiceStudioBlockView {
        VoiceStudioBlockView(
            leg: VoiceStudioLeg.stt.rawValue,
            title: studio.labels.legs.stt,
            role: role(roles, .stt),
            model: "\(legs.ear.providerLabel) \(legs.ear.label)",
            channel: legs.ear.channel,
            channelLabel: legs.ear.channelLabel,
            place: legs.earPlace.text,
            inRegion: legs.earPlace.inRegion,
            note: nil,
            latency: VoiceStudioLatencyText(legs.ear.latency)
        )
    }

    /// ⚠️ FLUX DECIDES END OF TURN ITSELF, so its Turn-taking block is the ear's (its channel,
    /// its place); every other ear hands the decision to the voice agent's detector.
    private static func turnBlock(_ legs: Legs, roles: Roles, in studio: VoiceStudioResponse) -> VoiceStudioBlockView {
        let turn = studio.catalog.turn
        let flux = legs.ear.takesTurns
        return VoiceStudioBlockView(
            leg: VoiceStudioLeg.turn.rawValue,
            title: studio.labels.legs.turn,
            role: role(roles, .turn),
            model: flux ? turn.ear.label : turn.detector.label,
            channel: flux ? legs.ear.channel : stableChannel,
            channelLabel: flux ? legs.ear.channelLabel : studio.labels.channels.stable,
            place: flux ? legs.earPlace.text : turn.detector.where,
            inRegion: flux ? legs.earPlace.inRegion : nil,
            note: nil,
            latency: VoiceStudioLatencyText(turn.latency)
        )
    }

    /// ⚠️ A MEASURED BRAIN NUMBER IS SHOWN ONLY WHERE IT WAS MEASURED (see ``brainLocal(_:_:)``);
    /// a lab probe is shown as the lab probe it is.
    private static func brainBlock(
        _ mix: EngineMix,
        legs: Legs,
        roles: Roles,
        in studio: VoiceStudioResponse
    ) -> VoiceStudioBlockView {
        let latency = legs.brain.latency.flatMap { !$0.isMeasured || brainLocal(mix, legs.brain) ? $0 : nil }
        return VoiceStudioBlockView(
            leg: VoiceStudioLeg.llm.rawValue,
            title: studio.labels.legs.llm,
            role: role(roles, .llm),
            model: legs.brain.label,
            channel: legs.brain.channel,
            channelLabel: legs.brain.channelLabel,
            place: legs.brainPlace.text,
            inRegion: legs.brainPlace.inRegion,
            note: nil,
            latency: VoiceStudioLatencyText(latency)
        )
    }

    private static func mouthBlock(
        _ mix: EngineMix,
        legs: Legs,
        roles: Roles,
        in studio: VoiceStudioResponse
    ) -> VoiceStudioBlockView {
        VoiceStudioBlockView(
            leg: VoiceStudioLeg.tts.rawValue,
            title: studio.labels.legs.tts,
            role: role(roles, .tts),
            model: "\(legs.mouth.providerLabel) \(legs.mouth.label)",
            channel: legs.mouth.channel,
            channelLabel: legs.mouth.channelLabel,
            place: legs.mouthPlace.text,
            inRegion: legs.mouthPlace.inRegion,
            note: nil,
            latency: mouthText(mix, legs.mouth, in: studio)
        )
    }

    private static func realtimeBlock(
        _ model: VoiceStudioRealtimeModel,
        in studio: VoiceStudioResponse
    ) -> VoiceStudioBlockView {
        VoiceStudioBlockView(
            leg: VoiceStudioLeg.realtime.rawValue,
            title: realtimeTitle(model, in: studio),
            role: role(roles(in: studio), .realtime),
            model: model.label,
            channel: model.channel,
            channelLabel: model.channelLabel,
            place: model.residency.text,
            inRegion: model.residency.inRegion,
            note: model.note,
            latency: VoiceStudioLatencyText(model.latency)
        )
    }

    private static func realtime(_ modelId: String, in studio: VoiceStudioResponse) -> VoiceStudioRealtimeModel? {
        studio.catalog.realtime.first { $0.model == modelId }
    }

    /// The realtime block's title ("All-in-one") is only in the service's blocks; else the
    /// model's own name.
    private static func realtimeTitle(_ model: VoiceStudioRealtimeModel, in studio: VoiceStudioResponse) -> String {
        roles(in: studio)[VoiceStudioLeg.realtime.rawValue]?.title ?? model.label
    }

    /// Each leg's title and role ("Speech recognition"), which only the service's blocks carry.
    private static func roles(in studio: VoiceStudioResponse) -> Roles {
        let blocks = studio.current.chain.blocks + studio.recipes.flatMap(\.chain.blocks)
        var out: Roles = [:]
        for block in blocks {
            out[block.leg] = (block.title, block.role)
        }
        return out
    }

    private static func role(_ roles: Roles, _ leg: VoiceStudioLeg) -> String {
        roles[leg.rawValue]?.role ?? ""
    }
}
