import DistrictModel
import Foundation

/// Where a slider runs, where it starts when first set, and what its "use the default" box says.
public struct VoiceStudioTuningRange: Equatable, Sendable {
    public let min: Double
    public let max: Double
    public let step: Double?
    public let start: Double
    public let useDefaultLabel: String?

    /// A whole-number slider (words to interrupt, the end-of-turn timeout) shows no decimals.
    public var isWhole: Bool {
        (step ?? 0) >= 1
    }
}

/// Which tuning controls a leg shows, over what range, and keeping a mix within them.
///
/// ⛔ A CONTROL APPEARS ONLY FOR THE LEG AND MODEL THAT HONOURS IT (`honouredBy` nil, or naming
/// the held provider and model), and a key this package cannot map is not drawn at all. A value
/// on a model that does not honour it is dropped by the service WITH A 200, which the re-read
/// would then report as a failed save, so it is never offered and never kept
/// (``conform(_:in:)``).
///
/// ⚠️ THE TURN-TAKING KEYS ARE HONOURED BY THE EAR. Flux decides end of turn itself, so the
/// end-of-turn keys name ear models in `honouredBy`.
public enum VoiceStudioTuning {
    /// The keys a leg's editor shows for the held engine, in the service's order.
    public static func keys(
        for leg: VoiceStudioLeg,
        engine: VoiceStudioEngine,
        in studio: VoiceStudioResponse
    ) -> [VoiceStudioTuningKey] {
        let drawable = VoiceStudioTuningPath.paths(for: engine)
        return studio.advanced.filter { key in
            key.leg == leg.rawValue && drawable.contains(key.key) && honoured(key, by: engine)
        }
    }

    /// Whether the held engine honours a key.
    public static func honoured(_ key: VoiceStudioTuningKey, by engine: VoiceStudioEngine) -> Bool {
        key.honouredBy == nil || entry(key, for: engine) != nil
    }

    /// The range a slider runs over for the held model: the model's own where `honouredBy`
    /// gives one, else the key's. Nil when neither says, which no published slider is.
    public static func range(_ key: VoiceStudioTuningKey, for engine: VoiceStudioEngine) -> VoiceStudioTuningRange? {
        let own = entry(key, for: engine)
        guard let min = own?.min ?? key.min, let max = own?.max ?? key.max else { return nil }
        return VoiceStudioTuningRange(
            min: min,
            max: max,
            step: key.step,
            start: key.start ?? own?.default ?? key.default ?? min,
            useDefaultLabel: own?.useDefaultLabel ?? key.useDefaultLabel
        )
    }

    /// A slider's raw value moved onto its step, clamped, and rounded off.
    ///
    /// ⚠️ A slider reports arithmetic on a `Double`, so 0.8 can arrive as 0.8000000000000002.
    /// Sent as is, the re-read would hold a different number from the screen and the save
    /// would read as failed.
    public static func snap(_ value: Double, to range: VoiceStudioTuningRange) -> Double {
        var stepped = value
        if let step = range.step, step > 0 {
            stepped = range.min + ((value - range.min) / step).rounded() * step
        }
        let clamped = Swift.min(Swift.max(stepped, range.min), range.max)
        return (clamped * snapScale).rounded() / snapScale
    }

    /// The mix with every tuning number its models do not honour dropped, every other one
    /// clamped into the held model's range, and the longest wait never below the shortest (the
    /// service raises it, and a raised value would read back as a failed save).
    public static func conform(_ mix: EngineMix, in studio: VoiceStudioResponse) -> EngineMix {
        var out = mix
        for key in studio.advanced {
            guard let path = VoiceStudioNumberPath(rawValue: key.key), let value = path.value(in: out) else {
                continue
            }
            let engine = VoiceStudioEngine.chained(out)
            var kept: Double?
            if honoured(key, by: engine) {
                kept = range(key, for: engine).map { Swift.min(Swift.max(value, $0.min), $0.max) } ?? value
            }
            out = path.setting(kept, in: out)
        }
        if let shortest = out.turn.minDelay, let longest = out.turn.maxDelay, longest < shortest {
            out.turn.maxDelay = shortest
        }
        return out
    }

    /// Key terms as typed, one per line: trimmed, cut to the longest a term may be,
    /// de-duplicated, and no more than the most there may be. ⛔ The service refuses the WHOLE
    /// mix past either limit (`invalid_engine_mix`).
    public static func parseKeyterms(_ text: String, key: VoiceStudioTuningKey) -> [String] {
        var seen = Set<String>()
        var terms: [String] = []
        for line in text.components(separatedBy: .newlines) {
            var term = line.trimmingCharacters(in: .whitespaces)
            if let longest = key.maxLength {
                term = String(term.prefix(longest))
            }
            guard !term.isEmpty, seen.insert(term).inserted else { continue }
            terms.append(term)
        }
        if let most = key.maxCount {
            return Array(terms.prefix(most))
        }
        return terms
    }

    /// The `honouredBy` row naming the held model for this key's leg.
    private static func entry(_ key: VoiceStudioTuningKey, for engine: VoiceStudioEngine) -> VoiceStudioHonouredBy? {
        let target = heldModel(for: key, engine: engine)
        return key.honouredBy?.first { $0.provider == target.provider && $0.model == target.model }
    }

    /// The provider and model a key's leg holds: the realtime model, or the chain's ear, brain
    /// or mouth. ⚠️ Turn-taking keys name the EAR (see the ⚠️ on this type).
    private static func heldModel(
        for key: VoiceStudioTuningKey,
        engine: VoiceStudioEngine
    ) -> (provider: String, model: String) {
        guard case let .chained(mix) = engine else {
            return ("", engine.realtimeModelId)
        }
        switch VoiceStudioLeg(rawValue: key.leg) {
        case .llm: return ("", mix.llm.model)
        case .tts: return (mix.tts.provider, mix.tts.model)
        default: return (mix.stt.provider, mix.stt.model)
        }
    }

    /// Four decimal places: finer than any published step, coarser than float noise.
    private static let snapScale = 10000.0
}
