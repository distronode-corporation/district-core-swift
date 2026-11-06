import DistrictL10n
import Foundation

/// The raw body of a failed District API response, in whichever of the three
/// shapes the route happened to use.
///
/// ⛔ ALL THREE FIELDS ARE OPTIONAL BECAUSE THE API SHIPS THREE DIFFERENT ERROR
/// ENVELOPES AND NOTHING NORMALISES THEM SERVER-SIDE:
///
///   - a route's own failure:  `{success:false, error, code}`
///   - the shared auth guard:  `{error}`, returned verbatim by EVERY route on
///     401/403/404, with no `success` key at all
///   - the newer helpers:      `{error, code}`
///
/// A DTO that required `success` would throw on every 401 in the API, and a 429
/// is a bare `{error}`. `ApiErrorEnvelopeTests` pins the bare shape and
/// `district-member-duplicate.json` the three-key one, so a regression to
/// non-Optional is caught by the test suite rather than by a phone.
///
/// ⚠️ THIS IS THE WIRE SHAPE, NOT THE APP'S ERROR TYPE. Normalising these onto
/// `ApiError` happens in DistrictNetwork; this type is only what the bytes decode into.
public struct ApiErrorEnvelope: Codable, Sendable {
    /// Present only when the route builds its own envelope. Absent, not
    /// `false`, on anything the shared auth guard produced.
    public let success: Bool?
    /// The human-readable reason. Present in all three shapes.
    ///
    /// ⚠️ STILL OPTIONAL. A body that carries neither `error` nor `success` is
    /// not a shape this client has seen, but making it required would turn an
    /// unexpected body into a decode failure that hides the HTTP status the
    /// caller actually needed.
    public let error: String?
    /// The machine-readable discriminator, where the route publishes one. The
    /// values this client branches on are `member_exists` and
    /// `last_agency_member`.
    ///
    /// ⛔ BRANCH ON THIS, NEVER ON `error`. The message strings are product copy
    /// and are rewritten without a version bump; the codes are the contract.
    public let code: String?
}

/// The `code` values this client understands.
///
/// ⚠️ PLAIN CONSTANTS RATHER THAN AN ENUM, for the same reason `role` is a raw
/// string: the server has no exhaustive union behind these, so a value this
/// client has never seen must degrade to "some other error" rather than throw
/// and take out the response it arrived in.
public enum ApiErrorCode {
    /// The response header that carries the code when the route left its body alone
    /// (shared guards, and routes whose body is pinned by a fixture).
    public static let header = ApiErrorText.header
    /// 409 when the address is already a member of the workspace.
    public static let memberExists = "member_exists"
    /// 409 refusing to leave a workspace with no administrator. Not a validation
    /// failure: nothing the operator typed is wrong.
    public static let lastAgencyMember = "last_agency_member"
    /// 503 from `GET /api/district/workspace/list` when a region is unreachable.
    /// See `WorkspaceListDegradedError`.
    public static let regionsDegraded = "REGIONS_DEGRADED"
    /// 402 from the shared `requireActiveSubscription` guard, so it can arrive
    /// on any billable route, not only the dial. Its body carries a fourth key
    /// and therefore has its own type: see `SubscriptionInactiveError`.
    public static let subscriptionInactive = "subscription_inactive"
    /// 403 from the dormancy guard: the workspace has sent nothing for 100 days
    /// and outbound calling and messaging are paused pending an account review.
    ///
    /// ⛔ NOT A BILLING FAILURE AND NOT A PERMISSION FAILURE, and it must not be
    /// worded as either. `subscription_inactive` means "pay and it resumes";
    /// this one means "ask us and we turn it back on", the dashboard has a
    /// reactivation route, so the only correct copy points there.
    /// Rendered as a generic 403 it reads as an account the operator has lost.
    ///
    /// ⚠️ ITS BODY IS A PLAIN `{success, error, code}`, no fourth key, unlike
    /// the subscription refusal, so `ApiErrorEnvelope` models it exactly and it
    /// needs no type of its own. See `district-dial-dormant.json`.
    public static let workspaceDormant = "workspace_dormant"
    /// 400 from `POST /api/district/scheduling/handoff` when a `nonce` was sent but
    /// is not 43 base64url characters. The mint is a failure and is NOT retried with
    /// the same nonce: it would be refused identically.
    public static let invalidNonce = "invalid_nonce"
    /// 400 from the same route when no `nonce` was sent and the server requires one
    /// (`HANDOFF_REQUIRE_NONCE`). Its `error` is the sentence the user sees.
    public static let nonceRequired = "nonce_required"
    /// 409 from `POST /api/district/messages/send` when an app sends SMS to a customer who
    /// has written on WhatsApp, Messenger or Instagram and never by SMS. Not a retry: the
    /// reply goes on the customer's channel, the first of the thread's `replyOptions`.
    public static let smsReplyNotCustomerChannel = "sms_reply_not_customer_channel"
    /// 409 from `POST /api/district/messages/send` when a Messenger or Instagram reply falls
    /// outside Meta's reply window (Instagram answers the same code). Not a retry: the
    /// composer shows the window closed until the customer writes again. See
    /// ``MetaWindowResponse``.
    public static let messengerWindowClosed = "messenger_window_closed"
    /// 400 from `POST /api/district/conversations/assign` naming a Viewer: a Viewer can
    /// read conversations and cannot be assigned one. The picker offers other roles only.
    /// See `district-conversation-assign-viewer.json`.
    public static let assigneeIsViewer = "assignee_is_viewer"
    /// 400 from the same route naming someone who is not a member of the workspace.
    public static let assigneeNotMember = "assignee_not_member"
    /// 409 from `POST /api/district/calls/token` asked to listen to a call that is neither
    /// in progress nor ringing (a stale Live tile, a replayed id). Not retried: the call is
    /// over. ⚠️ ONLY THE LISTEN SAYS THIS: an ended call on the whisper or the takeover is
    /// still `call_not_in_progress`.
    public static let callEnded = "call_ended"
    /// 409 from the whisper and the takeover on a team member's own softphone call (a
    /// `direct_` room): no assistant is on it to take a note or step back. Not "the call
    /// ended", and a screen must not word it so.
    public static let callHasNoReceptionist = "call_has_no_receptionist"
    /// 400 or 409 from the whisper, and 409 from the takeover, when the call is not live or
    /// no deployment holds its room.
    public static let callNotInProgress = "call_not_in_progress"
}
