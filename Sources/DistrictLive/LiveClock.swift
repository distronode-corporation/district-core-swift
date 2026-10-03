import Foundation

/// Where this module reads the time and waits.
///
/// ⛔ A PROTOCOL SO THAT NO TEST EVER SLEEPS. Every timing rule here (the renewal a
/// minute before expiry, the backoff, the 90 s silence watchdog, the 15 s connect
/// timeout, the five-minute presence renewal) is a wait, and a test that waited
/// for real would take an hour to prove the renewal ceiling. The tests drive a
/// manual clock instead; the apps pass ``SystemLiveClock``.
///
/// ⚠️ TWO DIFFERENT CLOCKS BEHIND ONE TYPE, ON PURPOSE. ``nowMilliseconds()`` is
/// WALL time, because the server states a credential's expiry in epoch
/// milliseconds by its own clock and the only thing to compare that with is a wall
/// clock. ``sleep(milliseconds:)`` is a duration, and keeps running while the
/// machine sleeps (see ``SystemLiveClock``).
public protocol LiveClock: Sendable {
    /// The current wall time, in milliseconds since the epoch.
    func nowMilliseconds() -> Int64

    /// Wait `milliseconds`, or throw `CancellationError` if the task is cancelled
    /// first.
    func sleep(milliseconds: Int64) async throws
}

/// The system's clock.
///
/// ⚠️ `Task.sleep(for:)` WAITS ON `ContinuousClock`, WHICH KEEPS COUNTING WHILE A
/// MAC IS ASLEEP. So a laptop that wakes after an hour finds every wait overdue at
/// once: the silence watchdog fires, the dead socket is replaced, and the ring
/// timeout has already passed. That is the wanted behaviour; a clock that paused
/// with the machine would resume a socket that died an hour ago as if it were
/// healthy.
public struct SystemLiveClock: LiveClock {
    public init() {}

    public func nowMilliseconds() -> Int64 {
        Int64((Date().timeIntervalSince1970 * 1000).rounded(.down))
    }

    /// ⚠️ A NEGATIVE WAIT IS A WAIT OF ZERO, not a trap: a deadline that has already
    /// passed is an ordinary result of a machine that slept.
    public func sleep(milliseconds: Int64) async throws {
        try await Task.sleep(for: .milliseconds(max(0, milliseconds)))
    }
}
