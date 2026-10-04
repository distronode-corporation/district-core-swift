@testable import DistrictData
import DistrictModel
import DistrictNetwork
import Foundation
import XCTest

/// The Studio's held state and every transition a screen routes into it.
final class VoiceStudioSessionTests: XCTestCase {
    private func session() throws -> VoiceStudioSession {
        try VoiceStudioSession(studio: VoiceStudioFixture.response())
    }

    func testItOpensOnTheSavedPersonaWithNothingPending() throws {
        let session = try session()
        XCTAssertEqual(session.held.engine, .chained(VoiceStudioFixture.fluxChain))
        XCTAssertEqual(session.savedEngine, session.held.engine)
        XCTAssertEqual(session.tier, "stable")
        XCTAssertEqual(session.baseRecipe, "fastest")
        XCTAssertEqual(session.leg, .stt)
        XCTAssertEqual(session.heldFields, session.savedFields)
        XCTAssertEqual(session.pending, [])
        XCTAssertFalse(session.isDirty)
        XCTAssertEqual(session.changes, 0)
        XCTAssertEqual(session.tiles.map(\.id), session.studio.recipeIds)
        XCTAssertEqual(session.baseName, "Fastest")
    }

    func testAVoiceEditIsPendingAndCounted() throws {
        let edited = try session().withHeld(
            VoiceStudioState(
                engine: .chained(VoiceStudioFixture.fluxChain).withVoice("aura-2-luna-en"),
                realtimeTemperature: 0.7,
                bilingual: false,
                voiceStyle: nil
            )
        )
        XCTAssertEqual(edited.pending, [.voice])
        XCTAssertTrue(edited.isDirty)
        XCTAssertEqual(edited.changes, 1)
        XCTAssertEqual(edited.withReset().held.engine, edited.baseEngine)
        XCTAssertFalse(edited.withReset().isDirty)
    }

    /// ⛔ A RECIPE APPLIES ITS ENGINE AND ITS BILINGUAL FLAG, and becomes the new base.
    func testARecipeAppliesItsEngineAndBilingualFlag() throws {
        let bilingual = try session().withRecipe("bilingual")
        XCTAssertEqual(bilingual.held.engine, .realtime(modelId: VoiceStudioRules.gemini38Live, voice: "Puck"))
        XCTAssertTrue(bilingual.held.bilingual)
        XCTAssertEqual(bilingual.baseRecipe, "bilingual")
        XCTAssertEqual(bilingual.leg, .realtime)
        XCTAssertEqual(bilingual.changes, 0)
        XCTAssertEqual(bilingual.pending, [.modelId, .voice, .temperature, .bilingual])

        let unknown = try session()
        XCTAssertEqual(unknown.withRecipe("nope"), unknown)
    }

    /// ⚠️ A TIER SWITCH RE-APPLIES THE RECIPE ON THE OTHER TIER; "Your chain" is not a tier's.
    func testATierSwitchReappliesTheRecipe() throws {
        let latest = try session().withTier("latest")
        XCTAssertEqual(latest.tier, "latest")
        XCTAssertEqual(latest.held.engine.mix?.stt.model, "flux-general-multi")
        XCTAssertEqual(latest.baseName, "Fastest")

        let custom = try session().withRecipe("custom").withTier("latest")
        XCTAssertEqual(custom.tier, "latest")
        XCTAssertEqual(custom.held.engine, .chained(VoiceStudioFixture.fluxChain))
        XCTAssertEqual(custom.baseRecipe, "custom")
    }

    func testABaseNameTheTierLacksIsEmpty() throws {
        let studio = try VoiceStudioFixture.response {
            try $0.edit(["current", "recipeId"]) { $0 = .string("gone") }
        }
        XCTAssertEqual(VoiceStudioSession(studio: studio).baseName, "")
    }

    func testAChainEditGoesThroughTheMix() throws {
        let edited = try session().withMix { mix in
            var next = mix
            next.llm.thinking = "dynamic"
            return next
        }
        XCTAssertEqual(edited.held.engine.mix?.llm.thinking, "dynamic")
        XCTAssertEqual(edited.pending, [.modelId, .engineMix])
        XCTAssertEqual(edited.heldFields.modelId, VoiceStudioRules.customPipeline)
    }

    func testAMixEditOnARealtimeEngineIsANoOp() throws {
        let realtime = try session().withRecipe("realtime")
        XCTAssertEqual(realtime.withMix { _ in VoiceStudioFixture.fluxChain }, realtime)
    }

    /// ⚠️ A realtime engine has one block; a chain opens on the leg it was on, or the ear.
    func testTheLegFollowsTheEnginesKind() throws {
        let chain = try session()
        XCTAssertEqual(chain.withLeg(.tts).leg, .tts)
        XCTAssertEqual(chain.withLeg(.realtime).leg, .stt)
        let realtime = chain.withLeg(.llm).withRecipe("realtime")
        XCTAssertEqual(realtime.leg, .realtime)
        XCTAssertEqual(realtime.withLeg(.llm).leg, .realtime)
        XCTAssertEqual(realtime.withRecipe("fastest").leg, .stt)
    }
}
