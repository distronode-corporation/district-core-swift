@testable import DistrictL10n
import Foundation
import XCTest

/// The French of every error code and wire value is the French `contracts/i18n/` carries,
/// read from the JSON at test time rather than from the catalogs.
///
/// ⛔ WHY THIS IS NOT THE GENERATED ACCESSOR TEST. That test holds the Swift to the
/// catalogs, and until 8.2.0 the catalogs could hold French the website had since fixed:
/// `gen-l10n.py` kept an entry's French while its English was unchanged, so a fix to the
/// French alone never arrived (`engine_unavailable`, and seven more 8.2.0 found). This
/// test reads the contract itself, so a catalog that drifts from it fails here even if
/// every generated file is current.
final class ContractFrenchTests: XCTestCase {
    /// The contract's French for `code` as this catalog must say it. An entry whose French
    /// departs from the website's on purpose has an `fr_variant` in its catalog saying
    /// why, and its rewrite here; anything else in the sentence must still match.
    private static func expected(_ code: String, _ french: String) -> String {
        switch code {
        // Apple catalogs say « Réglages » for Settings; the website says « paramètres ».
        case "no_sending_number": french.replacingOccurrences(of: "paramètres", with: "réglages")
        default: french
        }
    }

    func testEveryErrorCodeSaysTheContractsFrench() throws {
        let doc = try Self.contract("api-errors.json")
        let codes = try XCTUnwrap(doc["codes"] as? [String: [String: Any]])
        let placeholder = try XCTUnwrap(doc["itemsPlaceholder"] as? String)
        var compared = 0
        L10nRuntime.withLocale(.frCA) {
            for (code, sentence) in codes.sorted(by: { $0.key < $1.key }) {
                if let french = sentence["fr"] as? String {
                    // A listing sentence is compared with its placeholder standing in for
                    // the list, which is what the contract spells.
                    let items = sentence["listField"] == nil ? nil : placeholder
                    XCTAssertEqual(ApiErrorTable.sentence(code, items: items), Self.expected(code, french), code)
                    compared += 1
                }
                if let french = sentence["frWithoutList"] as? String {
                    let without = ApiErrorTable.sentence(code, items: nil)
                    XCTAssertEqual(without, Self.expected(code, french), "\(code) without the list")
                    compared += 1
                }
            }
        }
        // The contract has French for every code today; a JSON shape change that made
        // the loop read nothing would otherwise pass.
        XCTAssertGreaterThan(compared, codes.count)
    }

    func testEveryWireValueSaysTheContractsFrench() throws {
        let doc = try Self.contract("wire-vocabulary.json")
        let categories = try XCTUnwrap(doc["categories"] as? [String: [String: Any]])
        let placeholders = try XCTUnwrap(doc["placeholders"] as? [[String: Any]])
        var compared = 0
        try L10nRuntime.withLocale(.frCA) {
            for (name, category) in categories.sorted(by: { $0.key < $1.key }) {
                let wire = try XCTUnwrap(WireCategory(rawValue: name), "\(name) has no WireCategory")
                for value in try XCTUnwrap(category["values"] as? [[String: Any]]) {
                    let raw = try XCTUnwrap(value["value"] as? String)
                    // The tables key a value trimmed and in lower case, as WireLabel does.
                    let key = raw.trimmingCharacters(in: .whitespaces).lowercased()
                    if let french = value["fr"] as? String {
                        XCTAssertEqual(WireTable.label(wire, key), french, "\(name) \(raw)")
                        compared += 1
                    }
                    if let french = value["frLong"] as? String {
                        XCTAssertEqual(WireTable.regionLong(key), french, "\(name) \(raw) long")
                        compared += 1
                    }
                }
                if let fallback = category["fallback"] as? [String: Any], let french = fallback["fr"] as? String {
                    XCTAssertEqual(WireTable.fallback(wire), french, "\(name) fallback")
                    compared += 1
                }
            }
            for placeholder in placeholders {
                let raw = try XCTUnwrap(placeholder["value"] as? String)
                if let french = placeholder["fr"] as? String {
                    XCTAssertEqual(WireTable.placeholder(raw), french, "placeholder \(raw)")
                    compared += 1
                }
            }
        }
        XCTAssertGreaterThan(compared, 100)
    }

    /// A drifted catalog is what this test exists to catch, so prove the comparison can
    /// fail: a sentence the website no longer says is not what the table says.
    func testAStaleSentenceIsNotTheTablesFrench() {
        L10nRuntime.withLocale(.frCA) {
            let stale = "Il manque encore des renseignements ou des documents pour ce transfert. "
                + "Remplissez chaque étape, puis réessayez."
            XCTAssertNotEqual(ApiErrorTable.sentence("transfer_incomplete", items: nil), stale)
        }
    }

    /// `contracts/i18n/<name>` at the repository root, found by walking up from
    /// #filePath (Tests/DistrictL10nTests/ is two levels down).
    private static func contract(_ name: String) throws -> [String: Any] {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0 ..< 3 {
            url = url.deletingLastPathComponent()
        }
        url = url.appendingPathComponent("contracts/i18n/\(name)")
        let data = try Data(contentsOf: url)
        let object = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(object as? [String: Any], "\(url.path) is not a JSON object")
    }
}
