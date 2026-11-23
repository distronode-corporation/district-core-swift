import Foundation

/// The single source of a usable access token.
///
/// ⛔ THE INVARIANT THIS ACTOR EXISTS TO PROTECT: A REFRESH TOKEN IS NEVER SENT
/// TWICE. The server's rotation is mandatory, `rotateNativeSession` claims the
/// presented row with an atomic `updateMany(where: { rotatedAt: nil })` and
/// mints a successor, and a token that arrives already-rotated is treated as
/// theft, because the server cannot tell a duplicated credential from a
/// retrying client. Its response is to revoke the entire `familyId` chain and
/// log `[auth] Native refresh replay detected`. Every plausible way of sending
/// the same token twice is closed here:
///
///   1. TWO CONCURRENT CALLERS. Two requests 401 at once, both refresh, both
///      present the same token. Closed by ``inFlight`` below (single-flight),
///      with a fast path so the common case does not serialise.
///   2. REACTING TO EXPIRY INSTEAD OF ANTICIPATING IT. Waiting for a 401
///      guarantees a thundering herd at the 10-minute boundary. Closed by
///      refreshing ``earlyRefreshMarginMilliseconds`` early.
///   3. PROCESS DEATH MID-REFRESH. The response is lost, the disk still holds a
///      token the server has rotated. Closed by the pending marker, see
///      ``TokenStore``, which turns this into a deliberate re-login instead of
///      a false replay alarm.
///   4. PERSISTING THE SUCCESSOR TOO LATE. Closed by resolving the write BEFORE
///      the new access token becomes visible to any caller.
///   5. A FAILED WRITE DISCARDING THE SUCCESSOR. Closed by ``unpersistedSession``
///      see ``adoptRotated(_:deviceId:)``.
///
/// ⛔ EXACTLY ONE OF THESE EXISTS PER PROCESS, HELD BY `AppContainer`. Two
/// coordinators means two single-flight gates, either of which can present the
/// same refresh token, failure mode 1 with the guard intact and useless. A test
/// constructs `AppContainer` precisely so this stays asserted.
///
/// ⚠️ THE SERVER ACCEPTS THAT CASE 3 SIGNS THE USER OUT, AND SO MUST THE UI.
/// There is no recovery: the client does not have the successor token and never
/// will. The server states the tradeoff explicitly, the alternative is
/// being unable to distinguish theft from packet loss and resolving it in the
/// attacker's favour. Design the re-login prompt for it rather than treating it
/// as an error.
///
/// ⚠️ AN ACTOR RATHER THAN A LOCK, AND THAT REMOVES A FIELD THE KOTLIN CLIENT
/// NEEDS. `TokenRefreshCoordinator.kt` carries a `refreshInFlight` flag because
/// its interrupted-refresh check runs both outside and inside its mutex, and the
/// outside copy misfires on its own concurrency. Here the check exists ONCE,
/// inside the single-flight task, so there is nothing for it to misfire on. Do
/// not "optimise" it back out to the fast path.
public actor TokenRefreshCoordinator {
    /// Refresh this far before the access token actually expires.
    ///
    /// 60s against a 10-minute TTL. Sized to cover a slow request plus the
    /// server's own clock-skew tolerance, without refreshing so eagerly that the
    /// effective token lifetime shrinks meaningfully.
    public static let earlyRefreshMarginMilliseconds: Int64 = 60000

    private let store: any TokenStore
    private let refreshClient: any RefreshClient
    private let outbox: RevokeOutbox
    private let now: @Sendable () -> Int64

    /// The access token, in memory ONLY, deliberately never persisted (see
    /// ``TokenStore``). Nil after a process restart, which simply means the next
    /// call refreshes.
    private var cachedAccessToken: String?
    private var cachedAccessTokenExpiresAt: Int64 = 0

    /// A successor the server has already minted and the store refused to keep.
    ///
    /// ⛔ WHEN THIS IS NON-NIL, THE COPY ON DISK IS THE SPENT PREDECESSOR AND
    /// MUST NOT BE READ. Presenting it is the replay that revokes the family.
    /// ``acquire()`` therefore prefers this over ``TokenStore/read()``.
    private var unpersistedSession: PersistedSession?

    /// The one refresh allowed to be outstanding. Concurrent callers await its
    /// value instead of starting their own.
    private var inFlight: Task<AccessTokenOutcome, Never>?

    /// Which session a refresh was started for. ``forget()`` and
    /// ``adopt(_:deviceId:)`` bump it: both replace the session a refresh may
    /// still be in flight for.
    ///
    /// ⛔ A REFRESH ON THE WIRE WHEN THE USER SIGNS OUT STILL COMES BACK WITH A
    /// LIVE SUCCESSOR. Without this fence it was written to the store and its
    /// access token cached after the sign-out, so the next cold start signed the
    /// previous user back in with a refresh token nothing would ever revoke. A
    /// refresh whose generation changed across its store reads, its marker
    /// write or the network call touches neither the store nor the cache, and
    /// hands any successor to ``outbox``.
    private var generation = 0

    /// - Parameter revokeClient: where a successor that lands after ``forget()``
    ///   is revoked. ⚠️ Nil sends nothing and leaves the token in the
    ///   store's revoke outbox for ``SignOutCoordinator/drainPendingRevoke()``;
    ///   the app passes its real client so the token dies straight away.
    public init(
        store: any TokenStore,
        refreshClient: any RefreshClient,
        revokeClient: (any RevokeClient)? = nil,
        now: @escaping @Sendable () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) }
    ) {
        self.store = store
        self.refreshClient = refreshClient
        outbox = RevokeOutbox(store: store, client: revokeClient ?? OutboxOnlyRevokeClient())
        self.now = now
    }

    /// A valid access token, refreshing if necessary.
    ///
    /// Callers must treat ``AccessTokenOutcome/reauthRequired(_:)`` as terminal:
    /// clear their state and route to login. Retrying will not help, and on
    /// ``ReauthReason/interruptedRefresh`` in particular a retry is exactly what
    /// would trigger the family revocation this avoided.
    ///
    /// ⛔ THE FAST PATH AND THE SINGLE-FLIGHT CHECK RUN WITH NO `await` BETWEEN
    /// THEM, WHICH IS WHAT MAKES THE COALESCING SOUND. An actor suspends at
    /// every `await` and admits another caller; inserting one here would let two
    /// callers both find ``inFlight`` nil and both start a refresh, presenting
    /// the same token twice.
    public func accessToken() async -> AccessTokenOutcome {
        if let token = cachedIfFresh() {
            return .available(token)
        }
        if let existing = inFlight {
            return await existing.value
        }

        let started = generation
        // ⛔ THE RESCUE IS READ HERE, IN THE SAME ACTOR TURN AS THE GENERATION:
        // the task below can sit queued while a replacement login parks its OWN
        // rescued successor in the slot, and a capture made later, inside the
        // task, could pair that login's live token with this caller's stale
        // generation and hand it to ``discard(_:)`` (CodeRabbit, 2026-11-23).
        let rescuedSession = unpersistedSession
        let task = Task<AccessTokenOutcome, Never> { [self] in
            let outcome = await acquire(generation: started, rescuedSession: rescuedSession)
            // Cleared HERE, inside the task, so it is already nil by the time any
            // awaiting caller resumes. Clearing it after `await task.value` in
            // each caller instead would leave a completed task installed for a
            // later arrival to latch onto. ⛔ ONLY IF IT IS STILL THIS TASK'S
            // GATE: after ``forget()`` the slot may hold the next session's
            // refresh, and releasing that one would let two run at once.
            if generation == started {
                inFlight = nil
            }
            return outcome
        }
        inFlight = task
        return await task.value
    }

    /// Adopt the tokens from a completed login or an initial code exchange.
    ///
    /// Resolves the write before the access token becomes visible, for the same
    /// ordering reason as a rotation.
    ///
    /// ⛔ AND TRIPS THE SAME FENCE ``forget()`` DOES: without the bump, a refresh
    /// still on the wire for the replaced session had its answer pass the
    /// generation check, its rejection's ``TokenStore/clear()`` wiping the session
    /// the login had just written, or its success overwriting it with the old
    /// session's successor. The abandoned task and any rescue the old session
    /// left are dropped with it, as a sign-out drops them.
    ///
    /// ⛔ AND IT HOLDS THE SINGLE-FLIGHT GATE FOR ITS OWN WRITE, as ``accessToken()`` does
    /// for a refresh: the store serialises nothing (see the ⛔ on
    /// ``TokenStore/clear(ifHolding:)``), so a caller arriving mid-write read the OUTGOING
    /// session at the new generation; callers now latch onto the adoption instead.
    public func adopt(_ tokens: NativeTokens, deviceId: String) async {
        generation += 1
        let started = generation
        inFlight = nil
        unpersistedSession = nil
        // ⛔ THE OUTGOING SESSION'S ACCESS TOKEN GOES WITH IT. The fast path in
        // ``accessToken()`` runs before the gate check, so a caller arriving
        // while this adoption holds the gate would otherwise be served the
        // replaced session's still-fresh token instantly, without ever waiting
        // for the login (CodeRabbit re-review, 2026-11-23).
        cachedAccessToken = nil
        cachedAccessTokenExpiresAt = 0
        let task = Task<AccessTokenOutcome, Never> { [self] in
            let outcome = await adoptRotated(tokens, deviceId: deviceId, generation: started)
            if generation == started {
                inFlight = nil
            }
            return outcome
        }
        inFlight = task
        _ = await task.value
    }

    /// Wait for a refresh already on the wire, and for the write of its successor,
    /// without starting one.
    ///
    /// ⛔ FOR A PROCESS ABOUT TO EXIT, AND IT IS THE ONLY WAY TO CLOSE FAILURE MODE 3
    /// ON A QUIT. The server rotates the moment it answers, and the successor reaches
    /// the store only inside the refresh task (``adoptRotated(_:deviceId:)``). A quit
    /// that lands in that gap leaves the spent predecessor on disk with the marker
    /// naming it, so the next launch reports ``ReauthReason/interruptedRefresh`` and
    /// the person signs in again for having pressed Quit (District AI for Mac 3.0.0,
    /// 2026-10-15: rotated at 14:29:02Z, quit at 14:29:05Z, "Your session ended
    /// unexpectedly" on the next launch). The app awaits this, bounded by its own
    /// deadline, before it lets the process go.
    ///
    /// ⛔ AND A SUCCESSOR THE STORE REFUSED EARLIER IS WRITTEN ONE LAST TIME. After a
    /// failed write the successor lives only in ``unpersistedSession``, the disk holds the
    /// spent predecessor and the marker naming it, and a process exit loses the session
    /// exactly as a quit mid-refresh does. One more attempt costs nothing when the
    /// keychain has come back.
    ///
    /// ⚠️ IT NEVER STARTS A REFRESH, unlike ``accessToken()``: asking for a token at
    /// quit would open the very window this closes. With nothing in flight and nothing
    /// unwritten it returns at once.
    public func finishRefreshInFlight() async {
        // ⛔ THE GATE IS HELD FOR THE WHOLE RETRY, as every other mutation holds
        // it: a caller's refresh starting between this write and the marker clear
        // would spend the rescued token and set its own marker, and this clear,
        // unheld, wiped it, so a transport failure then left nothing and the next
        // launch presented the spent token (CodeRabbit, 2026-11-23). Callers
        // arriving latch onto the retry and answer refreshNotSent: nothing was
        // sent for them, by design.
        while let existing = inFlight {
            _ = await existing.value
        }
        // ⛔ THE RESCUE AND THE GENERATION ARE CAPTURED AS ONE PAIR, IN THE
        // TURN THE WAIT ENDS: a replacement login can park its OWN rescued
        // successor while this actor sat parked in the loop, and a rescue read
        // apart from its generation could be paired with a stale one, persist
        // the token and then hand it to ``discard(_:)``, revoking the live
        // replacement. Read together, whichever session holds the slot now is
        // the one the retry serves, under the generation it belongs to
        // (CodeRabbit re-review, 2026-11-23).
        let started = generation
        let rescued = unpersistedSession
        let task = Task<AccessTokenOutcome, Never> { [self] in
            var outcome = AccessTokenOutcome.retryLater(.refreshNotSent)
            if let rescued {
                let persisted = await repersistRescuedSession(rescued)
                if generation != started {
                    // A replacement inside that write ends the rescue, as in
                    // ``acquire(generation:)``: the write can land after the wipe.
                    outcome = await discard(rescued)
                } else if persisted {
                    try? await store.clearRefreshPending()
                    // ⛔ A LOGIN DURING THE CLEAR OWNS THE RESCUE SLOT: nil-ing
                    // here would drop its rescued successor (CodeRabbit, 2026-11-23).
                    if generation == started {
                        unpersistedSession = nil
                    }
                } else {
                    // A refused write keeps the rescue and the marker: the next
                    // launch takes the interrupted-refresh path rather than
                    // replaying the spent token (CodeRabbit, 2026-11-23).
                }
            }
            if generation == started {
                inFlight = nil
            }
            return outcome
        }
        inFlight = task
        _ = await task.value
    }

    /// Discard the cached access token if it is still the one the caller used.
    ///
    /// ⛔ WITHOUT THIS, A SERVER-SIDE REVOCATION STRANDS THE APP FOR UP TO THE
    /// FULL ACCESS-TOKEN TTL. An access token is a stateless JWS, but the server
    /// checks revocation on every authenticated request (`requireAuth` →
    /// `isSessionRevoked`), so a password change, a password reset or an account
    /// deletion makes a signature-valid, unexpired token start answering 401.
    /// The fast path only consults the clock, so it would keep handing back that
    /// dead token for the remainder of its 10 minutes.
    ///
    /// ⛔ THE TOKEN ARGUMENT IS NOT DECORATION, it makes this safe under
    /// concurrency. Two requests can 401 together; the first invalidates and
    /// refreshes, the second then calls this with the OLD token and must not
    /// wipe the good one that just replaced it.
    ///
    /// - Returns: true if the cached token was actually discarded.
    @discardableResult
    public func invalidateAccessToken(_ token: String) -> Bool {
        guard cachedAccessToken == token else { return false }
        cachedAccessToken = nil
        cachedAccessTokenExpiresAt = 0
        return true
    }

    /// Local sign-out. The caller is responsible for
    /// `POST /api/auth/native/revoke`.
    ///
    /// ⛔ THE IN-MEMORY CREDENTIALS GO FIRST, BEFORE THE SUSPENDING DISK WIPE.
    /// Doing the disk work first would leave a window in which this actor still
    /// hands a live access token to a request racing the sign-out.
    ///
    /// ⛔ AND A REFRESH IN FLIGHT IS FENCED OFF, NOT AWAITED. Bumping
    /// ``generation`` makes its answer land nowhere (see the ⛔ there), and
    /// dropping ``inFlight`` stops a caller after the sign-out from latching
    /// onto the old session's outcome.
    public func forget() async {
        generation += 1
        inFlight = nil
        cachedAccessToken = nil
        cachedAccessTokenExpiresAt = 0
        unpersistedSession = nil
        try? await store.clear()
    }

    // ── Internals ────────────────────────────────────────────────────────────

    private func cachedIfFresh() -> String? {
        guard let token = cachedAccessToken else { return nil }
        return now() + Self.earlyRefreshMarginMilliseconds >= cachedAccessTokenExpiresAt ? nil : token
    }

    /// What an acquisition answers once its generation has moved and it has
    /// captured nothing: the replacement may have cached a token it can still
    /// serve, and beyond that the answer belongs to ``supersededOutcome()``.
    private func supersededOrCached() async -> AccessTokenOutcome {
        if let token = cachedIfFresh() {
            return .available(token)
        }
        return await supersededOutcome()
    }

    /// What an acquisition whose session was replaced answers; WHY that must not
    /// be terminal is on ``RetryReason/sessionReplaced``: a sign-out left no
    /// session, so terminal stands, and a login left one, on disk or as the rescue.
    private func supersededOutcome() async -> AccessTokenOutcome {
        if unpersistedSession != nil {
            return .retryLater(.sessionReplaced)
        }
        // ⛔ A LOGIN'S ADOPTION IS STILL MID-WRITE: the generation moved, so
        // this caller no longer speaks for the session, but its replacement
        // EXISTS and is holding the gate while its write lands; a terminal
        // noSession here would clear live state and route to login while the
        // login is saving. The gate is empty after a sign-out, which is
        // exactly the case the store read below exists to answer (CodeRabbit,
        // 2026-11-23).
        if inFlight != nil {
            return .retryLater(.sessionReplaced)
        }
        do {
            if try await store.read() != nil {
                return .retryLater(.sessionReplaced)
            }
            return .reauthRequired(.noSession)
        } catch {
            return .retryLater(.storeUnavailable)
        }
    }

    private func acquire(
        generation started: Int,
        rescuedSession captured: PersistedSession?
    ) async -> AccessTokenOutcome {
        // ⛔ THE RESCUED SESSION WINS OVER THE DISK. See `unpersistedSession`.
        // ⚠️ CAPTURED IN THE CALLER'S PROLOGUE, IN THE SAME TURN AS THE
        // GENERATION (see ``accessToken()``), so a replacement login's parked
        // successor can never be paired with a stale generation here
        // (CodeRabbit, 2026-11-23).
        if let rescued = captured {
            return await acquireRescued(rescued, generation: started)
        }

        let stored: PersistedSession?
        do {
            stored = try await store.read()
        } catch {
            // ⛔ NOT A SIGN-OUT. A Keychain read fails transiently on a locked
            // device; reporting that as "no session" would sign the user out for
            // having locked their phone.
            return .retryLater(.storeUnavailable)
        }
        guard let current = stored else { return .reauthRequired(.noSession) }

        let pending: String?
        do {
            pending = try await store.pendingRefreshToken()
        } catch {
            return .retryLater(.storeUnavailable)
        }

        // ⛔ THE REPLACEMENT FENCE: THE TWO READS ABOVE ARE SUSPENSION POINTS, and
        // a login can land inside them, so what they produced can belong to a
        // session this acquisition no longer speaks for, and it has no authority
        // over what it read: comparing the marker could take the login's own
        // in-flight marker for an interrupted refresh and WIPE the session that
        // replaced this one, and refreshing would present a token the login's
        // next acquisition presents too, the replay that revokes the family. It
        // may still serve a token the login cached while the reads were suspended.
        if generation != started {
            return await supersededOrCached()
        }

        // ── The interrupted-refresh check ────────────────────────────────────
        // If the marker names the token still on disk, a previous refresh was
        // sent and its response never landed, so this token is already spent
        // server-side. Sending it would revoke the family and produce a security
        // warning describing an attack that did not happen.
        if let pending, pending == current.refreshToken {
            try? await store.clear()
            return .reauthRequired(.interruptedRefresh)
        }

        if now() >= current.refreshTokenExpiresAt {
            try? await store.clear()
            return .reauthRequired(.refreshTokenExpired)
        }

        return await performRefresh(current, generation: started)
    }

    /// The rescue path of ``acquire(generation:)``: persist the successor a
    /// refused write left in memory, clear its marker, then refresh from it.
    /// Split out at the complexity ceiling (swiftlint, 2026-11-23); the fences
    /// and their order are unchanged.
    private func acquireRescued(_ rescued: PersistedSession, generation started: Int) async -> AccessTokenOutcome {
        let persisted = await repersistRescuedSession(rescued)
        // ⛔ A REPLACEMENT INSIDE THAT WRITE ENDS THE RESCUE: ``discard(_:)`` undoes it.
        guard generation == started else { return await discard(rescued) }
        // ⛔ A REFUSED WRITE ENDS THE ATTEMPT, NOT THE SESSION: refreshing with
        // the rescue unwritten is the crash window the marker exists to close
        // (CodeRabbit, 2026-11-23).
        guard persisted else { return .retryLater(.storeUnavailable) }
        try? await store.clearRefreshPending()
        // ⛔ THE CLEAR SUSPENDS TOO: a login inside it owns the rescue slot
        // by now, and this refresh would run for the session it replaced
        // (CodeRabbit, 2026-11-23).
        guard generation == started else { return await supersededOutcome() }
        unpersistedSession = nil
        return await performRefresh(rescued, generation: started)
    }

    /// Try again to write a successor an earlier rotation could not persist.
    ///
    /// Best effort: if it still fails, the in-memory copy stays authoritative
    /// and the marker stays set, which is exactly the state
    /// ``adoptRotated(_:deviceId:)`` left behind. ⚠️ THE WRITE IS ALL IT DOES: the
    /// callers clear the marker and the rescue slot behind their own guard.
    private func repersistRescuedSession(_ rescued: PersistedSession) async -> Bool {
        do {
            try await store.write(rescued)
            return true
        } catch {
            // Deliberately silent. The rescue and the marker both stay, so the
            // next refresh carries the same rescue (CodeRabbit, 2026-11-23).
            return false
        }
    }

    private func performRefresh(_ current: PersistedSession, generation started: Int) async -> AccessTokenOutcome {
        // ⛔ MARKER BEFORE NETWORK, AND A FAILED MARKER ABORTS RATHER THAN FALLS
        // THROUGH. A refresh sent without a durable marker is precisely the
        // crash window the marker exists to close: the successor would be
        // unrecoverable and the next launch would present a spent token and be
        // told it is a thief. A skipped mutation must abort, never fall through
        // to the action.
        do {
            try await store.markRefreshPending(current.refreshToken)
        } catch {
            return .retryLater(.markerNotDurable)
        }

        // ⛔ AND ONCE MORE IMMEDIATELY BEFORE THE REQUEST, WITH NO `await` BETWEEN
        // THE TWO: the marker write suspends too, and a login can land inside it.
        // The request is the one thing no later fence can take back, and ⚠️ the
        // bail leaves the marker naming this own acquisition's token, which
        // nothing that compares can be holding; the next adoption clears it.
        guard generation == started else {
            return await supersededOutcome()
        }

        let result = await refreshClient.refresh(refreshToken: current.refreshToken)

        // ⛔ THE SESSION WAS REPLACED WHILE THE REQUEST WAS ON THE WIRE, by a
        // sign-out or a login; both bump ``generation``. No branch below may
        // run: a success would resurrect the old session, and a rejection's
        // `clear()` could wipe the login that replaced it.
        guard generation == started else {
            if case let .success(tokens) = result {
                await outbox.revoke(tokens.refreshToken)
            }
            return await supersededOutcome()
        }

        switch result {
        case let .success(tokens):
            return await adoptRotated(tokens, deviceId: current.deviceId, generation: started)

        case .rejected:
            try? await store.clear()
            unpersistedSession = nil
            cachedAccessToken = nil
            cachedAccessTokenExpiresAt = 0
            return .reauthRequired(.refreshRejected)

        case .rateLimited:
            // ⛔ The token was NOT consumed, the server rate-limits before
            // rotating, so the marker MUST be cleared. Leaving it set would
            // make the next attempt report `interruptedRefresh` and sign the
            // user out over a transient 429.
            try? await store.clearRefreshPending()
            return .retryLater(.refreshThrottled)

        case .notSent:
            // ⛔ The request never left the device, so the token is provably
            // unspent. Handled exactly like the 429 above.
            try? await store.clearRefreshPending()
            return .retryLater(.refreshNotSent)

        case .transportFailure:
            // ⚠️ The marker is deliberately LEFT SET. The request may have
            // reached the server and rotated the token even though the response
            // did not arrive, indistinguishable from here. Clearing it would
            // let a later attempt present the possibly-spent token and revoke
            // the family. Leaving it set costs a re-login in the ambiguous case.
            return .reauthRequired(.refreshUnreachable)
        }
    }

    /// Store a freshly minted pair and expose its access token.
    ///
    /// ⛔ THE WRITE IS RESOLVED BEFORE THE ACCESS TOKEN IS EXPOSED. Returning
    /// first and writing after leaves a window where the app makes authenticated
    /// requests against a refresh token that exists only in memory and nothing
    /// has yet tried to save.
    ///
    /// ⛔ A FAILED WRITE DOES NOT DISCARD THE PAIR, AND THAT IS THE WHOLE REASON
    /// THIS IS NOT `try await store.write(...)` WITH THE ERROR PROPAGATED. The
    /// predecessor is already spent server-side, so the successor held here is
    /// the ONLY credential that can still refresh this session, dropping it on
    /// a transient Keychain failure would convert "the device was locked for a
    /// moment" into a permanent sign-out. It is kept in memory, the session
    /// keeps working for the life of the process, and every later refresh
    /// retries the write.
    ///
    /// ⚠️ AND THE MARKER IS LEFT SET ON THAT PATH, WHICH IS WHAT MAKES IT SAFE
    /// ACROSS A CRASH. Disk then holds the spent predecessor plus a marker
    /// naming it, so the next launch takes the `interruptedRefresh` path and
    /// re-logs in cleanly instead of presenting a spent token.
    ///
    /// ⛔ AND A SIGN-OUT DURING THE WRITE ENDS THE ADOPTION. ``forget()`` can run while
    /// the store write is suspended; the generation is checked again once it is done,
    /// and an adoption from an ended session caches nothing and is undone
    /// (``discard(_:)``).
    private func adoptRotated(
        _ tokens: NativeTokens,
        deviceId: String,
        generation started: Int
    ) async -> AccessTokenOutcome {
        let successor = PersistedSession(
            refreshToken: tokens.refreshToken,
            refreshTokenExpiresAt: tokens.refreshTokenExpiresAt,
            deviceId: deviceId
        )
        var persisted = true
        do {
            try await store.write(successor)
        } catch {
            persisted = false
        }
        // ⛔ THE GUARD COMES BEFORE ANY OTHER MUTATION: a newer acquisition may
        // already own the marker slot, and a fenced adoption must not take it.
        // A STALE FAILURE ASSIGNS NOTHING, or it overwrites a replacement login's
        // rescue here and discards it below, stranding the login; a CURRENT
        // failure parks its own successor, after the fence (CodeRabbit, 2026-11-23).
        // The discarded successor is reclaimed by ``discard(_:)``.
        guard generation == started else { return await discard(successor) }
        if !persisted {
            unpersistedSession = successor
        }
        // ⚠️ The marker is cleared only when nothing was rescued, i.e. when the
        // write persisted; a refused one leaves it set for the interrupted-refresh path.
        if unpersistedSession == nil {
            try? await store.clearRefreshPending()
        }
        // ⛔ THE CLEAR SUSPENDS TOO: a sign-out inside it is answered by
        // ``discard(_:)``, not by this session's token (CodeRabbit, 2026-11-23).
        guard generation == started else { return await discard(successor) }
        cachedAccessToken = tokens.accessToken
        cachedAccessTokenExpiresAt = tokens.accessTokenExpiresAt
        return .available(tokens.accessToken)
    }

    /// Undo an adoption whose session was replaced while it was being stored.
    ///
    /// ⛔ THE WRITE MAY HAVE LANDED AFTER THE SIGN-OUT'S WIPE, so the store is cleared
    /// if it still holds this successor, and only then: a login since the sign-out
    /// may have written its own. The successor is live server-side, so it goes to
    /// ``outbox`` like any other credential a sign-out leaves behind.
    private func discard(_ successor: PersistedSession) async -> AccessTokenOutcome {
        // Nothing to take back from the rescue slot: every generation change
        // clears the slot in its own prologue before any discarded work resumes,
        // so the slot never holds this successor here.
        // ⛔ ONE STEP, NOT A READ AND THEN A CLEAR: a login can write between the two.
        try? await store.clear(ifHolding: successor.refreshToken)
        await outbox.revoke(successor.refreshToken)
        return await supersededOutcome()
    }
}
