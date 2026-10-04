import DistrictModel
@testable import DistrictNetwork
import Foundation
import XCTest

/// What a Voice Studio save puts on the wire.
///
/// ⛔ BODY-LEVEL, FOR THE REASON `PersonaEndpointTests` IS: the property under test is what is
/// LEFT OUT. The route merges per key, so a key sent that nobody changed overwrites a teammate's
/// save, and a mix sent without its engine id is read as nothing.
final class VoiceStudioEndpointTests: XCTestCase {
    private func body(_ descriptor: ApiRequestDescriptor) throws -> String {
        guard case let .json(value) = descriptor.body else {
            XCTFail("expected a JSON body")
            return ""
        }
        return try String(bytes: JSONWire.encode(value), encoding: .utf8) ?? ""
    }

    private let mix = EngineMix(
        stt: EngineMixStt(provider: "deepgram", model: "flux-general-en"),
        llm: EngineMixLlm(model: "gemini-2.5-flash", location: "auto", thinking: "dynamic"),
        tts: EngineMixTts(provider: "deepgram", model: "aura-2", voice: "aura-2-asteria-en"),
        turn: EngineMixTurn(),
        preemptiveTts: false
    )

    func testTheSaveIsThePersonaPatch() {
        let descriptor = DistrictEndpoints.saveVoiceStudio(
            workspaceId: "ws_1",
            fields: VoiceStudioFields(modelId: "deepgram-pipeline", voice: "aura-2-luna-en"),
            keys: [.voice]
        )
        XCTAssertEqual(descriptor.id, .savePersona)
        XCTAssertEqual(descriptor.method, .patch)
        XCTAssertEqual(descriptor.segments, ["api", "district", "workspace", "persona"])
    }

    /// ⛔ ONLY THE NAMED KEYS, AND A NAMED KEY WITH NO VALUE IS NOT SENT EITHER.
    func testOnlyTheNamedKeysWithValuesAreSent() throws {
        let fields = VoiceStudioFields(modelId: "deepgram-pipeline", voice: "aura-2-luna-en", preemptiveTts: true)
        let descriptor = DistrictEndpoints.saveVoiceStudio(
            workspaceId: "ws_1",
            fields: fields,
            keys: [.voice, .preemptiveTts, .temperature]
        )
        XCTAssertEqual(
            try body(descriptor),
            #"{"preemptiveTts":true,"voice":"aura-2-luna-en","workspaceId":"ws_1"}"#
        )
    }

    /// ⛔ THE WEB'S SHAPE FOR A MIX: the always-present keys as `null`, the others left out.
    func testACustomChainSendsItsMixInTheWebsShape() throws {
        let fields = VoiceStudioFields(
            modelId: "custom-pipeline",
            voice: "aura-2-asteria-en",
            engineMix: mix,
            preemptiveTts: false,
            bilingual: false
        )
        let descriptor = DistrictEndpoints.saveVoiceStudio(
            workspaceId: "ws_1",
            fields: fields,
            keys: [.modelId, .engineMix, .bilingual]
        )
        XCTAssertEqual(
            try body(descriptor),
            #"{"bilingual":false,"engineMix":{"llm":{"location":"auto","model":"gemini-2.5-flash","#
                + #""temperature":null,"thinking":"dynamic"},"preemptiveTts":false,"stt":{"language":null,"#
                + #""location":null,"model":"flux-general-en","provider":"deepgram"},"tts":{"location":null,"#
                + #""model":"aura-2","provider":"deepgram","speed":null,"voice":"aura-2-asteria-en"},"#
                + #""turn":{"eotThreshold":null,"maxDelay":null,"minDelay":null},"v":1},"#
                + #""modelId":"custom-pipeline","workspaceId":"ws_1"}"#
        )
    }

    /// Every tuning key, present, in its place.
    func testEveryTuningKeyIsWrittenWhenSet() {
        var tuned = mix
        tuned.stt.language = "en"
        tuned.stt.location = "us"
        tuned.stt.keyterms = ["Distronode"]
        tuned.llm.temperature = 1.5
        tuned.tts.speed = 1.25
        tuned.tts.location = "eu"
        tuned.tts.stability = 0.5
        tuned.tts.expressivity = 0.25
        tuned.turn = EngineMixTurn(
            minDelay: 0.5,
            maxDelay: 1.5,
            eotThreshold: 0.75,
            mode: "fixed",
            eagerEotThreshold: 0.5,
            eotTimeoutMs: 3000,
            interruption: EngineMixInterruption(minDuration: 0.5, minWords: nil, resume: true, falseTimeout: 2)
        )
        tuned.userAwayTimeout = 30
        let value = JSONValue.engineMix(tuned)
        XCTAssertEqual(value["stt"]?["keyterms"], .array([.string("Distronode")]))
        XCTAssertEqual(value["stt"]?["language"], .string("en"))
        XCTAssertEqual(value["llm"]?["temperature"], .number(1.5))
        XCTAssertEqual(value["tts"]?["speed"], .number(1.25))
        XCTAssertEqual(value["tts"]?["location"], .string("eu"))
        XCTAssertEqual(value["tts"]?["stability"], .number(0.5))
        XCTAssertEqual(value["tts"]?["expressivity"], .number(0.25))
        XCTAssertEqual(value["turn"]?["mode"], .string("fixed"))
        XCTAssertEqual(value["turn"]?["eotTimeoutMs"], .number(3000))
        XCTAssertEqual(value["turn"]?["eagerEotThreshold"], .number(0.5))
        XCTAssertEqual(value["turn"]?["interruption"]?["minWords"], .null)
        XCTAssertEqual(value["turn"]?["interruption"]?["resume"], .bool(true))
        XCTAssertEqual(value["userAwayTimeout"], .number(30))
        XCTAssertEqual(value["v"], .integer(1))
    }

    func testARealtimeSaveSendsItsTemperatureAndStyle() throws {
        let fields = VoiceStudioFields(
            modelId: "gemini-live-2.5-flash-native-audio",
            voice: "Kore",
            temperature: 0.5,
            voiceStyle: "en-US-News-K"
        )
        let descriptor = DistrictEndpoints.saveVoiceStudio(
            workspaceId: "ws_1",
            fields: fields,
            keys: Set(VoiceStudioKey.allCases)
        )
        XCTAssertEqual(
            try body(descriptor),
            #"{"modelId":"gemini-live-2.5-flash-native-audio","temperature":0.5,"voice":"Kore","#
                + #""voiceStyle":"en-US-News-K","workspaceId":"ws_1"}"#
        )
    }
}
