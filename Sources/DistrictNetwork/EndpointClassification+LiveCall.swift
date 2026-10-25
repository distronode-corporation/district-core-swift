import Foundation

public extension TypedEndpoints {
    /// The writes a person makes about a call without being in it: declining a ring,
    /// whispering to the agent on a live call, and registering a Live Activity's token.
    ///
    /// ⚠️ ITS OWN FILE FOR THE REASON ``TypedEndpoints/softphone`` HAS ONE: the main
    /// classification file is a lint ceiling rather than a taxonomy. ⛔ Unioned into
    /// ``TypedEndpoints/all``, or `EndpointSurfaceTests`' partition assertion fails.
    ///
    /// ⛔ TYPED FROM THEIR FIRST COMMIT. `InboundCallRepository.decline` and
    /// `CallsRepository.whisper` decode the shared ``SuccessResponse``.
    /// `district-call-decline.json` is gated in `ImplementedFixtures`; the whisper has
    /// no fixture (the mobile corpus mirrors the Android client), so its shape is
    /// pinned by its repository tests and the route source.
    /// `CallsRepository.registerLiveActivity` (8.1.0) decodes ``SuccessResponse`` too,
    /// gated by `district-call-live-activity.json`, and so does
    /// `registerLiveActivityStartToken`, gated by `district-live-activity-start-token.json`.
    ///
    /// ⛔ NONE IS EVER RETRIED AUTOMATICALLY. A decline is a statement about a ring
    /// that may already be over, a whisper may have reached the agent before its
    /// response was lost, and a Live Activity token is sent again only when ActivityKit
    /// rotates it (a start token also when it goes stale).
    static let liveCall: Set<EndpointID> = [
        .declineCall, .whisper, .registerLiveActivity, .registerLiveActivityStartToken,
    ]
}
