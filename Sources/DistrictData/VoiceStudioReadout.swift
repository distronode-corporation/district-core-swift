import DistrictModel
import Foundation

/// A leg's number as a screen shows it.
///
/// ⛔ THREE CASES AND NO FOURTH: the service's own sentence, a measured per-voice median the
/// service sent as a bare number, or nothing ("not measured yet"). There is no estimate
/// anywhere.
public enum VoiceStudioLatencyText: Equatable, Sendable {
    case server(String)
    case milliseconds(Double)
    case none

    public init(_ latency: VoiceStudioLatency?) {
        self = latency.map { .server($0.text) } ?? .none
    }
}

/// One block of the signal chain, as drawn.
public struct VoiceStudioBlockView: Equatable, Sendable {
    public let leg: String
    public let title: String
    public let role: String
    public let model: String
    public let channel: String
    public let channelLabel: String
    public let place: String
    /// Nil for the turn detector, which runs in the voice agent.
    public let inRegion: Bool?
    public let note: String?
    public let latency: VoiceStudioLatencyText
}

/// One stage of the meter.
public struct VoiceStudioStageView: Equatable, Sendable {
    public let label: String
    public let value: VoiceStudioLatencyText
}

/// The meter's headline.
public enum VoiceStudioMeterHeadline: Equatable, Sendable {
    /// The service's own sentence ("About 970 ms").
    case server(String)
    /// ⛔ A SUM OF MEASURED MEDIANS for an engine the service has not described (an unsaved
    /// edit). `atLeast` when a stage is missing: the missing stage is not estimated, so the real
    /// time is longer than the sum, and the words must say "at least", never "about".
    case local(ms: Double, atLeast: Bool)
    /// Nothing is measured.
    case none
}

public struct VoiceStudioMeterView: Equatable, Sendable {
    public let headline: VoiceStudioMeterHeadline
    public let note: String?
    public let stages: [VoiceStudioStageView]
}

public struct VoiceStudioResidencyView: Equatable, Sendable {
    public let inRegion: Bool
    public let text: String
    public let legsOut: [String]
}

/// What the chain strip, the meter and the residency summary say for the engine held.
///
/// ⛔ THE SERVICE'S OWN WORDS WHENEVER IT HAS DESCRIBED THIS ENGINE. When the held engine IS the
/// saved one, or IS a recipe's, every block, number and sentence is the service's, verbatim.
/// Only an unsaved edit the service never described is assembled (``VoiceStudioLocalReadout``),
/// from the per-leg catalogue the same response carries, and the service's numbers win again
/// after the save.
public enum VoiceStudioReadout {
    public static func blocks(_ engine: VoiceStudioEngine, in studio: VoiceStudioResponse) -> [VoiceStudioBlockView] {
        guard let chain = serverChain(engine, in: studio) else {
            return VoiceStudioLocalReadout.blocks(engine, in: studio)
        }
        return chain.blocks.map(view(of:))
    }

    public static func meter(_ engine: VoiceStudioEngine, in studio: VoiceStudioResponse) -> VoiceStudioMeterView {
        if engine == VoiceStudioEngine(chain: studio.current.chain) {
            let meter = studio.latency
            return VoiceStudioMeterView(
                headline: .server(meter.text),
                note: meter.note,
                stages: meter.stages.map(stage)
            )
        }
        guard let recipe = studio.recipes.first(where: { VoiceStudioEngine(chain: $0.chain) == engine }) else {
            return VoiceStudioLocalReadout.meter(engine, in: studio)
        }
        let meter = recipe.timeToFirstWord
        return VoiceStudioMeterView(
            headline: .server(meter.text),
            note: meter.note,
            stages: meter.stages.map(stage)
        )
    }

    public static func residency(
        _ engine: VoiceStudioEngine,
        in studio: VoiceStudioResponse
    ) -> VoiceStudioResidencyView {
        guard let chain = serverChain(engine, in: studio) else {
            return VoiceStudioLocalReadout.residency(engine, in: studio)
        }
        return VoiceStudioResidencyView(
            inRegion: chain.residency.inRegion,
            text: chain.residency.text,
            legsOut: chain.residency.legsOut
        )
    }

    private static func serverChain(_ engine: VoiceStudioEngine, in studio: VoiceStudioResponse) -> VoiceStudioChain? {
        if VoiceStudioEngine(chain: studio.current.chain) == engine {
            return studio.current.chain
        }
        return studio.recipes.map(\.chain).first { VoiceStudioEngine(chain: $0) == engine }
    }

    private static func view(of block: VoiceStudioBlock) -> VoiceStudioBlockView {
        VoiceStudioBlockView(
            leg: block.leg,
            title: block.title,
            role: block.role,
            model: block.model,
            channel: block.channel,
            channelLabel: block.channelLabel,
            place: block.where,
            inRegion: block.inRegion,
            note: block.note,
            latency: VoiceStudioLatencyText(block.latency)
        )
    }

    private static func stage(_ stage: VoiceStudioStage) -> VoiceStudioStageView {
        VoiceStudioStageView(label: stage.label, value: .server(stage.text))
    }
}
