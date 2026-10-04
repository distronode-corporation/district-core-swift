import DistrictModel
import DistrictNetwork
import Foundation

/// Why a Studio save wrote nothing.
public enum VoiceStudioRefusal: Equatable, Sendable {
    /// ⛔ 400 `invalid_engine_mix`: the catalogue refuses a model, voice, location or language
    /// in the chain, or the key terms are over their limits. NOTHING was written, the other
    /// keys of the same body included. The service's sentence is carried (it is English).
    case invalidEngineMix(String?)
    /// ⛔ 400 `model_unavailable_in_region`: Gemini 3.8 Live in an `eu` workspace.
    case modelUnavailableInRegion(String?)
    /// Anything else: offline, signed out, the role 403, the rate limit, a 5xx, drift.
    case failed(ApiError)
}

/// What a Studio save did.
///
/// ⛔ THREE CASES FOR THE REASON THE SETTINGS SAVES HAVE THREE. ``savedButStale(_:)`` means the
/// write LANDED and only the read back failed: told "not saved", an operator would save again
/// from a state the client can no longer vouch for.
public enum VoiceStudioSaveOutcome: Equatable, Sendable {
    /// The write landed and the Studio was read back. Whether the re-read holds what was sent
    /// is the caller's question (``VoiceStudioRules/landed(sent:keys:reread:)``), because only it
    /// knows which keys it sent.
    case saved(VoiceStudioResponse)
    case savedButStale(ApiError)
    case notSaved(VoiceStudioRefusal)
}

/// The Voice Studio: one read, and a save through the persona PATCH that is always followed by
/// that read.
///
/// ⛔ THE RE-READ IS THE ONLY WAY TO KNOW WHAT A SAVE DID. The PATCH answers a bare
/// `{"success":true}`, does not echo the persona, and answers 200 for things it silently
/// ignores (an unknown `modelId` is coerced, a wrong-typed `temperature` is dropped). So a save
/// is never reported until the Studio has been read back.
///
/// ⚠️ NOTHING IS CACHED. Every residency sentence is a claim about one workspace's region, and
/// the labels follow the reader's portal language, which can change between two reads.
public struct VoiceStudioRepository: Sendable {
    private let client: ApiClient

    public init(client: ApiClient) {
        self.client = client
    }

    /// The Studio for one workspace.
    public func load(workspaceId: String) async -> Result<VoiceStudioResponse, ApiError> {
        let outcome = await client.send(
            DistrictEndpoints.personaVoiceStudio(workspaceId: workspaceId),
            as: VoiceStudioResponse.self
        )
        return outcome.flatMap { ResponseEnvelope.affirm("VoiceStudioResponse", $0.success, $0) }
    }

    /// Send `keys` of `fields`, then read the Studio again.
    ///
    /// ⛔ `sendUnmapped`, BECAUSE THE REFUSAL BODY IS PART OF THE ANSWER. The two refusals a
    /// Studio save can earn carry their `code` in the BODY (no header), and ``ApiError`` keeps
    /// no code; reading it here is what lets a screen say "that chain cannot be saved" rather
    /// than a generic failure.
    ///
    /// ⚠️ NOTHING IS SENT FOR AN EMPTY KEY SET, and the caller's guard is what ensures it: a
    /// body carrying only `workspaceId` still spends one of 30 writes a minute.
    public func save(
        workspaceId: String,
        fields: VoiceStudioFields,
        keys: Set<VoiceStudioKey>
    ) async -> VoiceStudioSaveOutcome {
        let descriptor = DistrictEndpoints.saveVoiceStudio(workspaceId: workspaceId, fields: fields, keys: keys)
        let answer = await client.sendUnmapped(descriptor)
        if let refusal = Self.refusal(of: answer) {
            return .notSaved(refusal)
        }
        switch await load(workspaceId: workspaceId) {
        case let .success(studio):
            return .saved(studio)
        case let .failure(error):
            return .savedButStale(error)
        }
    }

    /// The refusal a PATCH answer carries, or nil when it wrote.
    static func refusal(of outcome: Result<RawResponse, ApiError>) -> VoiceStudioRefusal? {
        let response: RawResponse
        switch outcome {
        case let .failure(error):
            return .failed(error)
        case let .success(raw):
            response = raw
        }
        guard (200 ... 299).contains(response.statusCode) else {
            let envelope = try? JSONDecoder().decode(ApiErrorEnvelope.self, from: response.body)
            if envelope?.code == Self.invalidEngineMix {
                return .invalidEngineMix(envelope?.error)
            }
            if envelope?.code == Self.modelUnavailableInRegion {
                return .modelUnavailableInRegion(envelope?.error)
            }
            return .failed(ApiErrorNormalizer.apiError(statusCode: response.statusCode, body: response.body))
        }
        // ⛔ ENVELOPE-CHECKED LIKE EVERY OTHER WRITE: a route falling into its error branch
        // after the headers are written answers `{success:false}` with a 200.
        let written = try? JSONDecoder().decode(SuccessResponse.self, from: response.body)
        guard written?.success == true else {
            return .failed(.decoding("PersonaPatchResponse did not affirm success=true"))
        }
        return nil
    }

    static let invalidEngineMix = "invalid_engine_mix"
    static let modelUnavailableInRegion = "model_unavailable_in_region"
}
