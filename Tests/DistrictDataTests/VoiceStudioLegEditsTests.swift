@testable import DistrictData
import DistrictModel
import DistrictNetwork
import Foundation
import XCTest

/// Recipes and leg edits: every edit keeps the chain one the PATCH accepts.
final class VoiceStudioLegEditsTests: XCTestCase {
    private typealias Edits = VoiceStudioLegEdits
    private typealias Recipes = VoiceStudioRecipes

    // MARK: - Recipes

    func testATiersTilesFollowTheServicesOrder() throws {
        let studio = try VoiceStudioFixture.response()
        XCTAssertEqual(Recipes.tiles(studio, tier: Recipes.stable).map(\.id), studio.recipeIds)
        XCTAssertTrue(Recipes.tiles(studio, tier: Recipes.latest).allSatisfy { $0.tier == Recipes.latest })
        XCTAssertEqual(Recipes.tiles(studio, tier: "nope"), [])
    }

    /// ⛔ "YOUR CHAIN" IS THE SAVED CHAIN ITSELF, voice included.
    func testYourChainIsTheSavedChain() throws {
        let studio = try VoiceStudioFixture.response()
        let custom = try XCTUnwrap(Recipes.tiles(studio, tier: Recipes.stable).first { $0.id == Recipes.custom })
        let saved = VoiceStudioEngine.chained(VoiceStudioFixture.fluxChain).withVoice("aura-2-luna-en")
        let current = VoiceStudioEngine.realtime(modelId: VoiceStudioRules.geminiLive25, voice: "Puck")
        XCTAssertEqual(Recipes.applied(custom, saved: saved, current: current, studio: studio), saved)
    }

    /// ⚠️ With a realtime engine saved, "Your chain" is the region's starting chain instead.
    func testYourChainOverASavedRealtimeEngineIsTheServicesStartingChain() throws {
        let studio = try VoiceStudioFixture.response()
        let custom = try XCTUnwrap(Recipes.tiles(studio, tier: Recipes.stable).first { $0.id == Recipes.custom })
        let saved = VoiceStudioEngine.realtime(modelId: VoiceStudioRules.geminiLive25, voice: "Puck")
        XCTAssertEqual(
            Recipes.applied(custom, saved: saved, current: saved, studio: studio),
            VoiceStudioEngine(chain: custom.chain)
        )
    }

    /// ⛔ A RECIPE KEEPS THE VOICE THE CALLER HEARS WHERE THE NEW MOUTH HAS IT.
    func testARecipeKeepsTheHeldVoiceWhereItCan() throws {
        let studio = try VoiceStudioFixture.response()
        let inRegion = try XCTUnwrap(studio.recipes.first { $0.id == "in-region" && $0.tier == Recipes.stable })
        let current = VoiceStudioEngine.chained(VoiceStudioFixture.fluxChain).withVoice("aura-2-luna-en")
        let applied = Recipes.applied(inRegion, saved: current, current: current, studio: studio)
        XCTAssertEqual(applied.voice, "aura-2-luna-en")
        XCTAssertEqual(applied.mix?.stt.model, "nova-3-general")
    }

    func testARecipeWhoseMouthLacksTheVoiceUsesItsOwn() throws {
        let studio = try VoiceStudioFixture.response()
        let natural = try XCTUnwrap(studio.recipes.first { $0.id == "natural" && $0.tier == Recipes.stable })
        let current = VoiceStudioEngine.chained(VoiceStudioFixture.fluxChain)
        let applied = Recipes.applied(natural, saved: current, current: current, studio: studio)
        XCTAssertEqual(applied, VoiceStudioEngine(chain: natural.chain))
    }

    func testTheVoiceListsAreTheServices() throws {
        let studio = try VoiceStudioFixture.response()
        let realtime = Recipes.voices(for: .realtime(modelId: VoiceStudioRules.geminiLive25, voice: ""), in: studio)
        XCTAssertEqual(Recipes.voiceValues(realtime).first, "Puck")
        XCTAssertNil(Recipes.ttsVoices(provider: "deepgram", model: "nope", in: studio))
        XCTAssertEqual(Recipes.voiceValues(nil), [])
        let aura = Recipes.voices(for: .chained(VoiceStudioFixture.fluxChain), in: studio)
        XCTAssertEqual(Recipes.voiceOption("aura-2-asteria-en", in: aura)?.p50, 120)
        XCTAssertNil(Recipes.voiceOption("Puck", in: aura))
    }

    // MARK: - The ear

    func testANewEarVendorStartsOnItsFirstOfferedModelWithNoKeyTerms() throws {
        let studio = try VoiceStudioFixture.response()
        var mix = VoiceStudioFixture.fluxChain
        mix.stt.keyterms = ["Distronode"]
        let next = Edits.earVendor(mix, provider: "google-stt", bilingual: false, in: studio)
        XCTAssertEqual(next.stt, EngineMixStt(provider: "google-stt", model: "chirp_3", location: "us"))
    }

    /// ⚠️ A vendor whose only model is not offered still switches to it: the picker that
    /// listed the vendor already decided it may be chosen.
    func testAVendorWithNoOfferedModelStartsOnItsFirstModel() throws {
        let studio = try VoiceStudioFixture.response()
        let next = Edits.earVendor(VoiceStudioFixture.fluxChain, provider: "inworld", bilingual: false, in: studio)
        XCTAssertEqual(next.stt.model, "inworld/inworld-stt-1")
    }

    func testABilingualEarVendorSkipsModelsNotProvenOnBothLanguages() throws {
        let studio = try VoiceStudioFixture.response()
        let next = Edits.earVendor(VoiceStudioFixture.fluxChain, provider: "deepgram", bilingual: true, in: studio)
        XCTAssertEqual(next.stt.model, "nova-3-general")
        let unknown = Edits.earVendor(VoiceStudioFixture.fluxChain, provider: "nope", bilingual: false, in: studio)
        XCTAssertEqual(unknown, VoiceStudioFixture.fluxChain)
    }

    func testANewEarModelKeepsKeyTermsOnlyWhereTheyAreTaken() throws {
        var mix = VoiceStudioFixture.fluxChain
        mix.stt.keyterms = ["Distronode"]
        let studio = try VoiceStudioFixture.response()
        XCTAssertEqual(Edits.earModel(mix, model: "nova-3-general", in: studio).stt.keyterms, ["Distronode"])

        let refusing = try VoiceStudioFixture.response { document in
            try document.editEntry(["catalog", "stt"], where: ["model": "nova-3-general"]) { model in
                try model.set("keyterms", .bool(false))
            }
        }
        XCTAssertNil(Edits.earModel(mix, model: "nova-3-general", in: refusing).stt.keyterms)
        XCTAssertEqual(Edits.earModel(mix, model: "nope", in: studio), mix)
    }

    // MARK: - The brain

    /// A location the new brain does not offer falls back to its default; one it does is kept.
    func testANewBrainKeepsItsLocationOnlyWhereOffered() throws {
        let studio = try VoiceStudioFixture.response()
        var mix = VoiceStudioFixture.fluxChain
        mix.llm.location = "us-east4"
        mix.llm.temperature = 1.2
        let moved = Edits.brainModel(mix, model: "gemini-3.5-flash", in: studio)
        XCTAssertEqual(moved.llm.location, "northamerica-northeast1")
        XCTAssertEqual(moved.llm.thinking, "low")
        XCTAssertEqual(moved.llm.temperature, 1.2)

        var global = mix
        global.llm.model = "gemini-3.6-flash"
        global.llm.location = "global"
        XCTAssertEqual(Edits.brainModel(global, model: "gemini-3.8-flash", in: studio).llm.location, "global")
        XCTAssertEqual(Edits.brainModel(mix, model: "nope", in: studio), mix)
    }

    // MARK: - The mouth

    func testANewMouthVendorStartsOnItsModelsStartingVoice() throws {
        let studio = try VoiceStudioFixture.response()
        var mix = VoiceStudioFixture.fluxChain
        mix.tts.speed = 1.2
        let cartesia = Edits.voiceVendor(mix, provider: "cartesia", bilingual: false, in: studio)
        XCTAssertEqual(
            cartesia.tts,
            EngineMixTts(provider: "cartesia", model: "sonic-3", voice: "db6b0ed5-d5d3-463d-ae85-518a07d3c2b4")
        )
        let bilingual = Edits.voiceVendor(mix, provider: "elevenlabs", bilingual: true, in: studio)
        XCTAssertEqual(bilingual.tts.model, "eleven_multilingual_v2")
        XCTAssertEqual(Edits.voiceVendor(mix, provider: "nope", bilingual: false, in: studio), mix)
    }

    func testANewMouthModelKeepsTheVoiceOnlyWhereItHasIt() throws {
        let studio = try VoiceStudioFixture.response()
        let flux = Edits.voiceModel(VoiceStudioFixture.fluxChain, model: "flux-tts", in: studio)
        XCTAssertEqual(flux.tts.voice, "flux-alexis-en")

        var sonic = VoiceStudioFixture.fluxChain
        sonic.tts = EngineMixTts(provider: "cartesia", model: "sonic-3", voice: "47c38ca4-5f35-497b-b1a3-415245fb35e1")
        XCTAssertEqual(
            Edits.voiceModel(sonic, model: "sonic-3.6", in: studio).tts.voice,
            "47c38ca4-5f35-497b-b1a3-415245fb35e1"
        )
        XCTAssertEqual(Edits.voiceModel(sonic, model: "nope", in: studio), sonic)
    }

    func testAMouthLocationIsKeptWhereTheNewModelOffersIt() throws {
        let studio = try VoiceStudioFixture.response {
            try $0.editEntry(["catalog", "tts"], where: ["model": "chirp-3-hd"]) { model in
                try model.set("model", .string("chirp-3-hd-b"))
            }
        }
        var google = VoiceStudioFixture.fluxChain
        google.tts = EngineMixTts(provider: "google-tts", model: "chirp-3-hd", voice: "Achernar", location: "eu")
        XCTAssertEqual(Edits.voiceModel(google, model: "chirp-3-hd-b", in: studio).tts.location, "eu")
    }

    // MARK: - Locations and realtime

    func testALocationIsSetOnTheLegItBelongsTo() {
        let mix = VoiceStudioFixture.fluxChain
        XCTAssertEqual(Edits.location(mix, leg: .stt, location: "eu").stt.location, "eu")
        XCTAssertEqual(Edits.location(mix, leg: .llm, location: "us-east4").llm.location, "us-east4")
        XCTAssertEqual(Edits.location(mix, leg: .tts, location: "eu").tts.location, "eu")
        XCTAssertEqual(Edits.location(mix, leg: .turn, location: "eu"), mix)
        XCTAssertEqual(Edits.location(mix, leg: .realtime, location: "eu"), mix)
    }

    func testAnotherRealtimeModelKeepsTheVoiceItSpeaks() throws {
        let studio = try VoiceStudioFixture.response()
        XCTAssertEqual(
            Edits.realtimeModel(voice: "Kore", model: VoiceStudioRules.gemini38Live, in: studio),
            .realtime(modelId: VoiceStudioRules.gemini38Live, voice: "Kore")
        )
        XCTAssertEqual(
            Edits.realtimeModel(voice: "aura-2-asteria-en", model: VoiceStudioRules.gemini38Live, in: studio),
            .realtime(modelId: VoiceStudioRules.gemini38Live, voice: "Puck")
        )
        XCTAssertEqual(
            Edits.realtimeModel(voice: "Kore", model: "nope", in: studio),
            .realtime(modelId: "nope", voice: "Kore")
        )
    }
}
