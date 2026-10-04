import ContractGateSupport
import DistrictModel
import Foundation

// The native Voice Studio's read, `district-voice-studio.json`, and the one gate in this
// corpus whose null permissions are written per FIELD rather than per row.
//
// ⛔ WHY THIS FIXTURE DOES NOT GO THROUGH `allowedExplicitNulls`. The Studio's contract is
// "every object of one kind carries the same keys, and a value that does not apply is null,
// never absent", over 160 KB: 1,126 explicit nulls, 589 of them the `clip` and `p50` of a
// voice nobody rendered or measured. Writing each as an exact path would bury the decisions in
// row numbers and move `ContractManifest.expectedAllowedNullPaths` by a thousand on every
// regeneration. So the permission here is a FIELD of a KIND (`$.voices[*].groups[*].options[*]
// .p50`), each one a nullable property of the DTO, and the rest of the gate is unchanged: the
// fixture is decoded, re-encoded and compared key by key, a null in a field this list does not
// name still fails, and a field the list names that holds no null anywhere fails too (a
// permission nobody uses is a permission nobody checked).
//
// ⚠️ THE WILDCARD IS ONLY EVER AN ARRAY INDEX. Every object key stays literal, so a new nullable
// key the service adds is a red gate here and a decision in this file.

extension ImplementedFixtures {
    // MARK: - The Voice Studio

    static var voiceStudio: [ImplementedFixture] {
        [
            ImplementedFixture(name: VoiceStudioNulls.fixture, type: String(describing: VoiceStudioResponse.self)) {
                let data = try ContractFixtures.read(VoiceStudioNulls.fixture)
                let nulls = try VoiceStudioNulls.permitted(in: data)
                _ = try StrictDecodeVerifier.verify(
                    name: VoiceStudioNulls.fixture,
                    json: data,
                    as: VoiceStudioResponse.self,
                    allowingExplicitNulls: nulls
                )
            },
        ]
    }
}

/// The fields of `district-voice-studio.json` that may hold an explicit null, by kind.
enum VoiceStudioNulls {
    static let fixture = "district-voice-studio.json"

    /// ⚠️ THE ALWAYS-PRESENT NULLABLE KEYS OF AN ENGINE MIX, which appear wherever a mix does.
    /// The absent-when-unset keys (`keyterms`, `stability`, ...) are not here: the service leaves
    /// them out rather than writing null.
    static let mixFields = [
        "llm.temperature", "stt.language", "stt.location", "tts.location", "tts.speed",
        "turn.eotThreshold", "turn.maxDelay", "turn.minDelay",
    ]

    /// Every place a mix appears.
    static let mixes = [
        "$.catalog.presets[*].engineMix", "$.current.chain.engineMix",
        "$.recipes[*].chain.engineMix", "$.recipes[*].save.engineMix",
    ]

    /// Each entry names one nullable property of the DTO and why it is null.
    static let fields: Set<String> = Set(mixes.flatMap { mix in mixFields.map { "\(mix).\($0)" } }).union([
        // A tuning key's range, start, default, options, limits and models: each one null
        // where that kind of control has none (a checkbox has no range, a slider no options).
        "$.advanced[*].default", "$.advanced[*].description", "$.advanced[*].honouredBy",
        "$.advanced[*].honouredBy[*].default", "$.advanced[*].honouredBy[*].max",
        "$.advanced[*].honouredBy[*].min", "$.advanced[*].honouredBy[*].useDefaultLabel",
        "$.advanced[*].max", "$.advanced[*].maxCount", "$.advanced[*].maxLength", "$.advanced[*].min",
        "$.advanced[*].options", "$.advanced[*].start", "$.advanced[*].step", "$.advanced[*].useDefaultLabel",
        // ⛔ A LATENCY OF NULL IS "NOT MEASURED YET", AND A LAB PROBE HAS NO SAMPLE COUNT.
        "$.catalog.llm[*].latency", "$.catalog.stt[*].latency", "$.catalog.tts[*].latency",
        "$.catalog.realtime[*].latency.samples", "$.catalog.stt[*].latency.samples",
        "$.catalog.tts[*].latency.samples",
        "$.current.chain.blocks[*].latency.samples", "$.recipes[*].chain.blocks[*].latency",
        "$.recipes[*].chain.blocks[*].latency.samples",
        // A vendor endpoint has no location; only a Preview model has a note.
        "$.catalog.stt[*].defaultLocation", "$.catalog.tts[*].defaultLocation", "$.catalog.realtime[*].note",
        "$.current.chain.blocks[*].note", "$.recipes[*].chain.blocks[*].note", "$.recipes[*].note",
        // ⚠️ The turn detector runs in the voice agent, so its block is neither in nor out of region.
        "$.recipes[*].chain.blocks[*].inRegion",
        // ⛔ A CHAIN HAS NO REALTIME MODEL AND A REALTIME ENGINE NO MIX: exactly one of the two.
        "$.current.chain.realtimeModelId", "$.recipes[*].chain.realtimeModelId", "$.recipes[*].chain.engineMix",
        // The saved persona: no stored mix, no voice style chosen, and the save body's keys that
        // do not apply to its engine (null is "do not send").
        "$.current.engineMix", "$.current.voiceStyle",
        "$.current.fields.bilingual", "$.current.fields.engineMix", "$.current.fields.temperature",
        "$.current.fields.voiceStyle",
        "$.recipes[*].save.bilingual", "$.recipes[*].save.engineMix", "$.recipes[*].save.preemptiveTts",
        "$.recipes[*].save.temperature", "$.recipes[*].save.voiceStyle",
        // ⛔ A METER WITH NOTHING MEASURED HAS NO NUMBER, and a stage with no median has none either.
        "$.latency.note", "$.recipes[*].timeToFirstWord.ms", "$.recipes[*].timeToFirstWord.note",
        "$.recipes[*].timeToFirstWord.stages[*].ms", "$.recipes[*].timeToFirstWord.stages[*].samples",
        // A voice nobody rendered a sample of, or measured in this region.
        "$.voices[*].groups[*].options[*].clip", "$.voices[*].groups[*].options[*].p50",
    ])

    struct Unpermitted: Error, CustomStringConvertible {
        let paths: [String]

        var description: String {
            "district-voice-studio.json: explicit null at a field no entry names: \(paths.joined(separator: ", "))"
        }
    }

    struct Unused: Error, CustomStringConvertible {
        let fields: [String]

        var description: String {
            "district-voice-studio.json: permitted null fields that hold no null: \(fields.joined(separator: ", "))"
        }
    }

    /// Every exact null path in the fixture, once each has been checked against ``fields``.
    static func permitted(in data: Data) throws -> Set<String> {
        var paths: [String] = []
        let document = try JSONSerialization.jsonObject(with: data)
        collect(document, at: "$", into: &paths)
        let unpermitted = paths.filter { !fields.contains(kind(of: $0)) }
        guard unpermitted.isEmpty else { throw Unpermitted(paths: unpermitted) }
        let unused = fields.subtracting(paths.map(kind(of:)))
        guard unused.isEmpty else { throw Unused(fields: unused.sorted()) }
        return Set(paths)
    }

    /// `$.voices[3].groups[0].options[7].p50` becomes `$.voices[*].groups[*].options[*].p50`.
    static func kind(of path: String) -> String {
        path.replacingOccurrences(of: #"\[\d+\]"#, with: "[*]", options: .regularExpression)
    }

    private static func collect(_ value: Any, at path: String, into paths: inout [String]) {
        if value is NSNull {
            paths.append(path)
        } else if let object = value as? [String: Any] {
            for (key, child) in object {
                collect(child, at: "\(path).\(key)", into: &paths)
            }
        } else if let array = value as? [Any] {
            for (index, child) in array.enumerated() {
                collect(child, at: "\(path)[\(index)]", into: &paths)
            }
        }
    }
}
