// SPDX-FileCopyrightText: Distronode Corporation
//
// SPDX-License-Identifier: Apache-2.0

@testable import DistrictAuthCore
import Foundation
import XCTest

/// ``InMemoryTokenStore`` ships in `Sources/` so DistrictNetwork and
/// DistrictData can build a coordinator in their own suites, which makes it
/// production-visible code and therefore code the floors measure. It is also
/// the reference the Keychain implementation in `App/` has to behave like, so
/// its contract is pinned here rather than left implied.
final class InMemoryTokenStoreTests: XCTestCase {
    /// ⛔ THE OUTBOX IS CLEARED ONLY FOR THE TOKEN IT HOLDS. See
    /// ``TokenStore/clearRevokePending(ifHolding:)``.
    func testTheOutboxClearsOnlyForTheTokenItHolds() async throws {
        let store = InMemoryTokenStore()
        try await store.markRevokePending("newer")

        try await store.clearRevokePending(ifHolding: "older")
        let kept = try await store.pendingRevokeToken()
        XCTAssertEqual(kept, "newer")

        try await store.clearRevokePending(ifHolding: "newer")
        let cleared = try await store.pendingRevokeToken()
        XCTAssertNil(cleared)
    }

    /// ⛔ THE SESSION IS CLEARED ONLY WHILE IT IS THE ONE NAMED. See
    /// ``TokenStore/clear(ifHolding:)``.
    func testTheSessionClearsOnlyForTheTokenItHolds() async throws {
        let store = InMemoryTokenStore(session: AuthFixtures.session(refreshToken: "login"))
        try await store.markRefreshPending("login")

        try await store.clear(ifHolding: "successor")
        let kept = try await store.read()
        XCTAssertEqual(kept?.refreshToken, "login")
        let marker = try await store.pendingRefreshToken()
        XCTAssertEqual(marker, "login")

        try await store.clear(ifHolding: "login")
        let cleared = try await store.read()
        XCTAssertNil(cleared)
        let noMarker = try await store.pendingRefreshToken()
        XCTAssertNil(noMarker)
    }

    /// ⚠️ AND ``SpyTokenStore``, WHICH EVERY OTHER SUITE TAKES AS ITS ORACLE: with
    /// the protocol default gone, its own one-step compare-and-clear is what the
    /// sequence assertions elsewhere rest on, so it is pinned here too.
    func testTheSpyClearsOnlyWhileHoldingTheNamedToken() async throws {
        let store = SpyTokenStore(session: AuthFixtures.session(refreshToken: "login"), revokePending: "held")

        try await store.clear(ifHolding: "successor")
        await expectEqual("login") { await store.session?.refreshToken }
        try await store.clearRevokePending(ifHolding: "other")
        await expectEqual("held") { await store.revokePending }

        try await store.clear(ifHolding: "login")
        await expectNil { await store.session }
        try await store.clearRevokePending(ifHolding: "held")
        await expectNil { await store.revokePending }
    }

    func testStartsEmptyAndRoundTripsASession() async throws {
        let store = InMemoryTokenStore()
        let read = try await store.read()
        XCTAssertNil(read)

        let session = AuthFixtures.session()
        try await store.write(session)
        let stored = try await store.read()
        XCTAssertEqual(stored, session)
    }

    func testAcceptsASeededSession() async throws {
        let session = AuthFixtures.session(refreshToken: "seeded")
        let store = InMemoryTokenStore(session: session)
        let stored = try await store.read()
        XCTAssertEqual(stored?.refreshToken, "seeded")
    }

    func testWriteReplacesRatherThanAccumulates() async throws {
        let store = InMemoryTokenStore(session: AuthFixtures.session(refreshToken: "old"))
        try await store.write(AuthFixtures.session(refreshToken: "new"))
        let stored = try await store.read()
        XCTAssertEqual(stored?.refreshToken, "new")
    }

    func testMarkerRoundTripsIndependentlyOfTheSession() async throws {
        let store = InMemoryTokenStore(session: AuthFixtures.session())
        let empty = try await store.pendingRefreshToken()
        XCTAssertNil(empty)

        try await store.markRefreshPending("refresh-1")
        let marked = try await store.pendingRefreshToken()
        XCTAssertEqual(marked, "refresh-1")

        try await store.clearRefreshPending()
        let cleared = try await store.pendingRefreshToken()
        XCTAssertNil(cleared)
        let survived = try await store.read()
        XCTAssertNotNil(survived, "clearing the marker must not touch the session")
    }

    func testClearForgetsBothTheSessionAndTheMarker() async throws {
        let store = InMemoryTokenStore(session: AuthFixtures.session())
        try await store.markRefreshPending("refresh-1")
        try await store.clear()

        let session = try await store.read()
        let marker = try await store.pendingRefreshToken()
        XCTAssertNil(session)
        XCTAssertNil(marker)
    }
}
