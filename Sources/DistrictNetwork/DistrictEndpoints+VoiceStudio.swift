import DistrictModel
import Foundation

/// The native Voice Studio: one read, and a save through the existing persona PATCH.
///
/// ⛔ THE SAVE HAS NO ROUTE OF ITS OWN AND IS ``EndpointID/savePersona``, on purpose. The
/// service publishes the Studio as a READ (everything localized, every list, every number) and
/// keeps one writer for the persona. A save is therefore always followed by the read: the PATCH
/// answers a bare `{"success":true}`, does not echo the persona, and ignores some values with a
/// 200, so only the re-read can say what landed.
///
/// ⚠️ BOTH ARE `agency`/`client` ONLY, exactly like `persona/options`: a viewer gets 403.
public extension DistrictEndpoints {
    /// The Studio for one workspace.
    ///
    /// ⛔ NO LOCALE PARAMETER EXISTS AND NONE MAY BE ADDED. The labels follow the reader's
    /// PORTAL language (`User.locale`, else the portal cookie, else English), by the service's
    /// rule; the response carries `locale` so a client can tell which it got.
    ///
    /// ⚠️ Rate limited at 60 reads per workspace per minute. One read on open and one after
    /// every save is the budget; it is not something to poll.
    static func personaVoiceStudio(workspaceId: String) -> ApiRequestDescriptor {
        ApiRequestDescriptor(
            .personaVoiceStudio,
            .get,
            DistrictPaths.workspacePersonaVoiceStudio,
            query: [ApiQueryItem("workspaceId", workspaceId)]
        )
    }

    /// The persona PATCH for the Studio's keys.
    ///
    /// ⛔ ONLY ``keys`` ARE SENT, AND A KEY WHOSE VALUE IS nil IN ``fields`` IS NOT SENT EITHER.
    /// The route merges per key, so an omitted key keeps what is stored; a body carrying every
    /// key would undo a teammate's save of one this screen never touched.
    ///
    /// ⛔ `engineMix` IS WRITTEN IN THE WEB STUDIO'S SHAPE: the always-present nullable keys as
    /// `null`, the absent-when-unset ones left out (see ``JSONValue/engineMix(_:)``). A mix the
    /// catalogue refuses answers **400 `invalid_engine_mix`** and writes NOTHING, the other keys
    /// of the same body included.
    ///
    /// ⚠️ ``EndpointID/savePersona``, the same route as the persona form's `savePersona`, and
    /// the same 30 writes a minute per workspace.
    static func saveVoiceStudio(
        workspaceId: String,
        fields: VoiceStudioFields,
        keys: Set<VoiceStudioKey>
    ) -> ApiRequestDescriptor {
        func sent<Value>(_ key: VoiceStudioKey, _ value: Value?, _ wrap: (Value) -> JSONValue) -> JSONValue? {
            guard keys.contains(key), let value else { return nil }
            return wrap(value)
        }
        return ApiRequestDescriptor(
            .savePersona,
            .patch,
            DistrictPaths.workspacePersona,
            body: .json(.object([
                ("workspaceId", .string(workspaceId)),
                ("modelId", sent(.modelId, fields.modelId) { JSONValue.string($0) }),
                ("voice", sent(.voice, fields.voice) { JSONValue.string($0) }),
                ("engineMix", sent(.engineMix, fields.engineMix) { JSONValue.engineMix($0) }),
                ("preemptiveTts", sent(.preemptiveTts, fields.preemptiveTts) { JSONValue.bool($0) }),
                ("temperature", sent(.temperature, fields.temperature) { JSONValue.number($0) }),
                ("bilingual", sent(.bilingual, fields.bilingual) { JSONValue.bool($0) }),
                ("voiceStyle", sent(.voiceStyle, fields.voiceStyle) { JSONValue.string($0) }),
            ]))
        )
    }
}

public extension JSONValue {
    /// An engine mix as the persona PATCH takes it.
    ///
    /// ⛔ THE WEB STUDIO'S SHAPE, KEY FOR KEY. Every always-present nullable key is written as
    /// `null` when unset, and every absent-when-unset key (`stt.keyterms`, `tts.stability`,
    /// `tts.expressivity`, `turn.mode`, `turn.eagerEotThreshold`, `turn.eotTimeoutMs`,
    /// `turn.interruption`, `userAwayTimeout`) is left out. The server reads an absent key in
    /// a mix as null either way, but a body that matches the web byte for byte is one less
    /// thing to wonder about when a refusal arrives.
    ///
    /// ⚠️ `v` IS WRITTEN AS AN INTEGER: the catalogue refuses any other version.
    static func engineMix(_ mix: EngineMix) -> JSONValue {
        .object([
            ("v", .integer(mix.version)),
            ("stt", .object([
                ("provider", .string(mix.stt.provider)),
                ("model", .string(mix.stt.model)),
                ("language", nullable(mix.stt.language, JSONValue.string)),
                ("location", nullable(mix.stt.location, JSONValue.string)),
                ("keyterms", mix.stt.keyterms.map { JSONValue.array($0.map(JSONValue.string)) }),
            ])),
            ("llm", .object([
                ("model", .string(mix.llm.model)),
                ("location", .string(mix.llm.location)),
                ("thinking", .string(mix.llm.thinking)),
                ("temperature", nullable(mix.llm.temperature, JSONValue.number)),
            ])),
            ("tts", .object([
                ("provider", .string(mix.tts.provider)),
                ("model", .string(mix.tts.model)),
                ("voice", .string(mix.tts.voice)),
                ("speed", nullable(mix.tts.speed, JSONValue.number)),
                ("location", nullable(mix.tts.location, JSONValue.string)),
                ("stability", mix.tts.stability.map(JSONValue.number)),
                ("expressivity", mix.tts.expressivity.map(JSONValue.number)),
            ])),
            ("turn", turn(mix.turn)),
            ("preemptiveTts", .bool(mix.preemptiveTts)),
            ("userAwayTimeout", mix.userAwayTimeout.map(JSONValue.number)),
        ])
    }

    private static func turn(_ turn: EngineMixTurn) -> JSONValue {
        .object([
            ("minDelay", nullable(turn.minDelay, JSONValue.number)),
            ("maxDelay", nullable(turn.maxDelay, JSONValue.number)),
            ("eotThreshold", nullable(turn.eotThreshold, JSONValue.number)),
            ("mode", turn.mode.map(JSONValue.string)),
            ("eagerEotThreshold", turn.eagerEotThreshold.map(JSONValue.number)),
            ("eotTimeoutMs", turn.eotTimeoutMs.map(JSONValue.number)),
            ("interruption", turn.interruption.map { interruption -> JSONValue in
                JSONValue.object([
                    ("minDuration", nullable(interruption.minDuration, JSONValue.number)),
                    ("minWords", nullable(interruption.minWords, JSONValue.number)),
                    ("resume", nullable(interruption.resume, JSONValue.bool)),
                    ("falseTimeout", nullable(interruption.falseTimeout, JSONValue.number)),
                ])
            }),
        ])
    }

    /// ⚠️ `.null` RATHER THAN nil, which ``object(_:)`` would drop: the key is always present.
    private static func nullable<Value>(_ value: Value?, _ wrap: (Value) -> JSONValue) -> JSONValue {
        value.map(wrap) ?? .null
    }
}
