import DistrictModel
import DistrictNetwork
import Foundation

/// The call log, plus the per-call reads a detail screen makes on demand.
public struct CallsRepository: Sendable {
    private let client: ApiClient

    public init(client: ApiClient) {
        self.client = client
    }

    /// A pager over the call log, newest first.
    ///
    /// ⛔ NO TOTAL, SO END-OF-LIST IS INFERRED FROM A SHORT PAGE. The route
    /// answers a BARE ARRAY with no `total`, no `hasMore` and no cursor. That is
    /// what ``OffsetPage/total`` being nil expresses, and it costs one extra empty
    /// request on an exactly-divisible feed, the right price for not guessing.
    ///
    /// ⛔ `[CallSummary].self`, WITH NO WRAPPER. `NextResponse.json(calls)` is
    /// what the route does; a DTO expecting `{success, …}` fails to decode every
    /// response it sends. This is one of three bare-array routes and the only one
    /// on the MVP surface, see ``BareArrayEndpoints``.
    ///
    /// ⚠️ A NEW PAGER PER WORKSPACE. Switching workspace must produce a new one
    /// rather than resetting this: the dedup set and the offsets are only
    /// meaningful within one tenant.
    ///
    /// ⚠️ THE DEDUP KEY IS NOW THE DTO'S OWN NON-OPTIONAL `id` rather than a
    /// lookup into an untyped document, so the identify closure can no longer be
    /// silently wrong about which field identifies a row.
    public func pager(workspaceId: String) -> OffsetPager<CallSummary> {
        let client = client
        return OffsetPager(
            identify: { $0.id },
            fetch: { limit, offset in
                let descriptor = DistrictEndpoints.calls(
                    workspaceId: workspaceId,
                    limit: limit,
                    offset: offset
                )
                return await client.send(descriptor, as: [CallSummary].self)
                    .map { OffsetPage(items: $0, total: nil) }
            }
        )
    }

    /// The newest inbound calls, unpaged, for the dialer's call-back list.
    ///
    /// ⛔ NOT ``pager(workspaceId:)`` READ ONCE, AND THE DIFFERENCE IS NOT STYLE.
    /// An ``OffsetPager`` is a stateful object whose dedup set and offsets belong
    /// to one scrolling surface; borrowing one to read twenty rows would give the
    /// dialer a second pager over the same feed, advancing independently of the
    /// call log's. This is one GET with a small `limit`, which is what the
    /// endpoint is for.
    ///
    /// ⛔ IT REUSES THE CALL-LOG ENDPOINT BECAUSE THE SERVER HAS NO `direction`
    /// FILTER. One page is asked for and its inbound rows are kept client-side, so
    /// there is no new route, no new descriptor and no new fixture.
    ///
    /// ⛔ INBOUND ROWS ONLY, AND THE FILTER IS LOAD-BEARING RATHER THAN TIDY.
    /// ``CallSummary/from`` is the raw `Call.from` column, which on an OUTBOUND row
    /// is the workspace's OWN number: the dial route writes `from: fromNumber` and
    /// puts the callee in `callerName`. A "redial" built from `from` on an outbound
    /// row would dial the workspace's own line, connect, bill, and read as a
    /// carrier fault rather than as a bug in this list. A row with NO `direction`
    /// at all is excluded for the same reason, because an unknown direction is not
    /// evidence that `from` is a callee.
    ///
    /// ⚠️ SO THIS IS "CALL THEM BACK", NOT "REDIAL", AND THE UI MUST SAY SO. A
    /// screen labelled redial would promise to repeat outbound calls it cannot
    /// repeat.
    ///
    /// ⚠️ THE ROWS ARE NOT DEDUPLICATED BY NUMBER. One person who called three
    /// times is three rows, each with its own time and outcome, and collapsing them
    /// here would misreport the log. A view may collapse them for display, and that
    /// is the view's decision to comment.
    ///
    /// ⚠️ NO ENVELOPE TO CHECK, because the feed is a bare array, and an EMPTY
    /// result is a legitimate "nobody has called in" rather than a failure: a
    /// workspace whose last twenty calls were all outbound reaches it honestly. No
    /// guard could tell that apart from a broken read anyway.
    public func recentCallbacks(
        workspaceId: String,
        limit: Int = CallsRepository.callbackLimit
    ) async -> Result<[CallSummary], ApiError> {
        let descriptor = DistrictEndpoints.calls(workspaceId: workspaceId, limit: limit, offset: 0)
        return await client.send(descriptor, as: [CallSummary].self)
            .map { rows in rows.filter(CallsRepository.isCallable) }
    }

    /// One call, fetched by id.
    ///
    /// ⚠️ THE DETAIL SCREEN FETCHES RATHER THAN RECEIVING THE ROW, which is what
    /// makes it survive process death and be openable from a push notification,
    /// where an id is all the app has.
    ///
    /// ⚠️ A 404 DOES NOT IMPLY A MALFORMED ID: the server reads by id and checks
    /// ownership afterwards, so another tenant's id looks exactly like one that
    /// does not exist. Word any message accordingly.
    ///
    /// ⚠️ THE PAYLOAD IS THE FEED'S OWN ``CallSummary``, not a richer type, the
    /// route reuses the server's one `toCallSummaries` mapping. What differs is
    /// the ENVELOPE: the feed is a bare array, this is `{success, call}`.
    public func detail(workspaceId: String, callId: String) async -> Result<CallSummary, ApiError> {
        let outcome = await client.send(
            DistrictEndpoints.callDetail(workspaceId: workspaceId, callId: callId),
            as: CallDetailResponse.self
        )
        return outcome.flatMap { response in
            ResponseEnvelope.affirm("CallDetailResponse", response.success, response).flatMap { affirmed in
                // ⚠️ A 2xx WITH NO `call` IS MALFORMED, NOT AN ABSENCE. Absence
                // is the 404 above; reporting this as one would hide a server
                // bug behind an ordinary empty state.
                guard let call = affirmed.call else {
                    return .failure(.decoding("CallDetailResponse success response carried no call"))
                }
                return .success(call)
            }
        }
    }

    /// A call's transcript.
    ///
    /// ⛔ THE ENVELOPE MATTERS MOST ON THIS ONE, because `""` is the LEGITIMATE
    /// value for a call with no transcript. Without the flag, a structurally wrong
    /// 200 is indistinguishable from "nothing was said" and the screen renders an
    /// empty transcript for a call that has one.
    ///
    /// ⚠️ PREFER THIS OVER THE COPY ON THE FEED ROW. ``CallSummary/transcript``
    /// arrives populated, but a transcript can be written after a call ends, so
    /// the embedded copy is only as fresh as the request that fetched the row.
    public func transcript(workspaceId: String, callId: String) async -> Result<String, ApiError> {
        let outcome = await client.send(
            DistrictEndpoints.callTranscript(workspaceId: workspaceId, callId: callId),
            as: CallTranscriptResponse.self
        )
        return outcome
            .flatMap { ResponseEnvelope.affirm("CallTranscriptResponse", $0.success, $0) }
            // ⚠️ An absent transcript is "" rather than nil, the handler does
            // `call.transcript || ""`, so emptiness is the "nothing to show"
            // test and a nil check would never fire.
            .map(\.transcript)
    }

    /// Send one supervisor line to the agent on a live call.
    ///
    /// ⛔ NEVER RETRIED, HERE OR ABOVE. The route publishes the line to the room before
    /// it answers, so a lost response may follow a line the agent already acted on, and
    /// a second send would say it twice. A failure is shown to the person, who decides.
    ///
    /// ⚠️ THE FAILURES A SCREEN NAMES ARRIVE AS ``ApiError/http(status:message:code:)``
    /// with the server's `code`: `call_not_in_progress` (400 or 409, the call ended),
    /// `call_has_no_receptionist` (409, a team member's own softphone call, where no
    /// assistant is listening), `call_not_found` (404), `call_predates_feature` (400), `service_unavailable` and
    /// `service_not_configured` (503), and 403 for a viewer, whose screen should offer no
    /// whisper in the first place (roles are `["agency","client"]`).
    ///
    /// - Parameter text: one line, 1...2000 characters (the route refuses anything
    ///   else with 400 `invalid_request`), in the third person: it reaches the agent as
    ///   an instruction, not the caller as speech.
    public func whisper(workspaceId: String, callId: String, text: String) async -> Result<Void, ApiError> {
        let outcome = await client.send(
            DistrictEndpoints.whisper(workspaceId: workspaceId, callId: callId, text: text),
            as: SuccessResponse.self
        )
        return outcome
            .flatMap { ResponseEnvelope.affirm("WhisperResponse", $0.success, $0) }
            .map { _ in () }
    }

    /// A listen-only seat on a live call: the credential to join its room hearing
    /// everything and publishing nothing.
    ///
    /// ⛔ NEVER RETRIED, HERE OR ABOVE. A credential that arrives after the person gave up
    /// would join them to a customer's call they had walked away from.
    ///
    /// ⚠️ A VIEWER MAY LISTEN (roles `["agency","client","viewer"]`); only the whisper and
    /// the takeover are refused to one. The refusals a screen names arrive as
    /// ``ApiError/http(status:message:code:)`` with the server's `code`: `room_not_found`
    /// (404, no such call for this account), `call_predates_feature` (400), `call_ended`
    /// (409, the call is neither in progress nor ringing: a stale Live tile or a replayed
    /// id), and `service_not_configured` (503).
    ///
    /// - Returns: `.failure(.decoding)` for a 200 that does not affirm success or that
    ///   carries a blank token or URL: joining on either would show a connected listener
    ///   over what was really a refusal.
    public func monitor(
        callId: SupervisedCallID,
        platform: ClientPlatform = .ios
    ) async -> Result<CallMonitorResponse, ApiError> {
        let outcome = await client.send(
            DistrictEndpoints.monitorCall(callId: callId, platform: platform),
            as: CallMonitorResponse.self
        )
        return outcome
            .flatMap { ResponseEnvelope.affirm("CallMonitorResponse", $0.success, $0) }
            .flatMap { Self.joinable("CallMonitorResponse", $0, url: $0.url, token: $0.token) }
    }

    /// Take a live call over from the assistant: the microphone-only credential to join
    /// its room as a coach.
    ///
    /// ⛔ NEVER RETRIED, HERE OR ABOVE: a late credential is a live microphone in a
    /// customer's call. ⛔ AND IT IS ASKED FOR BEFORE THE LISTEN SEAT IS GIVEN UP, so a
    /// refusal leaves the person listening (`SuperviseSession` in `DistrictCall` orders it).
    ///
    /// ⚠️ THE REFUSALS A SCREEN NAMES: `call_not_in_progress` (409, not live or no
    /// deployment holds the room), `call_has_no_room` (409), `call_not_found` (404),
    /// 403 for a viewer, 429 (20 a minute per workspace), and `service_unavailable` /
    /// `service_not_configured` (503, "could not check", never "the call ended"), and
    /// `call_has_no_receptionist` (409) for a team member's own softphone call, where no
    /// assistant is listening to step back. An ended call stays `call_not_in_progress`.
    public func takeOver(workspaceId: String, callId: String) async -> Result<CallTakeoverResponse, ApiError> {
        let outcome = await client.send(
            DistrictEndpoints.takeOverCall(callId: callId, workspaceId: workspaceId),
            as: CallTakeoverResponse.self
        )
        return outcome
            .flatMap { ResponseEnvelope.affirm("CallTakeoverResponse", $0.success, $0) }
            .flatMap { Self.joinable("CallTakeoverResponse", $0, url: $0.url, token: $0.token) }
    }

    /// ⛔ A BLANK CREDENTIAL IS CONTRACT DRIFT, NOT A JOIN, the rule `InboundCallRepository`
    /// states for the answer: every field is required, so `{}` never reaches here, but
    /// `""` decodes, and the failure would surface at the media join as a network error on
    /// a screen already showing the person in the call.
    private static func joinable<Response>(
        _ name: String,
        _ response: Response,
        url: String,
        token: String
    ) -> Result<Response, ApiError> {
        let blank = { (value: String) in value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !blank(url), !blank(token) else {
            return .failure(.decoding("\(name) carried no join credential"))
        }
        return .success(response)
    }

    /// Register one Live Activity push token for a call, so the server can update the
    /// activity while the app is asleep.
    ///
    /// ⛔ NEVER RETRIED, HERE OR ABOVE. ActivityKit's `pushTokenUpdates` hands over each
    /// new token, and each is sent once. A failure costs only server updates: the app
    /// still updates and ends the activity locally while it is awake.
    ///
    /// ⚠️ 404 `call_not_found` is the call ending first, and nothing to show anyone.
    ///
    /// - Parameter token: the push token as lowercase hex.
    public func registerLiveActivity(
        workspaceId: String,
        callId: String,
        token: String
    ) async -> Result<Void, ApiError> {
        let outcome = await client.send(
            DistrictEndpoints.registerLiveActivity(workspaceId: workspaceId, callId: callId, token: token),
            as: SuccessResponse.self
        )
        return outcome
            .flatMap { ResponseEnvelope.affirm("LiveActivityResponse", $0.success, $0) }
            .map { _ in () }
    }

    /// Register this device's Live Activity push-to-start token, so a ring can start the call's
    /// activity while the app is not running.
    ///
    /// ⛔ NEVER RETRIED, HERE OR ABOVE. A failure costs only the server-started activity; the
    /// app still starts one itself when a ring reaches it in front.
    public func registerLiveActivityStartToken(workspaceId: String, token: String) async -> Result<Void, ApiError> {
        let outcome = await client.send(
            DistrictEndpoints.registerLiveActivityStartToken(workspaceId: workspaceId, token: token),
            as: SuccessResponse.self
        )
        return outcome
            .flatMap { ResponseEnvelope.affirm("LiveActivityStartTokenResponse", $0.success, $0) }
            .map { _ in () }
    }

    /// One page, because the filtering happens afterwards.
    ///
    /// ⚠️ SMALL ON PURPOSE. The server has no `direction` filter, so the whole
    /// list is whatever is inbound within the newest twenty rows, which is one
    /// server page and comfortably under the route's clamp of 100. Asking for more
    /// would buy a longer list for a screen that is a shortcut rather than a log.
    public static let callbackLimit = 20

    /// The ``CallSummary/direction`` value whose ``CallSummary/from`` is somebody
    /// else's number.
    ///
    /// ⚠️ `direction`, NOT ``CallSummary/type``. The handler derives `type` from
    /// the normalised status as well, so an unanswered inbound call reads `missed`
    /// there and would be dropped by a filter that used it.
    ///
    /// ⚠️ DELIBERATELY NOT ``ThreadEventDirection/inbound``, WHICH HOLDS THE SAME
    /// STRING. That is the timeline mapper's vocabulary for a different column, and
    /// sharing a constant between two surfaces that merely agree today makes one of
    /// them unable to move without the other. Kotlin's `CallsRepository` declares
    /// its own for the same reason.
    private static let inboundDirection = "inbound"

    /// ⛔ BLANK COUNTS AS ABSENT, matching Kotlin's `isNullOrBlank`. A row whose
    /// number is whitespace is not something to call back, and a list given one
    /// would offer a row that fills the keypad with nothing.
    ///
    /// ⛔ AND SO DOES AN ENGLISH SENTENCE, WHICH IS WHAT BLANKNESS ALONE MISSED.
    /// A withheld caller reaches this filter as the literal `"Inbound SIP
    /// Caller"` rather than as an empty string (see ``CallerIdentity``), which is
    /// not blank, so the row was offered and tapping it typed that sentence into
    /// the keypad. ``CallerIdentity/resolved(_:)`` subsumes the blank rule, so
    /// this is one test rather than two.
    private static func isCallable(_ row: CallSummary) -> Bool {
        guard row.direction == inboundDirection else { return false }
        return CallerIdentity.resolved(row.from) != nil
    }
}
