import ContractGateSupport
@testable import DistrictData
import DistrictModel
import DistrictNetwork
import Foundation
import XCTest

/// A chain moved to models that speak a new persona language, and the read, save and read
/// that carry it out.
final class VoiceStudioRefitTests: XCTestCase {
    private typealias Refit = VoiceStudioRefit

    /// A catalogue model, by leg (`stt` or `tts`), that no longer speaks the language.
    private struct Unfit {
        let leg: String
        let provider: String
        let model: String

        static func ear(_ provider: String, _ model: String) -> Unfit {
            Unfit(leg: "stt", provider: provider, model: model)
        }

        static func voice(_ provider: String, _ model: String) -> Unfit {
            Unfit(leg: "tts", provider: provider, model: model)
        }
    }

    private var flux: EngineMix {
        VoiceStudioFixture.fluxChain
    }

    /// The fixture's document with each `unfit` model no longer speaking the language.
    private func document(
        unfit models: [Unfit] = [],
        _ edit: (inout JSONValue) throws -> Void = { _ in }
    ) throws -> JSONValue {
        var read = try XCTUnwrap(JSONWire.decode(ContractFixtures.read(VoiceStudioFixture.name)))
        for entry in models {
            let match = ["provider": entry.provider, "model": entry.model]
            try read.editEntry(["catalog", entry.leg], where: match) {
                try $0.set("forLanguage", .bool(false))
            }
        }
        try edit(&read)
        return read
    }

    private func studio(unfit models: [Unfit] = []) throws -> VoiceStudioResponse {
        try JSONDecoder().decode(VoiceStudioResponse.self, from: JSONWire.encode(document(unfit: models)))
    }

    /// Every model of a leg.
    private func allUnfit(_ leg: String) throws -> [Unfit] {
        let catalog = try VoiceStudioFixture.response().catalog
        return leg == "stt"
            ? catalog.stt.map { Unfit.ear($0.provider, $0.model) }
            : catalog.tts.map { Unfit.voice($0.provider, $0.model) }
    }

    // MARK: - The ear

    func testAChainThatFitsComesBackUnchanged() throws {
        XCTAssertEqual(try Refit.refit(flux, in: studio()), flux)
    }

    /// The same vendor's ear that takes turns the same way comes first, key terms kept where
    /// the new ear takes them.
    func testAnEarMovesToTheSameVendorTakingTurnsTheSameWay() throws {
        var mix = flux
        mix.stt.keyterms = ["Acme"]
        let moved = try XCTUnwrap(Refit.refit(mix, in: studio(unfit: [.ear("deepgram", "flux-general-en")])))
        let multi = EngineMixStt(provider: "deepgram", model: "flux-general-multi", keyterms: ["Acme"])
        XCTAssertEqual(moved.stt, multi)
        XCTAssertEqual(moved.llm, mix.llm)
        XCTAssertEqual(moved.tts, mix.tts)
    }

    func testThenTheSameVendorsOtherEars() throws {
        let unfit: [Unfit] = [.ear("deepgram", "flux-general-en"), .ear("deepgram", "flux-general-multi")]
        let moved = try XCTUnwrap(Refit.refit(flux, in: studio(unfit: unfit)))
        XCTAssertEqual(moved.stt.model, "nova-3-general")
    }

    /// Then any vendor's, in catalogue order, and key terms go where the new ear takes none.
    func testThenAnyVendorsAndKeyTermsGoWhereNotTaken() throws {
        var mix = flux
        mix.stt.keyterms = ["Acme"]
        let unfit = try allUnfit("stt").filter { $0.provider == "deepgram" || $0.provider == "assemblyai" }
        let moved = try XCTUnwrap(Refit.refit(mix, in: studio(unfit: unfit)))
        XCTAssertEqual(moved.stt, EngineMixStt(provider: "aws-transcribe", model: "transcribe-streaming"))
    }

    /// An ear the catalogue no longer lists is moved as one that does not take turns, and its
    /// location is kept where the new ear offers it.
    func testAnUnlistedEarMovesAndKeepsAnOfferedLocation() throws {
        var mix = flux
        mix.stt = EngineMixStt(provider: "google-stt", model: "chirp_2", location: "eu")
        let moved = try XCTUnwrap(Refit.refit(mix, in: studio()))
        XCTAssertEqual(moved.stt, EngineMixStt(provider: "google-stt", model: "chirp_3", location: "eu"))
        mix.stt.location = "asia"
        XCTAssertEqual(try XCTUnwrap(Refit.refit(mix, in: studio())).stt.location, "us")
    }

    /// ⚠️ AN EAR THE WORKSPACE IS NOT OFFERED DOES NOT FIT, whatever it speaks.
    func testAnEarNotOfferedDoesNotFit() throws {
        var mix = flux
        mix.stt = EngineMixStt(provider: "inworld", model: "inworld/inworld-stt-1")
        let moved = try XCTUnwrap(Refit.refit(mix, in: studio()))
        XCTAssertEqual(moved.stt.model, "nova-3-general")
    }

    func testNoEarForTheLanguageIsNoFit() throws {
        XCTAssertNil(try Refit.refit(flux, in: studio(unfit: allUnfit("stt"))))
    }

    // MARK: - The voice

    /// The same vendor's model; the voice becomes its default where the new model lacks it.
    func testAVoiceMovesToTheSameVendorAndItsDefaultVoice() throws {
        let moved = try XCTUnwrap(Refit.refit(flux, in: studio(unfit: [.voice("deepgram", "aura-2")])))
        XCTAssertEqual(moved.tts, EngineMixTts(provider: "deepgram", model: "flux-tts", voice: "flux-alexis-en"))
        XCTAssertEqual(moved.stt, flux.stt)
    }

    func testTheVoiceIsKeptWhereTheNewModelHasIt() throws {
        var mix = flux
        let voice = "db6b0ed5-d5d3-463d-ae85-518a07d3c2b4"
        mix.tts = EngineMixTts(provider: "cartesia", model: "sonic-3", voice: voice)
        let moved = try XCTUnwrap(Refit.refit(mix, in: studio(unfit: [.voice("cartesia", "sonic-3")])))
        XCTAssertEqual(moved.tts.model, "sonic-3.6")
        XCTAssertEqual(moved.tts.voice, voice)
    }

    func testTheVoicesLocationIsKeptWhereOffered() throws {
        var mix = flux
        mix.tts = EngineMixTts(provider: "google-tts", model: "chirp-3", voice: "Achernar", location: "eu")
        let moved = try XCTUnwrap(Refit.refit(mix, in: studio()))
        XCTAssertEqual(
            moved.tts,
            EngineMixTts(provider: "google-tts", model: "chirp-3-hd", voice: "Achernar", location: "eu")
        )
        mix.tts.location = "mars"
        XCTAssertEqual(try XCTUnwrap(Refit.refit(mix, in: studio())).tts.location, "us")
    }

    func testAnyVendorsVoiceWhenTheVendorHasNone() throws {
        let unfit = try allUnfit("tts").filter { $0.provider == "deepgram" }
        let moved = try XCTUnwrap(Refit.refit(flux, in: studio(unfit: unfit)))
        XCTAssertEqual(moved.tts.provider, "cartesia")
        XCTAssertEqual(moved.tts.model, "sonic-3")
    }

    func testNoVoiceForTheLanguageIsNoFit() throws {
        XCTAssertNil(try Refit.refit(flux, in: studio(unfit: allUnfit("tts"))))
    }

    // MARK: - The read, save and read

    private func response(_ status: Int, _ body: String) -> HTTPResponse {
        HTTPResponse(statusCode: status, headers: ["Content-Type": "application/json"], body: Data(body.utf8))
    }

    /// The read for a `custom-pipeline` persona: `mix` as the stored chain, null when the
    /// service no longer accepts it.
    private func custom(_ mix: EngineMix?, unfit: [Unfit] = []) throws -> String {
        let read = try document(unfit: unfit) { edited in
            try edited.edit(["current", "modelId"]) { $0 = .string(VoiceStudioRules.customPipeline) }
            try edited.edit(["current", "engineMix"]) { $0 = mix.map(JSONValue.engineMix) ?? .null }
        }
        return try XCTUnwrap(String(data: JSONWire.encode(read), encoding: .utf8))
    }

    private func served(_ responses: [HTTPResponse]) -> (VoiceStudioRepository, RepositoryTransport) {
        let transport = RepositoryTransport(responses)
        return (VoiceStudioRepository(client: .repositoryTest(transport)), transport)
    }

    func testTheStoredChainIsReadOnlyForAChainOfTheMembersOwn() async throws {
        let (own, _) = try served([response(200, custom(flux))])
        let stored = await Refit.storedChain(workspaceId: "ws_1", in: own)
        XCTAssertEqual(try stored.get(), flux)

        let (preset, _) = try served([response(200, VoiceStudioFixture.body())])
        let none = await Refit.storedChain(workspaceId: "ws_1", in: preset)
        XCTAssertNil(try none.get())

        let (down, _) = served([response(503, #"{"error":"Down"}"#)])
        let failed = await Refit.storedChain(workspaceId: "ws_1", in: down)
        XCTAssertNotNil(failed.failureOnly)
    }

    func testAChainTheServiceStillAcceptsSendsNothing() async throws {
        let (repository, transport) = try served([response(200, custom(flux))])
        let outcome = await Refit.run(from: flux, workspaceId: "ws_1", in: repository)
        XCTAssertEqual(outcome, .fits)
        XCTAssertEqual(transport.requests.count, 1)
    }

    func testAPresetEngineFits() async throws {
        let (repository, _) = try served([response(200, VoiceStudioFixture.body())])
        let outcome = await Refit.run(from: flux, workspaceId: "ws_1", in: repository)
        XCTAssertEqual(outcome, .fits)
    }

    /// ⛔ MOVED, SAVED AS THE MEMBER'S OWN CHAIN, AND READ BACK BEFORE IT IS CALLED DONE.
    func testAChainThatNoLongerFitsIsMovedSavedAndReadBack() async throws {
        let unfit: [Unfit] = [.voice("deepgram", "aura-2")]
        let moved = try XCTUnwrap(Refit.refit(flux, in: studio(unfit: unfit)))
        let (repository, transport) = try served([
            response(200, custom(nil, unfit: unfit)),
            response(200, #"{"success":true}"#),
            response(200, custom(moved, unfit: unfit)),
        ])
        let outcome = await Refit.run(from: flux, workspaceId: "ws_1", in: repository)
        XCTAssertEqual(outcome, .refitted)
        XCTAssertEqual(transport.requests.count, 3)
        let body = try XCTUnwrap(transport.bodies.first)
        XCTAssertTrue(body.contains(#""modelId":"custom-pipeline""#), body)
        XCTAssertTrue(body.contains(#""voice":"flux-alexis-en""#), body)
        XCTAssertTrue(body.contains(#""model":"flux-tts""#), body)
    }

    func testAReadBackThatStillDoesNotFitIsNotSeen() async throws {
        let (repository, _) = try served([
            response(200, custom(nil, unfit: [.voice("deepgram", "aura-2")])),
            response(200, #"{"success":true}"#),
            response(200, custom(nil)),
        ])
        let outcome = await Refit.run(from: flux, workspaceId: "ws_1", in: repository)
        XCTAssertEqual(outcome, .notSeen)
    }

    func testAReadBackThatFailsIsNotSeen() async throws {
        let (repository, _) = try served([
            response(200, custom(nil)),
            response(200, #"{"success":true}"#),
            response(503, #"{"error":"Down"}"#),
        ])
        let outcome = await Refit.run(from: flux, workspaceId: "ws_1", in: repository)
        XCTAssertEqual(outcome, .notSeen)
    }

    /// ⛔ A REFUSED SECOND SAVE IS SAID AS A FAILURE, with the service's sentence.
    func testARefusedSaveIsAFailure() async throws {
        let refused = #"{"success":false,"error":"That voice chain cannot be saved.","code":"invalid_engine_mix"}"#
        let (repository, _) = try served([response(200, custom(nil)), response(400, refused)])
        let outcome = await Refit.run(from: flux, workspaceId: "ws_1", in: repository)
        XCTAssertEqual(outcome, .failed(.invalidEngineMix("That voice chain cannot be saved.")))
    }

    func testAFailedFirstReadIsAFailure() async {
        let (repository, transport) = served([response(503, #"{"error":"Down"}"#)])
        let outcome = await Refit.run(from: flux, workspaceId: "ws_1", in: repository)
        guard case .failed(.failed) = outcome else { return XCTFail("expected a failure, got \(outcome)") }
        XCTAssertEqual(transport.requests.count, 1)
    }

    func testNothingThatFitsIsNoFitAndSendsNothing() async throws {
        let (repository, transport) = try served([response(200, custom(nil, unfit: allUnfit("tts")))])
        let outcome = await Refit.run(from: flux, workspaceId: "ws_1", in: repository)
        XCTAssertEqual(outcome, .noFit)
        XCTAssertEqual(transport.requests.count, 1)
    }
}
