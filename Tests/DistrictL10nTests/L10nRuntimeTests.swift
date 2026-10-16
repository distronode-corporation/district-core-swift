@testable import DistrictL10n
import Foundation
import XCTest

final class L10nRuntimeTests: XCTestCase {
    // MARK: - Locale resolution

    /// ⛔ ANY FRENCH IS CANADIAN FRENCH, AND THE FIRST LANGUAGE THIS CORE SPEAKS DECIDES.
    func testTheFirstLanguageTheCoreSpeaksDecides() {
        let rows: [([String], L10nLocale)] = [
            (["fr-CA"], .frCA),
            (["fr-FR"], .frCA),
            (["fr-BE", "en-US"], .frCA),
            (["fr_CH"], .frCA),
            (["FR"], .frCA),
            (["fr-Latn-CA"], .frCA),
            (["en-US", "fr-CA"], .en),
            (["en"], .en),
            (["de-DE", "fr-CH"], .frCA),
            (["de-DE", "en-GB", "fr-FR"], .en),
            (["", "es"], .en),
            ([], .en),
            (["french"], .en),
        ]
        for (tags, expected) in rows {
            XCTAssertEqual(locale(fromPreferred: tags), expected, "\(tags)")
        }
    }

    func testTheTagsAndTheStoredValues() {
        XCTAssertEqual(L10nLocale.en.languageTag, "en")
        XCTAssertEqual(L10nLocale.frCA.languageTag, "fr-CA")
        XCTAssertEqual(L10nLocale.en.settingsValue, "en")
        XCTAssertEqual(L10nLocale.frCA.settingsValue, "fr")
    }

    // MARK: - The runtime

    /// English until an app says otherwise, which is how French stays off in 7.x.
    func testTheStoredLanguageIsEnglishUntilSetAndTheScopeWins() {
        XCTAssertEqual(L10nRuntime.locale, .en)
        L10nRuntime.withLocale(.frCA) {
            XCTAssertEqual(L10nRuntime.locale, .frCA)
            L10nRuntime.withLocale(.en) {
                XCTAssertEqual(L10nRuntime.locale, .en)
            }
        }
        XCTAssertEqual(L10nRuntime.locale, .en)
    }

    /// ⚠️ THE ONE TEST THAT WRITES THE STORED VALUE, AND IT PUTS IT BACK. The scoped
    /// value still wins over it, so a test running beside this one in its own scope is
    /// not disturbed.
    func testTheStoredValueIsWhatTheAppSet() {
        L10nRuntime.locale = .frCA
        defer { L10nRuntime.locale = .en }
        XCTAssertEqual(L10nRuntime.locale, .frCA)
        L10nRuntime.withLocale(.en) {
            XCTAssertEqual(L10nRuntime.locale, .en)
        }
        XCTAssertEqual(DeskCopy.logoEmpty, "Ce fichier est vide.")
    }

    /// Every entry has reviewed French. The apps still decide when French is shown.
    func testFrenchIsComplete() {
        XCTAssertTrue(L10nRuntime.isFrenchComplete)
    }

    // MARK: - The error code table

    func testAKnownCodeHasItsSentence() {
        XCTAssertEqual(ApiErrorText.sentence(for: "unauthorized"), "Please sign in to continue.")
        // Two spellings of one refusal, both live on the wire, both known.
        XCTAssertEqual(ApiErrorText.sentence(for: "FORBIDDEN"), "You do not have permission to do that.")
        XCTAssertEqual(ApiErrorText.sentence(for: "forbidden"), "You do not have permission to do that.")
        XCTAssertEqual(ApiErrorText.unknown, "Something went wrong. Please try again.")
        XCTAssertEqual(ApiErrorText.header, "X-Distronode-Error-Code")
    }

    func testAnUnknownCodeHasNone() {
        XCTAssertNil(ApiErrorText.sentence(for: "not_a_code"))
        XCTAssertNil(ApiErrorText.sentence(for: ""))
        XCTAssertNil(ApiErrorText.sentence(for: "UNAUTHORIZED"))
    }

    /// The two codes whose sentence lists what the refusal names, with and without it.
    func testAListingCodeJoinsItsItemsWithCommas() {
        XCTAssertEqual(
            ApiErrorText.sentence(for: "invalid_params", items: ["email", "phone"]),
            "Check these fields and try again: email, phone."
        )
        XCTAssertEqual(
            ApiErrorText.sentence(for: "invalid_params"),
            "Some of what you entered is not valid. Please check it and try again."
        )
        XCTAssertEqual(
            ApiErrorText.sentence(for: "REGIONS_DEGRADED", items: ["eu"]),
            "Your workspaces could not all be listed because some regions are unreachable right now (eu). "
                + "Nothing about your account has changed."
        )
        // Any other code ignores the items.
        XCTAssertEqual(ApiErrorText.sentence(for: "unauthorized", items: ["x"]), "Please sign in to continue.")
    }

    // MARK: - Wire labels

    func testAKnownValueHasItsLabel() {
        XCTAssertEqual(WireLabel.label(.callStatus, "completed"), "Completed")
        XCTAssertEqual(WireLabel.label(.callStatus, "  In-Progress "), "In progress")
        XCTAssertEqual(WireLabel.label(.sentiment, "negative"), "Friction")
        XCTAssertEqual(WireLabel.label(.funnelStage, "Total Dials"), "Total Dials")
        XCTAssertEqual(WireLabel.label(.memberRole, "agency"), "Administrator")
        XCTAssertEqual(WireLabel.label(.disposition, "not-interested"), "Not interested")
        XCTAssertEqual(WireLabel.label(.region, "CA"), "Canada")
    }

    /// ⛔ NEVER THE VALUE HUMANIZED: a status the server adds later reads as the generic
    /// label, which is localized, rather than as English on a French screen.
    func testAnUnknownValueHasTheGenericLabel() {
        XCTAssertEqual(WireLabel.label(.callStatus, "queued"), "Other")
        XCTAssertEqual(WireLabel.label(.callStatus, nil), "Other")
        XCTAssertEqual(WireLabel.label(.memberRole, "owner"), "Other")
        XCTAssertEqual(WireLabel.label(.region, ""), "Other")
        XCTAssertEqual(WireLabel.label(.region, nil), "Other")
    }

    /// The contract's two exceptions: a transfer reason's own fallback sentence, and an
    /// unknown region id upper-cased.
    func testTheTwoContractExceptions() {
        XCTAssertEqual(WireLabel.label(.transferReason, "carrier_gone"), "Transfer attempted but not connected")
        XCTAssertEqual(WireLabel.label(.transferReason, nil), "Transfer attempted but not connected")
        XCTAssertEqual(WireLabel.label(.region, " mena "), "MENA")
    }

    /// 3.0.1: the vocabulary's label when it lists the value, nil otherwise, so an English
    /// screen shows `Completed` and keeps an unlisted value as sent.
    func testAKnownLabelIsTheVocabularysOrNothing() {
        XCTAssertEqual(WireLabel.knownLabel(.callStatus, " Completed "), "Completed")
        XCTAssertEqual(WireLabel.knownLabel(.numberProvider, "twilio"), WireLabel.label(.numberProvider, "twilio"))
        XCTAssertNil(WireLabel.knownLabel(.callStatus, "queued"))
        XCTAssertNil(WireLabel.knownLabel(.transferReason, "carrier_gone"), "no fallback sentence")
        XCTAssertNil(WireLabel.knownLabel(.region, "mena"), "no upper-casing")
        XCTAssertNil(WireLabel.knownLabel(.callStatus, nil))
        L10nRuntime.withLocale(.frCA) {
            XCTAssertEqual(WireLabel.knownLabel(.callStatus, "completed"), "Terminé")
        }
    }

    func testARegionLongName() {
        XCTAssertEqual(WireLabel.regionLongName("ca"), "Canada (Montreal)")
        XCTAssertEqual(WireLabel.regionLongName(" EU"), "Europe (Frankfurt)")
        XCTAssertEqual(WireLabel.regionLongName("mena"), "MENA")
        XCTAssertEqual(WireLabel.regionLongName(nil), "Other")
    }

    func testAPlaceholderHasItsLabelAndRealDataHasNone() {
        XCTAssertEqual(WireLabel.placeholder("Unknown"), "Unknown")
        XCTAssertEqual(WireLabel.placeholder("No summary available."), "No summary available.")
        XCTAssertNil(WireLabel.placeholder("Ana Gomez"))
        XCTAssertNil(WireLabel.placeholder("unknown"))
        XCTAssertNil(WireLabel.placeholder(nil))
        let noAnswer = "No answer, no conversation took place."
        XCTAssertEqual(WireLabel.placeholder(noAnswer), noAnswer)
        XCTAssertEqual(WireLabel.placeholder("No answer \u{2014} no conversation took place."), noAnswer)
    }

    // MARK: - Lists and counts, which the vectors do not cover

    /// « A, B et C », and English keeps the core's own `a, b and c` with no serial comma.
    func testLists() {
        XCTAssertEqual(L10nFormat.list([], locale: .en), "")
        XCTAssertEqual(L10nFormat.list(["A"], locale: .frCA), "A")
        XCTAssertEqual(L10nFormat.list(["A", "B"], locale: .en), "A and B")
        XCTAssertEqual(L10nFormat.list(["A", "B"], locale: .frCA), "A et B")
        XCTAssertEqual(L10nFormat.list(["A", "B", "C"], locale: .en), "A, B and C")
        XCTAssertEqual(L10nFormat.list(["A", "B", "C"], locale: .frCA), "A, B et C")
    }

    func testCountsAreUngroupedInEnglishAndGroupedInFrench() {
        XCTAssertEqual(L10nFormat.count(1204, locale: .en), "1204")
        XCTAssertEqual(L10nFormat.count(1204, locale: .frCA), "1\u{00A0}204")
        XCTAssertEqual(L10nFormat.count(-1_000_000, locale: .frCA), "-1\u{00A0}000\u{00A0}000")
        XCTAssertEqual(L10nFormat.integer(-1204, locale: .en), "-1,204")
    }

    /// The website prints the empty string for a value it cannot format.
    func testANumberThatIsNotFiniteIsEmpty() {
        XCTAssertEqual(L10nFormat.number(.nan, locale: .en), "")
        XCTAssertEqual(L10nFormat.number(.infinity, locale: .frCA), "")
        XCTAssertEqual(L10nFormat.percent(ratio: .nan, locale: .en), "")
    }

    func testANegativeOrMissingDurationReadsZero() {
        XCTAssertEqual(L10nFormat.minutesSeconds(nil, locale: .en), "0m")
        XCTAssertEqual(L10nFormat.minutesSeconds(-5, locale: .frCA), "0\u{00A0}min")
        XCTAssertEqual(L10nFormat.callDuration(nil), "0s")
        XCTAssertEqual(L10nFormat.callDuration(-1), "0s")
    }

    func testMoneyEdges() {
        XCTAssertEqual(L10nFormat.money(minorUnits: -150, currency: "usd", locale: .en), "-$1.50")
        XCTAssertEqual(L10nFormat.money(minorUnits: -150, currency: "cad", locale: .frCA), "-1,50\u{00A0}$\u{00A0}CA")
        XCTAssertEqual(L10nFormat.money(minorUnits: 205, currency: "gbp", locale: .en), "GBP\u{00A0}2.05")
        XCTAssertEqual(L10nFormat.money(minorUnits: 205, currency: "U$D", locale: .en), "U$D\u{00A0}2.05")
        XCTAssertEqual(L10nFormat.money(minorUnits: 205, currency: "   ", locale: .frCA), "2.05")
        XCTAssertEqual(L10nFormat.money(minorUnits: -205, currency: "x", locale: .en), "X\u{00A0}-2.05")
        XCTAssertEqual(L10nFormat.isoAmount(-2.5, isoCode: "eur", locale: .en), "-\u{20AC}2.50")
        XCTAssertEqual(L10nFormat.moneyOrBare(minorUnits: -120_425, currency: nil, locale: .frCA), "-1\u{00A0}204,25")
        XCTAssertEqual(L10nFormat.moneyOrBare(minorUnits: 24900, currency: "usd", locale: .en), "$249.00")
    }

    /// An unknown zone reads as UTC; a 12-hour English clock also runs in Australia.
    func testTimeEdges() {
        let instant = Date(timeIntervalSince1970: 1_790_000_000) // 2026-09-21T14:13:20Z, a Monday
        XCTAssertEqual(L10nFormat.time(instant, timezone: "Not/AZone", locale: .en), "14:13")
        XCTAssertEqual(L10nFormat.time(instant, timezone: "Australia/Sydney", locale: .en), "12:13 a.m.")
        XCTAssertEqual(L10nFormat.time(instant, timezone: "UTC", locale: .frCA), "14 h 13")
        XCTAssertEqual(
            L10nFormat.date(instant, timezone: "UTC", style: .full, locale: .frCA),
            "lundi 21 septembre 2026"
        )
    }

    func testTheCalendarTables() {
        XCTAssertEqual(L10nFormat.monthAbbreviation(9, locale: .en), "Sep")
        XCTAssertEqual(L10nFormat.monthAbbreviation(9, locale: .frCA), "sept.")
        XCTAssertNil(L10nFormat.monthAbbreviation(0, locale: .en))
        XCTAssertNil(L10nFormat.monthAbbreviation(13, locale: .frCA))
        XCTAssertEqual(L10nFormat.monthName(2, locale: .frCA), "f\u{E9}vrier")
        XCTAssertEqual(L10nFormat.monthName(12, locale: .en), "December")
        XCTAssertEqual(L10nFormat.weekdayName(1, locale: .en), "Sunday")
        XCTAssertEqual(L10nFormat.weekdayName(7, locale: .frCA), "samedi")
        XCTAssertNil(L10nFormat.weekdayName(8, locale: .en))
        XCTAssertEqual(L10nFormat.weekdayAbbreviation(2, locale: .en), "Mon")
        XCTAssertEqual(L10nFormat.weekdayAbbreviation(2, locale: .frCA), "lun.")
        XCTAssertEqual(L10nFormat.meridiem(hour: 0), "AM")
        XCTAssertEqual(L10nFormat.meridiem(hour: 11), "AM")
        XCTAssertEqual(L10nFormat.meridiem(hour: 12), "PM")
    }

    // MARK: - French, end to end

    /// ⛔ THE FRENCH SMOKE TEST: everything the core formats follows the scoped language,
    /// with no locale passed anywhere, and the catalog text is the French
    /// (``L10nRuntime/isFrenchComplete`` is true).
    func testFrenchFollowsTheRuntimeWithNoLocalePassed() {
        let instant = Date(timeIntervalSince1970: 1_790_000_000)
        L10nRuntime.withLocale(.frCA) {
            XCTAssertEqual(L10nFormat.money(minorUnits: 24900, currency: "cad"), "249,00\u{00A0}$\u{00A0}CA")
            XCTAssertEqual(L10nFormat.dateTime(instant, timezone: "America/Toronto"), "21 sept. 2026, 10 h 13")
            XCTAssertEqual(L10nFormat.minutesSeconds(65), "1\u{00A0}min 5\u{00A0}s")
            XCTAssertEqual(L10nFormat.percent(ratio: 0.38), "38\u{00A0}%")
            XCTAssertEqual(L10nFormat.number(1204.25), "1\u{00A0}204,25")
            XCTAssertEqual(L10nFormat.list(["A", "B", "C"]), "A, B et C")
            XCTAssertEqual(L10nFormat.monthAbbreviation(12), "d\u{E9}c.")
            XCTAssertEqual(
                SchedulingCopy.overviewEventTypes(1204, "3"),
                "1\u{00A0}204 types de rendez-vous, actifs\u{00A0}: 3"
            )
            XCTAssertEqual(
                ApiErrorText.sentence(for: "unauthorized"),
                "Veuillez vous connecter pour continuer."
            )
            XCTAssertEqual(WireLabel.label(.callStatus, "queued"), "Autre")
        }
        L10nRuntime.withLocale(.en) {
            XCTAssertEqual(L10nFormat.money(minorUnits: 24900, currency: "cad"), "CA$249.00")
            XCTAssertEqual(L10nFormat.dateTime(instant, timezone: "America/Toronto"), "Sep 21, 2026, 10:13 a.m.")
            XCTAssertEqual(SchedulingCopy.overviewEventTypes(1204, "3"), "1204 event types, 3 active")
        }
    }
}
