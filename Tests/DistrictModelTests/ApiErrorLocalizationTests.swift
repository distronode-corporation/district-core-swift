import DistrictL10n
@testable import DistrictModel
import XCTest

/// What a screen shows for a failure, in each language.
final class ApiErrorLocalizationTests: XCTestCase {
    func testTheCodeIsReadOffAnHttpFailureOnly() {
        XCTAssertEqual(ApiError.http(status: 409, message: "x", code: "member_exists").code, "member_exists")
        XCTAssertNil(ApiError.http(status: 409, message: "x").code)
        XCTAssertNil(ApiError.transport("offline").code)
        XCTAssertNil(ApiError.decoding("shape").code)
        XCTAssertEqual(ApiErrorCode.header, "X-Distronode-Error-Code")
    }

    /// ⛔ ENGLISH IS EXACTLY ``ApiError/message``, AS BEFORE THE CODES EXISTED: the
    /// server's sentence wins over the catalog's even when the code is known.
    func testEnglishShowsTheMessageAsBefore() {
        L10nRuntime.withLocale(.en) {
            let known = ApiError.http(status: 401, message: "Unauthorized", code: "unauthorized")
            XCTAssertEqual(known.localizedMessage, "Unauthorized")
            XCTAssertNil(ApiError.http(status: 500, message: nil, code: "unknown").localizedMessage)
            XCTAssertEqual(ApiError.transport("offline").localizedMessage, "offline")
            XCTAssertEqual(ApiError.decoding("shape").localizedMessage, "shape")
        }
    }

    /// ⛔ NEVER THE ENGLISH WIRE TEXT ON A FRENCH SCREEN: a known code gives its catalog
    /// sentence (English until its French lands), anything else gives nil and the
    /// screen's own French.
    func testFrenchShowsTheCodesSentenceOrNothing() {
        L10nRuntime.withLocale(.frCA) {
            let known = ApiError.http(status: 401, message: "Unauthorized", code: "unauthorized")
            XCTAssertEqual(known.localizedMessage, ApiErrorText.sentence(for: "unauthorized"))
            XCTAssertNotEqual(known.localizedMessage, "Unauthorized")
            XCTAssertNil(ApiError.http(status: 409, message: "Not ready", code: "not_a_code").localizedMessage)
            XCTAssertNil(ApiError.http(status: 403, message: "Forbidden").localizedMessage)
            XCTAssertNil(ApiError.transport("offline").localizedMessage)
        }
    }

    /// ⛔ A REFUSAL THIS CLIENT WROTE ITSELF IS SHOWN IN FRENCH AS IT IS: its message is
    /// catalog text in the active language, and it has no code to look up.
    func testFrenchShowsTheClientsOwnRefusal() {
        L10nRuntime.withLocale(.frCA) {
            for sentence in ClientRefusal.sentences {
                XCTAssertEqual(ApiError.http(status: 400, message: sentence).localizedMessage, sentence)
            }
            // Eight refusals, seven sentences: the desk and the inbox both say "That file is empty."
            XCTAssertEqual(ClientRefusal.sentences.count, 7)
        }
    }

    /// Only a server's sentence with no code this build knows stays nil in French, the
    /// screen supplying its own; a known code wins even beside a client-like sentence.
    func testFrenchLeavesAServerSentenceWithNoKnownCodeToTheScreen() {
        L10nRuntime.withLocale(.frCA) {
            XCTAssertNil(ApiError.http(status: 500, message: "Something broke on our side.").localizedMessage)
            XCTAssertNil(ApiError.http(status: 500, message: nil).localizedMessage)
            XCTAssertNil(ApiError.http(status: 400, message: DeskCopy.logoEmpty, code: "not_a_code").localizedMessage)
            XCTAssertEqual(
                ApiError.http(status: 400, message: DeskCopy.logoEmpty, code: "unauthorized").localizedMessage,
                ApiErrorText.sentence(for: "unauthorized")
            )
            XCTAssertNil(ApiError.decoding(DeskCopy.logoEmpty).localizedMessage)
        }
    }

    /// The vocabularies' labels come from the catalog and keep their English.
    func testRoutingRuleLabelsKeepTheirEnglish() {
        L10nRuntime.withLocale(.en) {
            XCTAssertEqual(RoutingRuleField.callerType.label, "Caller Type (business/consumer)")
            XCTAssertEqual(RoutingRuleOperator.equals.label, "Equals")
        }
    }
}
