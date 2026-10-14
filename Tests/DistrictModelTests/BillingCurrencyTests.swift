import DistrictModel
import Foundation
import XCTest

/// `currency` on a subscription and an invoice, modelled before the server sends it.
///
/// ⚠️ NO FIXTURE CARRIES THE KEY YET, so the strict gate proves only the absent branch
/// (`district-billing.json` still round-trips). These decode the present branch from
/// literal bytes, the shape the route will send once it forwards Stripe's field.
final class BillingCurrencyTests: XCTestCase {
    private let subscription = #"""
    {"id":"sub_1","status":"active","current_period_end":1756909800,
     "cancel_at_period_end":false,"tierName":"District AI Voice Pro","amount":24900,"currency":"cad"}
    """#

    private let invoice = #"""
    {"id":"in_1","amount_paid":24900,"total":24900,"tax":3237,"status":"paid",
     "created":1754231400,"hosted_invoice_url":null,"invoice_pdf":null,"currency":"cad"}
    """#

    func testASubscriptionCarriesItsCurrencyWhenTheServerSendsOne() throws {
        let decoded = try JSONDecoder().decode(BillingSubscription.self, from: Data(subscription.utf8))
        XCTAssertEqual(decoded.currency, "cad")
        XCTAssertEqual(decoded.amount, 24900)
    }

    func testAnInvoiceCarriesItsCurrencyWhenTheServerSendsOne() throws {
        let decoded = try JSONDecoder().decode(BillingInvoice.self, from: Data(invoice.utf8))
        XCTAssertEqual(decoded.currency, "cad")
        XCTAssertEqual(decoded.total, 24900)
    }

    /// Today's server omits the key, and that must stay a nil rather than a failure.
    func testAnAbsentCurrencyDecodesAsNil() throws {
        let bare = subscription.replacingOccurrences(of: #","currency":"cad""#, with: "")
        XCTAssertNotEqual(bare, subscription, "the key was not removed, so this proves nothing")
        let decodedSubscription = try JSONDecoder().decode(BillingSubscription.self, from: Data(bare.utf8))
        XCTAssertNil(decodedSubscription.currency)

        let bareInvoice = invoice.replacingOccurrences(of: #","currency":"cad""#, with: "")
        XCTAssertNotEqual(bareInvoice, invoice, "the key was not removed, so this proves nothing")
        let decodedInvoice = try JSONDecoder().decode(BillingInvoice.self, from: Data(bareInvoice.utf8))
        XCTAssertNil(decodedInvoice.currency)
    }

    /// The key re-encodes under its own name, so a cache written by this client reads back.
    func testTheCurrencyReEncodesUnderItsWireName() throws {
        let decoded = try JSONDecoder().decode(BillingInvoice.self, from: Data(invoice.utf8))
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(decoded)) as? [String: Any]
        )
        XCTAssertEqual(object["currency"] as? String, "cad")
    }
}
