@testable import DistrictData
import DistrictModel
import DistrictNetwork
import Foundation
import XCTest

/// Which tuning controls a leg shows, over what range, and how a mix is kept within them.
final class VoiceStudioTuningTests: XCTestCase {
    private typealias Tuning = VoiceStudioTuning

    private func key(_ path: String, in studio: VoiceStudioResponse) throws -> VoiceStudioTuningKey {
        try XCTUnwrap(studio.advanced.first { $0.key == path })
    }

    // MARK: - Which keys a leg shows

    /// ⛔ A KEY APPEARS ONLY FOR THE MODEL THAT HONOURS IT. Flux's end-of-turn keys show on a
    /// Flux ear and not on Nova-3, whose own end of turn is the voice agent's.
    func testTurnTakingShowsFluxKeysOnlyOnAFluxEar() throws {
        let studio = try VoiceStudioFixture.response()
        let flux = Tuning.keys(for: .turn, engine: .chained(VoiceStudioFixture.fluxChain), in: studio).map(\.key)
        XCTAssertTrue(flux.contains("engineMix.turn.eotThreshold"))
        XCTAssertTrue(flux.contains(VoiceStudioTuningPath.preemptiveTts))
        var nova = VoiceStudioFixture.fluxChain
        nova.stt.model = "nova-3-general"
        let detector = Tuning.keys(for: .turn, engine: .chained(nova), in: studio).map(\.key)
        XCTAssertFalse(detector.contains("engineMix.turn.eotThreshold"))
        XCTAssertTrue(detector.contains("engineMix.turn.minDelay"))
    }

    /// ⛔ A REALTIME ENGINE SHOWS PERSONA KEYS ONLY, and the voice style only on Gemini 2.5 Live.
    func testARealtimeEngineShowsItsTemperatureAndOnlyGeminiLive25ItsStyle() throws {
        let studio = try VoiceStudioFixture.response()
        let live25 = Tuning.keys(
            for: .realtime,
            engine: .realtime(modelId: VoiceStudioRules.geminiLive25, voice: "Puck"),
            in: studio
        )
        XCTAssertEqual(live25.map(\.key), [VoiceStudioTuningPath.realtimeTemperature, VoiceStudioTuningPath.voiceStyle])
        let live38 = Tuning.keys(
            for: .realtime,
            engine: .realtime(modelId: VoiceStudioRules.gemini38Live, voice: "Puck"),
            in: studio
        )
        XCTAssertEqual(live38.map(\.key), [VoiceStudioTuningPath.realtimeTemperature])
        // ⚠️ And no chain key is ever drawn on a realtime engine, whatever its leg says.
        XCTAssertEqual(
            Tuning.keys(for: .llm, engine: .realtime(modelId: VoiceStudioRules.geminiLive25, voice: ""), in: studio),
            []
        )
    }

    func testTheMouthsKeysFollowTheHeldModel() throws {
        let studio = try VoiceStudioFixture.response()
        var eleven = VoiceStudioFixture.fluxChain
        eleven.tts = EngineMixTts(provider: "elevenlabs", model: "eleven_flash_v2_5", voice: "EXAVITQu4vr4xnSDxMaL")
        XCTAssertEqual(
            Tuning.keys(for: .tts, engine: .chained(eleven), in: studio).map(\.key),
            ["engineMix.tts.stability", "engineMix.tts.expressivity"]
        )
        XCTAssertEqual(
            Tuning.keys(for: .tts, engine: .chained(VoiceStudioFixture.fluxChain), in: studio).map(\.key),
            ["engineMix.tts.speed"]
        )
        XCTAssertEqual(
            Tuning.keys(for: .llm, engine: .chained(VoiceStudioFixture.fluxChain), in: studio).map(\.key),
            ["engineMix.llm.thinking", "engineMix.llm.temperature"]
        )
    }

    // MARK: - Ranges

    func testARangeIsTheModelsOwnWhereItHasOneElseTheKeys() throws {
        let studio = try VoiceStudioFixture.response()
        let flux = VoiceStudioEngine.chained(VoiceStudioFixture.fluxChain)
        let threshold = try XCTUnwrap(Tuning.range(key("engineMix.turn.eotThreshold", in: studio), for: flux))
        XCTAssertEqual(threshold.min, 0.5)
        XCTAssertEqual(threshold.max, 0.9)
        XCTAssertEqual(threshold.start, 0.7)
        XCTAssertEqual(threshold.useDefaultLabel, "Use the default (0.70)")
        XCTAssertFalse(threshold.isWhole)

        let minDelay = try XCTUnwrap(Tuning.range(key("engineMix.turn.minDelay", in: studio), for: flux))
        XCTAssertEqual(minDelay.min, 0)
        XCTAssertEqual(minDelay.max, 1)
        XCTAssertEqual(minDelay.start, 0.3)

        let words = try XCTUnwrap(Tuning.range(key("engineMix.turn.interruption.minWords", in: studio), for: flux))
        XCTAssertTrue(words.isWhole)
    }

    /// A model the key does not name has no range when the key carries none of its own.
    func testAnUnhonouringModelHasNoRange() throws {
        let studio = try VoiceStudioFixture.response()
        var nova = VoiceStudioFixture.fluxChain
        nova.stt.model = "nova-3-general"
        let threshold = try key("engineMix.turn.eotThreshold", in: studio)
        XCTAssertNil(Tuning.range(threshold, for: .chained(nova)))
        XCTAssertFalse(Tuning.honoured(threshold, by: .chained(nova)))
        XCTAssertTrue(try Tuning.honoured(key("engineMix.turn.minDelay", in: studio), by: .chained(nova)))
    }

    /// ⚠️ A slider starts where the key says, else where the model's default is, else at its
    /// key's default, else at its minimum.
    func testASliderStartsAtTheFirstOfStartDefaultOrMinimum() throws {
        let studio = try VoiceStudioFixture.response {
            try $0.editEntry(["advanced"], where: ["key": "engineMix.turn.minDelay"]) { key in
                try key.set("start", .null)
                try key.set("default", .null)
            }
        }
        let range = try XCTUnwrap(
            Tuning.range(key("engineMix.turn.minDelay", in: studio), for: .chained(VoiceStudioFixture.fluxChain))
        )
        XCTAssertEqual(range.start, 0)
    }

    // MARK: - Snap and conform

    func testASliderValueSnapsToItsStepWithinItsRange() {
        let range = VoiceStudioTuningRange(min: 0.5, max: 0.9, step: 0.05, start: 0.7, useDefaultLabel: nil)
        XCTAssertEqual(Tuning.snap(0.800_000_011_920_929, to: range), 0.8)
        XCTAssertEqual(Tuning.snap(0.72, to: range), 0.7)
        XCTAssertEqual(Tuning.snap(2, to: range), 0.9)
        XCTAssertEqual(Tuning.snap(0, to: range), 0.5)
        let continuous = VoiceStudioTuningRange(min: 0, max: 1, step: nil, start: 0, useDefaultLabel: nil)
        XCTAssertEqual(Tuning.snap(0.123_456_78, to: continuous), 0.1235)
    }

    /// ⛔ A VALUE THE NEW MODEL DOES NOT HONOUR IS DROPPED; ONE IT DOES IS CLAMPED.
    func testConformDropsWhatTheModelIgnoresAndClampsTheRest() throws {
        let studio = try VoiceStudioFixture.response()
        var mix = VoiceStudioFixture.fluxChain
        mix.tts.speed = 3
        mix.tts.stability = 0.5
        mix.llm.temperature = 1.4
        let conformed = Tuning.conform(mix, in: studio)
        XCTAssertEqual(conformed.tts.speed, 1.5)
        XCTAssertNil(conformed.tts.stability)
        XCTAssertEqual(conformed.llm.temperature, 1.4)
    }

    /// ⚠️ THE LONGEST WAIT IS NEVER BELOW THE SHORTEST: the service raises it.
    func testConformRaisesTheLongestWaitToTheShortest() throws {
        let studio = try VoiceStudioFixture.response()
        var mix = VoiceStudioFixture.fluxChain
        mix.turn.minDelay = 0.9
        mix.turn.maxDelay = 0.6
        XCTAssertEqual(Tuning.conform(mix, in: studio).turn.maxDelay, 0.9)
        mix.turn.maxDelay = 1.2
        XCTAssertEqual(Tuning.conform(mix, in: studio).turn.maxDelay, 1.2)
    }

    /// A number whose key publishes no range at all is kept as it is.
    func testConformKeepsANumberWithNoRange() throws {
        let studio = try VoiceStudioFixture.response {
            try $0.editEntry(["advanced"], where: ["key": "engineMix.turn.minDelay"]) { key in
                try key.set("min", .null)
            }
        }
        var mix = VoiceStudioFixture.fluxChain
        mix.turn.minDelay = 7
        XCTAssertEqual(Tuning.conform(mix, in: studio).turn.minDelay, 7)
    }

    // MARK: - Key terms

    func testKeyTermsAreTrimmedCutDeDuplicatedAndCounted() throws {
        let studio = try VoiceStudioFixture.response()
        let key = try key(VoiceStudioTuningPath.keyterms, in: studio)
        XCTAssertEqual(
            Tuning.parseKeyterms("  Distronode \r\nDistrict AI\n\nDistronode\n", key: key),
            ["Distronode", "District AI"]
        )
        let long = String(repeating: "a", count: 150)
        XCTAssertEqual(Tuning.parseKeyterms(long, key: key), [String(repeating: "a", count: 100)])
        let many = (1 ... 60).map { "term\($0)" }.joined(separator: "\n")
        XCTAssertEqual(Tuning.parseKeyterms(many, key: key).count, 50)
    }

    func testKeyTermsWithNoPublishedLimitsAreOnlyTrimmed() throws {
        let studio = try VoiceStudioFixture.response {
            try $0.editEntry(["advanced"], where: ["key": VoiceStudioTuningPath.keyterms]) { key in
                try key.set("maxCount", .null)
                try key.set("maxLength", .null)
            }
        }
        let key = try key(VoiceStudioTuningPath.keyterms, in: studio)
        let many = (1 ... 60).map { "term\($0)" }.joined(separator: "\n")
        XCTAssertEqual(Tuning.parseKeyterms(many, key: key).count, 60)
    }

    // MARK: - Paths

    func testTheDrawablePathsDependOnTheEnginesKind() {
        XCTAssertEqual(
            VoiceStudioTuningPath.paths(for: .realtime(modelId: "x", voice: "y")),
            [VoiceStudioTuningPath.realtimeTemperature, VoiceStudioTuningPath.voiceStyle]
        )
        let chain = VoiceStudioTuningPath.paths(for: .chained(VoiceStudioFixture.fluxChain))
        XCTAssertEqual(chain.count, VoiceStudioNumberPath.allCases.count + VoiceStudioChoicePath.allCases.count + 2)
        XCTAssertTrue(chain.contains(VoiceStudioTuningPath.keyterms))
    }

    /// Every number path reads back what it wrote, and nil clears it.
    func testEveryNumberPathRoundTrips() {
        for path in VoiceStudioNumberPath.allCases {
            let set = path.setting(0.25, in: VoiceStudioFixture.fluxChain)
            XCTAssertEqual(path.value(in: set), 0.25, path.rawValue)
            XCTAssertNil(path.value(in: path.setting(nil, in: set)), path.rawValue)
        }
    }

    /// ⚠️ ALL FOUR INTERRUPTION FIELDS UNSET IS NO OBJECT AT ALL.
    func testAnEmptiedInterruptionIsNoObject() {
        let set = VoiceStudioNumberPath.interruptionMinWords.setting(2, in: VoiceStudioFixture.fluxChain)
        XCTAssertEqual(set.turn.interruption, EngineMixInterruption(minWords: 2))
        XCTAssertNil(VoiceStudioNumberPath.interruptionMinWords.setting(nil, in: set).turn.interruption)
    }

    func testEveryChoicePathRoundTrips() {
        let mix = VoiceStudioFixture.fluxChain
        XCTAssertEqual(VoiceStudioChoicePath.turnMode.value(in: mix), "auto")
        let fixed = VoiceStudioChoicePath.turnMode.setting("fixed", in: mix)
        XCTAssertEqual(fixed.turn.mode, "fixed")
        XCTAssertEqual(VoiceStudioChoicePath.turnMode.value(in: fixed), "fixed")
        XCTAssertNil(VoiceStudioChoicePath.turnMode.setting("auto", in: fixed).turn.mode)

        let resume = VoiceStudioChoicePath.interruptionResume
        XCTAssertEqual(resume.value(in: mix), "default")
        let on = resume.setting("on", in: mix)
        XCTAssertEqual(on.turn.interruption?.resume, true)
        XCTAssertEqual(resume.value(in: on), "on")
        let off = resume.setting("off", in: mix)
        XCTAssertEqual(resume.value(in: off), "off")
        XCTAssertNil(resume.setting("default", in: off).turn.interruption)

        let thinking = VoiceStudioChoicePath.llmThinking
        XCTAssertEqual(thinking.value(in: mix), "off")
        XCTAssertEqual(thinking.setting("dynamic", in: mix).llm.thinking, "dynamic")
    }
}
