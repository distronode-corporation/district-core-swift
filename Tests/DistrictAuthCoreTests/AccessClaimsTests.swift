@testable import DistrictAuthCore
import Foundation
import XCTest

/// Reading `sub`, `did` and `exp` out of the native access token, and refusing
/// everything the server would not have minted.
///
/// ⛔ HOSTILE INPUT, BECAUSE THE PARSER IS THE ONLY GUARD. Nothing verifies the
/// signature on this side, so the shape checks are the whole of what stands between
/// a damaged Keychain item and a desktop that rings for the wrong person.
final class AccessClaimsTests: XCTestCase {
    /// A token shaped like `mintNativeAccessToken`'s: HS256 header, the server's
    /// claim set, and a signature this client never checks.
    private func jwt(payload: String, header: String = #"{"alg":"HS256","typ":"JWT"}"#) -> String {
        [header, payload].map { Base64URL.encode(Data($0.utf8)) }.joined(separator: ".") + ".c2lnbmF0dXJl"
    }

    private let fullPayload = """
    {"email":"ada@example.com","did":"install-0123456789","sub":"user_desktop_contract",\
    "iss":"distronode-native","aud":"district-native","iat":1790433000,"exp":1790433900}
    """

    func testTheThreeClaimsAreRead() throws {
        let claims = try XCTUnwrap(AccessClaims(jwt: jwt(payload: fullPayload)))

        XCTAssertEqual(claims.userId, "user_desktop_contract")
        XCTAssertEqual(claims.deviceId, "install-0123456789")
        XCTAssertEqual(claims.expiresAtSeconds, 1_790_433_900)
        XCTAssertEqual(claims.expiresAt, Date(timeIntervalSince1970: 1_790_433_900))
    }

    /// ⚠️ base64url, NOT base64: a payload whose encoding needs `-` or `_` and has
    /// its padding stripped is the ordinary case, not an edge.
    func testAPayloadThatNeedsTheUrlSafeAlphabetIsRead() throws {
        // `??>` encodes to `Pz8-` in base64url and `Pz8+` in base64.
        let payload = #"{"sub":"u??>","did":"d","exp":1}"#
        XCTAssertTrue(Base64URL.encode(Data(payload.utf8)).contains("-"))

        let claims = try XCTUnwrap(AccessClaims(jwt: jwt(payload: payload)))

        XCTAssertEqual(claims.userId, "u??>")
    }

    func testTheWrongNumberOfSegmentsIsRefused() {
        let valid = jwt(payload: fullPayload)
        let parts = valid.split(separator: ".").map(String.init)

        XCTAssertNil(AccessClaims(jwt: ""))
        XCTAssertNil(AccessClaims(jwt: parts[1]))
        XCTAssertNil(AccessClaims(jwt: parts[0] + "." + parts[1]))
        XCTAssertNil(AccessClaims(jwt: valid + ".extra"))
        XCTAssertNil(AccessClaims(jwt: ".."))
    }

    func testAPayloadThatIsNotBase64urlIsRefused() {
        XCTAssertNil(AccessClaims(jwt: "aGVhZGVy.not*base64!.c2ln"))
        // A remainder of one character is producible by no valid encoding.
        XCTAssertNil(AccessClaims(jwt: "aGVhZGVy.eyJzdWIiOiJ1In0x1.c2ln"))
    }

    func testAPayloadThatIsNotAJSONObjectIsRefused() {
        XCTAssertNil(AccessClaims(jwt: jwt(payload: "not json")))
        XCTAssertNil(AccessClaims(jwt: jwt(payload: "[1,2,3]")))
        XCTAssertNil(AccessClaims(jwt: jwt(payload: #""a string""#)))
    }

    /// ⛔ ALL THREE ARE REQUIRED, as `verifyNativeAccessToken` requires them.
    func testAMissingClaimIsRefused() {
        XCTAssertNil(AccessClaims(jwt: jwt(payload: #"{"did":"d","exp":1}"#)))
        XCTAssertNil(AccessClaims(jwt: jwt(payload: #"{"sub":"u","exp":1}"#)))
        XCTAssertNil(AccessClaims(jwt: jwt(payload: #"{"sub":"u","did":"d"}"#)))
        XCTAssertNil(AccessClaims(jwt: jwt(payload: "{}")))
    }

    func testAnEmptyIdentityIsRefused() {
        XCTAssertNil(AccessClaims(jwt: jwt(payload: #"{"sub":"","did":"d","exp":1}"#)))
        XCTAssertNil(AccessClaims(jwt: jwt(payload: #"{"sub":"u","did":"","exp":1}"#)))
    }

    /// ⚠️ THE SERVER WRITES `exp` AS WHOLE SECONDS AND `sub`/`did` AS STRINGS. Any other
    /// type is a token it did not mint.
    func testClaimsOfTheWrongTypeAreRefused() {
        XCTAssertNil(AccessClaims(jwt: jwt(payload: #"{"sub":42,"did":"d","exp":1}"#)))
        XCTAssertNil(AccessClaims(jwt: jwt(payload: #"{"sub":"u","did":["d"],"exp":1}"#)))
        XCTAssertNil(AccessClaims(jwt: jwt(payload: #"{"sub":"u","did":"d","exp":"1790433900"}"#)))
        XCTAssertNil(AccessClaims(jwt: jwt(payload: #"{"sub":"u","did":"d","exp":null}"#)))
        XCTAssertNil(AccessClaims(jwt: jwt(payload: #"{"sub":null,"did":"d","exp":1}"#)))
    }

    /// The header and signature are not read, so a token with a damaged header still
    /// yields its claims. ⚠️ That is the "a read, not a verification" rule, stated as
    /// a test so nobody mistakes the parser for a verifier.
    func testTheHeaderAndSignatureAreNotInspected() {
        let token = "garbage." + Base64URL.encode(Data(fullPayload.utf8)) + "."
        XCTAssertEqual(AccessClaims(jwt: token)?.userId, "user_desktop_contract")
    }
}
