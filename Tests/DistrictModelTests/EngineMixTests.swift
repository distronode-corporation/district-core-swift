import DistrictModel
import Foundation
import XCTest

/// The engine mix: the two kinds of optional it carries, and its one renamed key.
final class EngineMixTests: XCTestCase {
    private func decode(_ json: String) throws -> EngineMix {
        try JSONDecoder().decode(EngineMix.self, from: Data(json.utf8))
    }

    /// ⛔ THE ABSENT-WHEN-UNSET KEYS MUST DECODE WHEN ABSENT. A stored mix that never set key
    /// terms, a stability or an interruption carries no key for them at all.
    func testAMixWithEveryOptionalKeyAbsentDecodes() throws {
        let mix = try decode(#"""
        {"v":1,"stt":{"provider":"deepgram","model":"nova-3-general","language":null,"location":null},
         "llm":{"model":"gemini-2.5-flash","location":"auto","thinking":"off","temperature":null},
         "tts":{"provider":"deepgram","model":"aura-2","voice":"aura-2-asteria-en","speed":null,"location":null},
         "turn":{"minDelay":null,"maxDelay":null,"eotThreshold":null},"preemptiveTts":false}
        """#)
        XCTAssertEqual(mix.version, 1)
        XCTAssertNil(mix.stt.keyterms)
        XCTAssertNil(mix.tts.stability)
        XCTAssertNil(mix.turn.interruption)
        XCTAssertNil(mix.userAwayTimeout)
    }

    func testEveryTuningKeyDecodesWhenPresent() throws {
        let mix = try decode(#"""
        {"v":1,"stt":{"provider":"deepgram","model":"flux-general-en","language":"en","location":null,
         "keyterms":["Distronode"]},
         "llm":{"model":"gemini-2.5-flash","location":"auto","thinking":"dynamic","temperature":1.2},
         "tts":{"provider":"elevenlabs","model":"eleven_flash_v2_5","voice":"v","speed":null,"location":null,
         "stability":0.5,"expressivity":0.2},
         "turn":{"minDelay":0.3,"maxDelay":1.8,"eotThreshold":0.7,"mode":"fixed","eagerEotThreshold":0.5,
         "eotTimeoutMs":5000,"interruption":{"minDuration":0.5,"minWords":2,"resume":true,"falseTimeout":2}},
         "preemptiveTts":true,"userAwayTimeout":30}
        """#)
        XCTAssertEqual(mix.stt.keyterms, ["Distronode"])
        XCTAssertEqual(mix.tts.expressivity, 0.2)
        XCTAssertEqual(mix.turn.mode, "fixed")
        XCTAssertEqual(
            mix.turn.interruption,
            EngineMixInterruption(minDuration: 0.5, minWords: 2, resume: true, falseTimeout: 2)
        )
        XCTAssertEqual(mix.userAwayTimeout, 30)
    }

    /// ⚠️ `v` ON THE WIRE, `version` IN SWIFT: the key survives a round trip unrenamed.
    func testTheVersionKeyIsVOnTheWire() throws {
        let mix = EngineMix(
            stt: EngineMixStt(provider: "deepgram", model: "nova-3-general"),
            llm: EngineMixLlm(model: "gemini-2.5-flash", location: "auto", thinking: "off"),
            tts: EngineMixTts(provider: "deepgram", model: "aura-2", voice: "aura-2-asteria-en"),
            turn: EngineMixTurn(),
            preemptiveTts: false
        )
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(mix)) as? [String: Any])
        XCTAssertEqual(object["v"] as? Int, 1)
        XCTAssertNil(object["version"])
        XCTAssertEqual(try JSONDecoder().decode(EngineMix.self, from: JSONEncoder().encode(mix)), mix)
    }

    func testAnInterruptionIsEmptyOnlyWithAllFourUnset() {
        XCTAssertTrue(EngineMixInterruption().isEmpty)
        XCTAssertFalse(EngineMixInterruption(resume: false).isEmpty)
        XCTAssertFalse(EngineMixInterruption(minDuration: 0.5).isEmpty)
        XCTAssertFalse(EngineMixInterruption(minWords: 1).isEmpty)
        XCTAssertFalse(EngineMixInterruption(falseTimeout: 2).isEmpty)
    }

    func testOnlyAMeasuredLatencyIsMeasured() {
        XCTAssertTrue(VoiceStudioLatency(source: "measured", ms: 420, samples: 268, text: "").isMeasured)
        XCTAssertFalse(VoiceStudioLatency(source: "lab", ms: 300, samples: nil, text: "").isMeasured)
    }
}
