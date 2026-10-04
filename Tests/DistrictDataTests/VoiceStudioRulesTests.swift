@testable import DistrictData
import DistrictModel
import DistrictNetwork
import Foundation
import XCTest

/// What a Studio state saves as, which keys a save sends, whether a re-read agrees, and how
/// far an edit is from its recipe: the web Studio's `studioModel.ts`, ported.
final class VoiceStudioRulesTests: XCTestCase {
    private typealias Rules = VoiceStudioRules

    // MARK: - The engine and the state

    func testAChainedChainIsHeldAsItsMix() throws {
        let studio = try VoiceStudioFixture.response()
        let engine = VoiceStudioEngine(chain: studio.current.chain)
        XCTAssertEqual(engine, .chained(VoiceStudioFixture.fluxChain))
        XCTAssertEqual(engine.voice, "aura-2-asteria-en")
        XCTAssertEqual(engine.mix, VoiceStudioFixture.fluxChain)
        XCTAssertEqual(engine.realtimeModelId, "")
    }

    func testARealtimeChainIsHeldAsItsModelAndVoice() throws {
        let studio = try VoiceStudioFixture.response()
        let recipe = try XCTUnwrap(studio.recipes.first { $0.id == "realtime" && $0.tier == "stable" })
        let engine = VoiceStudioEngine(chain: recipe.chain)
        XCTAssertEqual(engine, .realtime(modelId: Rules.geminiLive25, voice: "Puck"))
        XCTAssertEqual(engine.voice, "Puck")
        XCTAssertNil(engine.mix)
        XCTAssertEqual(engine.realtimeModelId, Rules.geminiLive25)
    }

    /// ⚠️ "HAS A MIX" DECIDES THE KIND, so a realtime chain whose model id the service left out
    /// is still realtime, on an empty id the pickers will not offer.
    func testARealtimeChainWithNoModelIdIsHeldOnAnEmptyOne() throws {
        let studio = try VoiceStudioFixture.response { document in
            try document.editEntry(["recipes"], where: ["id": "realtime"]) { recipe in
                try recipe.edit(["chain", "realtimeModelId"]) { $0 = .null }
            }
        }
        let recipe = try XCTUnwrap(studio.recipes.first { $0.id == "realtime" })
        XCTAssertEqual(VoiceStudioEngine(chain: recipe.chain), .realtime(modelId: "", voice: "Puck"))
    }

    func testAVoiceChangeKeepsTheKindAndEverythingElse() {
        let chain = VoiceStudioEngine.chained(VoiceStudioFixture.fluxChain).withVoice("aura-2-luna-en")
        XCTAssertEqual(chain.mix?.tts.voice, "aura-2-luna-en")
        XCTAssertEqual(chain.mix?.stt, VoiceStudioFixture.fluxChain.stt)
        let realtime = VoiceStudioEngine.realtime(modelId: Rules.geminiLive25, voice: "Puck").withVoice("Kore")
        XCTAssertEqual(realtime, .realtime(modelId: Rules.geminiLive25, voice: "Kore"))
    }

    func testTheStateOpensOnWhatTheServiceSaysIsSaved() throws {
        let studio = try VoiceStudioFixture.response()
        let state = VoiceStudioState(current: studio.current)
        XCTAssertEqual(state.engine, .chained(VoiceStudioFixture.fluxChain))
        XCTAssertEqual(state.realtimeTemperature, studio.current.temperature)
        XCTAssertFalse(state.bilingual)
        XCTAssertNil(state.voiceStyle)
    }

    // MARK: - Bilingual

    func testOnlyEnglishAndFrenchHaveABilingualPair() {
        XCTAssertTrue(Rules.bilingualPair("en-US"))
        XCTAssertTrue(Rules.bilingualPair("fr-CA"))
        XCTAssertTrue(Rules.bilingualPair("FR"))
        XCTAssertFalse(Rules.bilingualPair("es-ES"))
        XCTAssertFalse(Rules.bilingualPair(""))
    }

    func testBilingualAppliesOnlyToTheTwoEnginesThatCarryIt() {
        XCTAssertTrue(Rules.bilingualAvailable(modelId: Rules.customPipeline, language: "en-US"))
        XCTAssertTrue(Rules.bilingualAvailable(modelId: Rules.gemini38Live, language: "fr-CA"))
        XCTAssertFalse(Rules.bilingualAvailable(modelId: Rules.geminiLive25, language: "en-US"))
        XCTAssertFalse(Rules.bilingualAvailable(modelId: Rules.customPipeline, language: "es-ES"))
    }

    // MARK: - The preset rule

    /// ⛔ A CHAIN EQUAL TO A PRESET SAVES AS THAT FIXED ENGINE, whatever voice it speaks.
    func testAChainEqualToAPresetSavesAsThePresetWhateverItsVoice() throws {
        let presets = try VoiceStudioFixture.response().catalog.presets
        var mix = VoiceStudioFixture.fluxChain
        XCTAssertEqual(Rules.canonicalModelId(mix, presets: presets), "deepgram-pipeline")
        mix.tts.voice = "aura-2-luna-en"
        mix.preemptiveTts = true
        mix.userAwayTimeout = 30
        XCTAssertEqual(Rules.canonicalModelId(mix, presets: presets), "deepgram-pipeline")
    }

    func testAChainThatMatchesNoPresetIsCustom() throws {
        let presets = try VoiceStudioFixture.response().catalog.presets
        var mix = VoiceStudioFixture.fluxChain
        mix.llm.thinking = "dynamic"
        XCTAssertEqual(Rules.canonicalModelId(mix, presets: presets), Rules.customPipeline)
    }

    /// ⛔ ANY STUDIO TUNING KEY MAKES IT CUSTOM: a fixed engine cannot carry one.
    func testEveryTuningKeyMakesAPresetChainCustom() throws {
        let presets = try VoiceStudioFixture.response().catalog.presets
        let tunings: [(inout EngineMix) -> Void] = [
            { $0.stt.keyterms = ["Distronode"] },
            { $0.tts.stability = 0.5 },
            { $0.tts.expressivity = 0.2 },
            { $0.turn.mode = "fixed" },
            { $0.turn.eagerEotThreshold = 0.4 },
            { $0.turn.eotTimeoutMs = 3000 },
            { $0.turn.interruption = EngineMixInterruption(minWords: 2) },
        ]
        for tune in tunings {
            var mix = VoiceStudioFixture.fluxChain
            tune(&mix)
            XCTAssertEqual(Rules.canonicalModelId(mix, presets: presets), Rules.customPipeline)
        }
    }

    // MARK: - What a state saves as

    func testAPresetChainSavesItsIdVoiceAndSpeakSoonerAndNoMix() throws {
        let studio = try VoiceStudioFixture.response()
        let fields = Rules.fields(
            of: VoiceStudioState(current: studio.current),
            presets: studio.catalog.presets,
            language: "en-US"
        )
        XCTAssertEqual(fields, studio.current.fields)
        XCTAssertEqual(
            fields,
            VoiceStudioFields(modelId: "deepgram-pipeline", voice: "aura-2-asteria-en", preemptiveTts: false)
        )
    }

    func testACustomChainSavesItsMixAndABilingualFlag() throws {
        let studio = try VoiceStudioFixture.response()
        var mix = VoiceStudioFixture.fluxChain
        mix.llm.thinking = "dynamic"
        let state = VoiceStudioState(engine: .chained(mix), realtimeTemperature: 0.7, bilingual: false, voiceStyle: "x")
        let fields = Rules.fields(of: state, presets: studio.catalog.presets, language: "en-US")
        XCTAssertEqual(fields.modelId, Rules.customPipeline)
        XCTAssertEqual(fields.engineMix, mix)
        XCTAssertEqual(fields.bilingual, false)
        XCTAssertNil(fields.temperature)
        XCTAssertNil(fields.voiceStyle)
    }

    /// ⛔ A BILINGUAL CHAIN IS THE CUSTOM ENGINE BY DEFINITION, even when it equals a preset.
    func testABilingualChainIsCustomEvenWhenItEqualsAPreset() throws {
        let studio = try VoiceStudioFixture.response()
        let state = VoiceStudioState(
            engine: .chained(VoiceStudioFixture.fluxChain),
            realtimeTemperature: 0.7,
            bilingual: true,
            voiceStyle: nil
        )
        let fields = Rules.fields(of: state, presets: studio.catalog.presets, language: "fr-CA")
        XCTAssertEqual(fields.modelId, Rules.customPipeline)
        XCTAssertEqual(fields.bilingual, true)
        // ⚠️ And for a language with no pair it is not bilingual at all.
        let spanish = Rules.fields(of: state, presets: studio.catalog.presets, language: "es-ES")
        XCTAssertEqual(spanish.modelId, "deepgram-pipeline")
        XCTAssertNil(spanish.bilingual)
    }

    func testARealtimeEngineSavesItsTemperatureAndOnlyGeminiLive25ItsStyle() throws {
        let presets = try VoiceStudioFixture.response().catalog.presets
        let live25 = VoiceStudioState(
            engine: .realtime(modelId: Rules.geminiLive25, voice: "Kore"),
            realtimeTemperature: 0.4,
            bilingual: false,
            voiceStyle: "en-US-News-K"
        )
        XCTAssertEqual(
            Rules.fields(of: live25, presets: presets, language: "en-US"),
            VoiceStudioFields(modelId: Rules.geminiLive25, voice: "Kore", temperature: 0.4, voiceStyle: "en-US-News-K")
        )
        var live38 = live25
        live38.engine = .realtime(modelId: Rules.gemini38Live, voice: "Kore")
        live38.bilingual = true
        XCTAssertEqual(
            Rules.fields(of: live38, presets: presets, language: "en-US"),
            VoiceStudioFields(modelId: Rules.gemini38Live, voice: "Kore", temperature: 0.4, bilingual: true)
        )
    }

    // MARK: - What a save sends

    func testNothingIsSentWhenNothingChanged() throws {
        let fields = try VoiceStudioFixture.response().current.fields
        XCTAssertEqual(Rules.changedKeys(saved: fields, current: fields), [])
    }

    func testAVoiceChangeSendsTheVoiceAlone() throws {
        let saved = try VoiceStudioFixture.response().current.fields
        var current = saved
        current.voice = "aura-2-luna-en"
        XCTAssertEqual(Rules.changedKeys(saved: saved, current: current), [.voice])
    }

    /// ⛔ THE ENGINE ID AND THE MIX TRAVEL TOGETHER.
    func testAMixChangeSendsTheEngineIdWithIt() throws {
        let saved = try VoiceStudioFixture.response().current.fields
        var custom = VoiceStudioFixture.fluxChain
        custom.llm.thinking = "dynamic"
        var current = saved
        current.modelId = Rules.customPipeline
        current.engineMix = custom
        XCTAssertEqual(Rules.changedKeys(saved: saved, current: current), [.modelId, .engineMix])

        // A mix edit that keeps the same custom id still names the id.
        var later = current
        later.engineMix?.llm.temperature = 1.2
        XCTAssertEqual(Rules.changedKeys(saved: current, current: later), [.modelId, .engineMix])

        // Back to a preset: the id goes, and there is no mix to send.
        XCTAssertEqual(Rules.changedKeys(saved: current, current: saved), [.modelId])
    }

    /// ⚠️ AN ABSENT BILINGUAL FLAG AND `false` SAY THE SAME THING.
    func testAnAbsentBilingualFlagIsFalse() throws {
        let saved = try VoiceStudioFixture.response().current.fields
        var current = saved
        current.bilingual = false
        XCTAssertEqual(Rules.changedKeys(saved: saved, current: current), [])
        current.bilingual = true
        XCTAssertEqual(Rules.changedKeys(saved: saved, current: current), [.bilingual])
    }

    func testEveryKeyIsComparedOnItsOwn() throws {
        let saved = VoiceStudioFields(modelId: Rules.geminiLive25, voice: "Puck", temperature: 0.7)
        var current = saved
        current.temperature = 0.5
        current.voiceStyle = "en-US-News-K"
        current.preemptiveTts = true
        XCTAssertEqual(Rules.changedKeys(saved: saved, current: current), [.temperature, .voiceStyle, .preemptiveTts])
    }

    // MARK: - Whether it landed

    func testASaveLandedWhenTheReReadHoldsWhatWasSent() {
        let sent = VoiceStudioFields(modelId: Rules.geminiLive25, voice: "Kore", temperature: 0.4)
        var reread = sent
        reread.temperature = 0.400_000_000_1
        XCTAssertTrue(Rules.landed(sent: sent, keys: [.voice, .temperature], reread: reread))
    }

    /// ⛔ THE PATCH ANSWERS 200 FOR A VALUE IT IGNORED; ONLY THE RE-READ SAYS SO.
    func testASaveDidNotLandWhenTheReReadDisagrees() {
        let sent = VoiceStudioFields(modelId: "unknown-engine", voice: "Kore", temperature: 0.4)
        var reread = sent
        reread.modelId = "deepgram-pipeline"
        XCTAssertFalse(Rules.landed(sent: sent, keys: [.modelId], reread: reread))
        reread = sent
        reread.temperature = 0.7
        XCTAssertFalse(Rules.landed(sent: sent, keys: [.temperature], reread: reread))
        reread.temperature = nil
        XCTAssertFalse(Rules.landed(sent: sent, keys: [.temperature], reread: reread))
    }

    // MARK: - How far from the recipe

    func testTheChangeCountIsALeafCount() {
        let base = VoiceStudioEngine.chained(VoiceStudioFixture.fluxChain)
        XCTAssertEqual(Rules.countChanges(base: base, current: base), 0)
        XCTAssertEqual(Rules.countChanges(base: base, current: base.withVoice("aura-2-luna-en")), 1)

        var tuned = VoiceStudioFixture.fluxChain
        tuned.llm.temperature = 1.2
        tuned.stt.keyterms = ["Distronode"]
        // ⚠️ A null leaf that gains a value is one change; an absent key that appears is one more.
        XCTAssertEqual(Rules.countChanges(base: base, current: .chained(tuned)), 2)
    }

    func testAChainAndARealtimeEngineDifferInEveryLeaf() {
        let chain = VoiceStudioEngine.chained(VoiceStudioFixture.fluxChain)
        let realtime = VoiceStudioEngine.realtime(modelId: Rules.geminiLive25, voice: "Puck")
        // kind, modelId and voice on one side; kind and every mix leaf on the other.
        XCTAssertEqual(Rules.countChanges(base: chain, current: realtime), 21)
        let kore = VoiceStudioEngine.realtime(modelId: Rules.geminiLive25, voice: "Kore")
        XCTAssertEqual(Rules.countChanges(base: realtime, current: kore), 1)
    }
}
