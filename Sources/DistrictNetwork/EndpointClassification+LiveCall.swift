import Foundation

public extension TypedEndpoints {
    /// The two writes a person makes about a call without being in it: declining a
    /// ring, and whispering to the agent on a live call.
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
    ///
    /// ⛔ NEITHER IS EVER RETRIED AUTOMATICALLY. A decline is a statement about a ring
    /// that may already be over, and a whisper may have reached the agent before its
    /// response was lost.
    static let liveCall: Set<EndpointID> = [.declineCall, .whisper]
}
