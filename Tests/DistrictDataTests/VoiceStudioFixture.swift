import ContractGateSupport
import DistrictModel
import DistrictNetwork
import Foundation
import XCTest

/// The Voice Studio's contract fixture, decoded, optionally edited first.
///
/// ⚠️ EDITS GO THROUGH THE JSON, NOT THROUGH THE TYPES. The response types have no public
/// initialisers (nothing but the decoder builds one), so a case the fixture does not carry (an
/// ear whose `keyterms` is false, a second Deepgram voice with a measured p50) is made by
/// changing the document and decoding it again. The decode is what keeps the edit honest: a
/// shape the service could not send would not decode.
///
/// ⚠️ ``JSONValue`` RATHER THAN `JSONSerialization`, because it keeps a boolean a boolean and
/// an integer an integer on every platform this package is tested on.
enum VoiceStudioFixture {
    static let name = "district-voice-studio.json"

    static func response(_ edit: (inout JSONValue) throws -> Void = { _ in }) throws -> VoiceStudioResponse {
        var document = try XCTUnwrap(JSONWire.decode(ContractFixtures.read(name)))
        try edit(&document)
        return try JSONDecoder().decode(VoiceStudioResponse.self, from: JSONWire.encode(document))
    }

    /// The fixture's own bytes, for a transport.
    static func body() throws -> String {
        try XCTUnwrap(String(data: ContractFixtures.read(name), encoding: .utf8))
    }

    /// A chain the fixture's current persona runs: Deepgram Flux, Gemini 2.5 Flash at `auto`
    /// with thinking off, Deepgram Aura-2 Asteria.
    static var fluxChain: EngineMix {
        EngineMix(
            stt: EngineMixStt(provider: "deepgram", model: "flux-general-en"),
            llm: EngineMixLlm(model: "gemini-2.5-flash", location: "auto", thinking: "off"),
            tts: EngineMixTts(provider: "deepgram", model: "aura-2", voice: "aura-2-asteria-en"),
            turn: EngineMixTurn(),
            preemptiveTts: false
        )
    }
}

struct FixtureEditFailed: Error {
    let path: [String]
}

extension JSONValue {
    /// Change the value at a path of object keys.
    mutating func edit(_ path: [String], _ change: (inout JSONValue) throws -> Void) throws {
        guard let head = path.first else {
            try change(&self)
            return
        }
        guard case var .object(fields) = self, var child = fields[head] else {
            throw FixtureEditFailed(path: path)
        }
        try child.edit(Array(path.dropFirst()), change)
        fields[head] = child
        self = .object(fields)
    }

    /// Change the first element of the array at `path` whose string keys hold `match`.
    ///
    /// ⚠️ THE MATCHER IS DATA, NOT A CLOSURE: a second closure before the trailing one is
    /// SwiftLint's `multiple_closures_with_trailing_closure`.
    mutating func editEntry(
        _ path: [String],
        where match: [String: String],
        _ change: (inout JSONValue) throws -> Void
    ) throws {
        try edit(path) { value in
            let picked = { (row: JSONValue) in match.allSatisfy { row.has($0.key, $0.value) } }
            guard case var .array(rows) = value, let index = rows.firstIndex(where: picked) else {
                throw FixtureEditFailed(path: path)
            }
            try change(&rows[index])
            value = .array(rows)
        }
    }

    /// Set one key of an object.
    mutating func set(_ key: String, _ value: JSONValue) throws {
        try edit([key]) { $0 = value }
    }

    /// Whether this object's `key` holds the string `value`.
    func has(_ key: String, _ value: String) -> Bool {
        self[key]?.stringValue == value
    }
}
