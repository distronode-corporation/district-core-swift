import DistrictData
import DistrictL10n
import DistrictModel
import Foundation
import XCTest

/// A billing amount with its currency: French names the currency the service sends,
/// English stays exactly as the apps show it today.
final class BillingMoneyFormatTests: XCTestCase {
    private let nbsp = "\u{A0}"

    // MARK: - French, held to the website's vectors

    /// ⛔ EVERY FRENCH `symbol` VECTOR FOR `usd` AND `cad`, byte for byte: « 249,00 $ CA »,
    /// « 249,00 $ US », grouped with a no-break space.
    func testFrenchWithACurrencyIsTheWebsitesFormatMoney() throws {
        var checked = 0
        for vector in try Self.moneyVectors() {
            guard vector["fn"] as? String == "formatMoney", vector["locale"] as? String == "fr",
                  let currency = vector["currency"] as? String, ["usd", "cad"].contains(currency)
            else { continue }
            let options = try XCTUnwrap(vector["options"] as? [String: Any])
            guard (options["display"] as? String ?? "symbol") == "symbol",
                  options["disambiguateDollar"] as? Bool != true
            else { continue }
            let cents = try XCTUnwrap(vector["minorUnits"] as? NSNumber).intValue
            let output = try XCTUnwrap(vector["output"] as? String)
            XCTAssertEqual(BillingMoneyFormat.price(cents: cents, currency: currency, locale: .frCA), output)
            checked += 1
        }
        XCTAssertEqual(checked, 12, "six amounts in two currencies")
    }

    /// Without a currency, French is the website's bare number (`formatMoneyOrBare`) with
    /// the dollar glyph after it, the « 249,00 $ » the apps' French catalogs already write.
    func testFrenchWithoutACurrencyIsTheBareNumberAndADollar() throws {
        var checked = 0
        for vector in try Self.moneyVectors() {
            guard vector["fn"] as? String == "formatMoneyOrBare", vector["locale"] as? String == "fr"
            else { continue }
            let cents = try XCTUnwrap(vector["minorUnits"] as? NSNumber).intValue
            let output = try XCTUnwrap(vector["output"] as? String)
            XCTAssertEqual(BillingMoneyFormat.price(cents: cents, currency: nil, locale: .frCA), output + nbsp + "$")
            checked += 1
        }
        XCTAssertEqual(checked, 6)
        XCTAssertEqual(BillingMoneyFormat.price(cents: -1500, currency: nil, locale: .frCA), "-15,00" + nbsp + "$")
    }

    func testFrenchNamesTheEuroAndAnyOtherCode() {
        XCTAssertEqual(
            BillingMoneyFormat.price(cents: 24900, currency: "eur", locale: .frCA),
            "249,00" + nbsp + "\u{20AC}"
        )
        XCTAssertEqual(BillingMoneyFormat.price(cents: 24900, currency: "gbp", locale: .frCA), "249,00" + nbsp + "GBP")
    }

    // MARK: - English, unchanged

    /// ⛔ ENGLISH IGNORES THE CURRENCY: `$249.00` for `usd`, `cad` and none alike, with no
    /// thousands separator and the sign after the dollar, as the apps write it today.
    func testEnglishIsTodaysPriceWhateverTheCurrency() {
        for currency in [nil, "usd", "cad", "eur"] as [String?] {
            XCTAssertEqual(BillingMoneyFormat.price(cents: 24900, currency: currency, locale: .en), "$249.00")
            XCTAssertEqual(BillingMoneyFormat.price(cents: 120_425, currency: currency, locale: .en), "$1204.25")
            XCTAssertEqual(BillingMoneyFormat.price(cents: 7, currency: currency, locale: .en), "$0.07")
            XCTAssertEqual(BillingMoneyFormat.price(cents: -1500, currency: currency, locale: .en), "$-15.00")
        }
        XCTAssertEqual(BillingMoneyFormat.price(cents: Int.min, currency: "usd", locale: .en), "$-92233720368547758.08")
    }

    // MARK: - The display models

    /// A subscription and an invoice format their amounts in their own currency, in the
    /// active language.
    func testTheBillingModelsUseTheirOwnCurrency() throws {
        let subscription = try JSONDecoder().decode(
            BillingSubscription.self,
            from: Data(#"""
            {"id":"sub_1","status":"active","cancel_at_period_end":false,"tierName":"Pro",
             "amount":24900,"currency":"cad"}
            """#.utf8)
        )
        let invoice = try JSONDecoder().decode(
            BillingInvoice.self,
            from: Data(#"""
            {"id":"in_1","amount_paid":24900,"total":24900,"tax":3237,"status":"paid",
             "created":1754231400,"hosted_invoice_url":null,"invoice_pdf":null,"currency":"usd"}
            """#.utf8)
        )
        let bare = try JSONDecoder().decode(
            BillingInvoice.self,
            from: Data(#"""
            {"id":"in_2","amount_paid":0,"total":1500,"tax":0,"status":"open",
             "created":1756909800,"hosted_invoice_url":null,"invoice_pdf":null}
            """#.utf8)
        )

        L10nRuntime.withLocale(.en) {
            XCTAssertEqual(subscription.price(cents: 24900), "$249.00")
            XCTAssertEqual(invoice.price(cents: invoice.tax), "$32.37")
            XCTAssertEqual(bare.price(cents: bare.total), "$15.00")
        }
        L10nRuntime.withLocale(.frCA) {
            XCTAssertEqual(subscription.price(cents: 24900), "249,00" + nbsp + "$" + nbsp + "CA")
            XCTAssertEqual(invoice.price(cents: invoice.tax), "32,37" + nbsp + "$" + nbsp + "US")
            XCTAssertEqual(bare.price(cents: bare.total), "15,00" + nbsp + "$")
        }
    }

    // MARK: - Reading the file

    private static func moneyVectors() throws -> [[String: Any]] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("contracts/i18n/format-vectors.json")
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let categories = try XCTUnwrap(root["categories"] as? [[String: Any]])
        let category = try XCTUnwrap(categories.first { $0["category"] as? String == "money" })
        return try XCTUnwrap(category["vectors"] as? [[String: Any]])
    }
}
