import DistrictL10n

/// The place a number's leading digits name, for DISCLOSURE only.
///
/// ⛔ NOTHING HERE EVER CHANGES WHAT IS DIALLED, AND THAT IS THE WHOLE DESIGN.
/// `POST /api/district/calls/dial` runs its own `normalizePhoneNumber` and then
/// checks Do-Not-Call, resolves the Contact and instructs the carrier against
/// THAT form, so a client that rewrote the operator's text would ship a second
/// opinion about numbers whose disagreements are invisible until a call reaches
/// a number the compliance screen never saw. The Kotlin `DialFormat.kt` makes
/// the identical argument about its display grouping. This type reads the
/// string and says something about it; it never hands one back to be sent.
public enum DialRegion: Sendable, Equatable {
    /// Nothing to name: no country code has been typed yet.
    case none

    /// A country code is present and matches no entry in ``DialEntry/callingCodes``.
    ///
    /// ⛔ SAID PLAINLY RATHER THAN GUESSED AT. An unknown code is still dialable
    /// (see ``DialEntry/assess(_:)``), because refusing every code this table has
    /// not heard of would make the client the authority on which countries exist.
    /// What it must never do is name the wrong one.
    case unrecognised

    /// The place the leading digits name.
    case named(String)
}

/// Why an entry may not be dialled.
///
/// ⛔ EVERY CASE IS SHOWN TO THE OPERATOR. A disabled Call button with no reason
/// is how the eight-digit floor already confused people; the refusal exists so
/// the screen can say what is missing rather than simply going grey.
public enum DialRefusal: Sendable, Equatable {
    /// Nothing typed. ⚠️ The keypad's own hint covers this one, so the screen
    /// says nothing extra.
    case empty

    /// No leading `+`, so the string names no country at all.
    ///
    /// ⛔ THE WRONG-COUNTRY DIAL'S SIBLING AND THE ONE UNAMBIGUOUS
    /// REFUSAL. A bare `4165550123` is dialled by the carrier as whatever its
    /// own default interprets it to be, and the server adds no country code
    /// either: `normalizePhoneNumber` strips punctuation and nothing else.
    case missingCountryCode

    /// Fewer than ``DialEntry/minimumDigits`` digits after the `+`.
    case tooShort

    /// More than ``DialEntry/maximumDigits`` digits after the `+`. E.164 stops
    /// at fifteen.
    case tooLong

    /// A `+` somewhere other than the front. ⚠️ Reachable from a paste, and from
    /// the `.phonePad` keyboard, which offers `+` on every keypress.
    case strayPlus

    /// An emergency number. ⛔ NOT AN ERROR THE OPERATOR SHOULD FIX, a hand-off.
    ///
    /// ⛔ IT IS TESTED FIRST, BEFORE ``missingCountryCode``, AND THE ORDER IS THE
    /// WHOLE FIX. Until this case existed, `911` fell through to
    /// `missingCountryCode`, whose copy reads "Start with a country code, for
    /// example +1", and following that instruction produces `+1911`, which was
    /// then refused as ``tooShort``. The app walked somebody trying to call for
    /// help into a second dead end. A flat refusal would have been better; the
    /// remediation copy made it worse.
    ///
    /// ⛔ THE REMEDY IS NEVER TO DIAL IT. Emergency calling over VoIP is a
    /// regulatory problem (E911 location, callback, PSAP routing) rather than a
    /// feature gap, so this app must not carry one. What it owes the user is to
    /// say so and name the Phone app, which can.
    case emergencyNumber
}

/// What one keypad entry discloses, and whether it may be dialled.
public struct DialEntryAssessment: Sendable, Equatable {
    /// Where the call will ring, as far as the leading digits say.
    public let region: DialRegion

    /// Why it may not be dialled, or nil when it may.
    public let refusal: DialRefusal?

    public init(region: DialRegion, refusal: DialRefusal?) {
        self.region = region
        self.refusal = refusal
    }

    public var isDialable: Bool {
        refusal == nil
    }
}

/// Reading a dial entry: which country it names, and whether it can be E.164.
///
/// ⛔ IT EXISTS BECAUSE A CALL REACHED THE WRONG COUNTRY AND WAS BILLED FOR IT.
/// An operator typed a Canadian mobile and the app dialled
/// `+4165550123`: Canada is `+1`, so the number should have been
/// `+14165550123`, and as sent the leading `+41` is SWITZERLAND. The only gate
/// on the button was a digit COUNT, which ten digits passes, and nothing on
/// either side of the wire had an opinion about the country code. The fix is
/// disclosure plus one unambiguous refusal, never a rewrite.
///
/// ⛔ PURE, AND ON PURPOSE. Every function here is a total function of a
/// `String`, with no clock and no I/O, which is what lets the whole of it be
/// tested on Linux where the screen that uses it cannot even compile. The one
/// input besides the string is the language a place is NAMED in
/// (``L10nRuntime/locale``); which place, and whether it may be dialled, never
/// depends on it.
public enum DialEntry {
    /// The E.164 floor, and the server's own: `POST /api/district/calls/dial`
    /// rejects anything shorter than 8 characters after normalising.
    public static let minimumDigits = 8

    /// The E.164 ceiling. ⚠️ Stricter than the route's `.max(32)` on the raw
    /// string, and deliberately: 32 characters is a length guard on a request
    /// body, not a statement about phone numbers.
    public static let maximumDigits = 15

    /// The longest calling code in ``callingCodes``.
    public static let maximumCallingCodeDigits = 3

    /// Short codes that must never be treated as a number to validate.
    ///
    /// ⚠️ SOURCE, SO THE LIST IS ARGUABLE RATHER THAN FOLKLORE: `112` and `911`
    /// are the two every handset must recognise under **3GPP TS 22.101 §10.1**,
    /// independent of SIM or network. The rest are the widely deployed national
    /// codes, `000` (AU), `111` (NZ), `999` (UK, IE, HK), `110`/`118`/`119`
    /// (JP, CN, and much of Europe), `113`/`115`/`117` (various EU).
    ///
    /// ⛔ IT IS DELIBERATELY INCOMPLETE AND THAT IS SAFE HERE, because the
    /// fallback is not a wrong call: no number under ``minimumDigits`` is
    /// dialable at all, so an emergency code this set misses is still REFUSED,
    /// it just gets the country-code sentence instead of the hand-off. Adding a
    /// code improves the message; omitting one never places a call.
    ///
    /// ⚠️ MATCHED WHOLE, NEVER AS A PREFIX. `+1 911 555 0100` is an ordinary
    /// North American number that begins with 911, and a prefix test would
    /// refuse it. It would also fire while somebody was still typing.
    public static let emergencyNumbers: Set<String> = [
        "000", "110", "111", "112", "113", "115", "117", "118", "119", "911", "999",
    ]

    /// Whether this entry is an emergency short code, in either shape it reaches.
    ///
    /// ⚠️ THE `+1` SHAPE IS CHECKED BECAUSE THE OLD COPY CREATED IT. "Start with
    /// a country code" plus `911` is `+1911`, and a user who followed the app's
    /// own instruction must land on the hand-off rather than on "too short".
    static func isEmergency(_ compacted: String) -> Bool {
        let digits = compacted.hasPrefix("+") ? String(compacted.dropFirst()) : compacted
        if emergencyNumbers.contains(digits) {
            return true
        }
        guard digits.hasPrefix("1") else { return false }
        return emergencyNumbers.contains(String(digits.dropFirst()))
    }

    /// Read one entry as the screen must present it.
    ///
    /// ⚠️ THE ORDER OF THE REFUSALS IS THE ORDER THE OPERATOR CAN ACT ON THEM.
    /// A missing country code is reported before a length, because "add +1" is
    /// the instruction either way and "too short" would send someone hunting
    /// for digits they already have.
    public static func assess(_ raw: String) -> DialEntryAssessment {
        let compact = compacted(raw)
        return DialEntryAssessment(
            region: disclosedRegion(forCompacted: compact),
            refusal: refusal(raw, compact)
        )
    }

    /// ⚠️ THE REGION IS COMPUTED WHATEVER THE REFUSAL SAYS, so a half-typed
    /// `+41…` already reads "Switzerland" while the button is still off. The
    /// disclosure is the part that catches a wrong country code, and it is
    /// worth least at the moment the number is finally long enough to dial.
    private static func refusal(_ raw: String, _ compact: String) -> DialRefusal? {
        guard !raw.allSatisfy(\.isWhitespace) else { return .empty }
        // ⛔ BEFORE THE COUNTRY-CODE CHECK. See the ⛔ on ``DialRefusal/emergencyNumber``:
        // this ordering IS the fix, and a test that only asserts "911 is refused" would
        // pass against the broken behaviour it replaces.
        guard !isEmergency(compact) else { return .emergencyNumber }
        guard compact.hasPrefix("+") else { return .missingCountryCode }
        let digits = compact.dropFirst()
        guard !digits.contains("+") else { return .strayPlus }
        guard digits.count >= minimumDigits else { return .tooShort }
        guard digits.count <= maximumDigits else { return .tooLong }
        return nil
    }

    /// The place an entry's calling code names, or nil when it names none.
    ///
    /// ⚠️ LONGEST PREFIX WINS, THREE DIGITS DOWN TO ONE, which is the only
    /// correct way to read a calling code: `+372` is Estonia while `+37` is
    /// unassigned, and a left-to-right reader would answer `+41…` with nothing
    /// at all. No entry in the table is a prefix of another, so the match is
    /// unambiguous rather than merely first.
    public static func callingCodeRegion(for raw: String) -> String? {
        let digits = leadingDigits(ofCompacted: compacted(raw))
        guard !digits.isEmpty else { return nil }
        let longest = min(maximumCallingCodeDigits, digits.count)
        for length in stride(from: longest, through: 1, by: -1) {
            if let name = callingCodes[String(digits.prefix(length))] {
                return name
            }
        }
        return nil
    }

    /// ⛔ MIRRORS THE SERVER'S `normalizePhoneNumber` EXACTLY: keep ASCII
    /// digits and `+`, drop everything else. It keeps a `+` wherever it appears
    /// rather than only at the front, because the server does, which is what
    /// makes ``DialRefusal/strayPlus`` a real state and not a theoretical one.
    private static func compacted(_ raw: String) -> String {
        String(raw.filter { $0 == "+" || isDigit($0) })
    }

    /// The digits of the calling code, i.e. everything between the leading `+`
    /// and the first character that is not a digit. Empty when there is no `+`.
    private static func leadingDigits(ofCompacted compact: String) -> Substring {
        guard compact.hasPrefix("+") else { return "" }
        return compact.dropFirst().prefix(while: isDigit)
    }

    private static func disclosedRegion(forCompacted compact: String) -> DialRegion {
        let digits = leadingDigits(ofCompacted: compact)
        guard !digits.isEmpty else { return .none }
        guard let name = callingCodeRegion(for: compact) else { return .unrecognised }
        return .named(name)
    }

    /// ⚠️ `isASCII` AS WELL AS `isNumber`. `Character.isNumber` is true for
    /// Arabic-Indic digits and for superscripts, none of which `\d` matches in
    /// the server's regex; without the first half the two sides would disagree
    /// about what counts as a digit. Public so the dialer's own digit floor
    /// counts the same characters this file does.
    public static func isDigit(_ character: Character) -> Bool {
        character.isASCII && character.isNumber
    }

    /// The calling codes, committed rather than fetched.
    ///
    /// ⚠️ IT IS A DISCLOSURE TABLE AND NOT A ROUTING TABLE, so being incomplete
    /// costs a label and never a call: an unlisted code reads
    /// ``DialRegion/unrecognised`` and stays dialable.
    ///
    /// ⛔ SEVERAL CODES ARE SHARED AND THE VALUE SAYS SO WHERE IT MATTERS. `+1`
    /// is the whole North American Numbering Plan, which is Canada, the United
    /// States and about twenty Caribbean territories; the label names the two
    /// countries this product sells numbers in, because the job here is to
    /// catch a WRONG country code rather than to identify a right one. `+7` is
    /// Russia and Kazakhstan on one code, and is labelled as both.
    ///
    /// ⚠️ NO ENTRY IS A PREFIX OF ANOTHER. `callingCodeRegion(for:)` relies on
    /// that for its longest-prefix walk, and `DialNumberTests` asserts it, so a
    /// future addition that broke the property fails rather than quietly
    /// shadowing a country.
    /// ⚠️ COMPUTED, NOT STORED: the names are in the active language (the catalog's
    /// `dial_region` entries), so a table built once would keep the language it was
    /// built in.
    public static var callingCodes: [String: String] {
        [
            "1": DialRegionCopy.code1,
            "7": DialRegionCopy.code7,
            "20": DialRegionCopy.code20,
            "27": DialRegionCopy.code27,
            "30": DialRegionCopy.code30,
            "31": DialRegionCopy.code31,
            "32": DialRegionCopy.code32,
            "33": DialRegionCopy.code33,
            "34": DialRegionCopy.code34,
            "36": DialRegionCopy.code36,
            "39": DialRegionCopy.code39,
            "40": DialRegionCopy.code40,
            "41": DialRegionCopy.code41,
            "43": DialRegionCopy.code43,
            "44": DialRegionCopy.code44,
            "45": DialRegionCopy.code45,
            "46": DialRegionCopy.code46,
            "47": DialRegionCopy.code47,
            "48": DialRegionCopy.code48,
            "49": DialRegionCopy.code49,
            "51": DialRegionCopy.code51,
            "52": DialRegionCopy.code52,
            "53": DialRegionCopy.code53,
            "54": DialRegionCopy.code54,
            "55": DialRegionCopy.code55,
            "56": DialRegionCopy.code56,
            "57": DialRegionCopy.code57,
            "58": DialRegionCopy.code58,
            "60": DialRegionCopy.code60,
            "61": DialRegionCopy.code61,
            "62": DialRegionCopy.code62,
            "63": DialRegionCopy.code63,
            "64": DialRegionCopy.code64,
            "65": DialRegionCopy.code65,
            "66": DialRegionCopy.code66,
            "81": DialRegionCopy.code81,
            "82": DialRegionCopy.code82,
            "84": DialRegionCopy.code84,
            "86": DialRegionCopy.code86,
            "90": DialRegionCopy.code90,
            "91": DialRegionCopy.code91,
            "92": DialRegionCopy.code92,
            "93": DialRegionCopy.code93,
            "94": DialRegionCopy.code94,
            "95": DialRegionCopy.code95,
            "98": DialRegionCopy.code98,
            "211": DialRegionCopy.code211,
            "212": DialRegionCopy.code212,
            "213": DialRegionCopy.code213,
            "216": DialRegionCopy.code216,
            "218": DialRegionCopy.code218,
            "220": DialRegionCopy.code220,
            "221": DialRegionCopy.code221,
            "233": DialRegionCopy.code233,
            "234": DialRegionCopy.code234,
            "251": DialRegionCopy.code251,
            "254": DialRegionCopy.code254,
            "255": DialRegionCopy.code255,
            "256": DialRegionCopy.code256,
            "260": DialRegionCopy.code260,
            "263": DialRegionCopy.code263,
            "264": DialRegionCopy.code264,
            "265": DialRegionCopy.code265,
            "267": DialRegionCopy.code267,
            "268": DialRegionCopy.code268,
            "299": DialRegionCopy.code299,
            "350": DialRegionCopy.code350,
            "351": DialRegionCopy.code351,
            "352": DialRegionCopy.code352,
            "353": DialRegionCopy.code353,
            "354": DialRegionCopy.code354,
            "355": DialRegionCopy.code355,
            "356": DialRegionCopy.code356,
            "357": DialRegionCopy.code357,
            "358": DialRegionCopy.code358,
            "359": DialRegionCopy.code359,
            "370": DialRegionCopy.code370,
            "371": DialRegionCopy.code371,
            "372": DialRegionCopy.code372,
            "373": DialRegionCopy.code373,
            "374": DialRegionCopy.code374,
            "375": DialRegionCopy.code375,
            "376": DialRegionCopy.code376,
            "377": DialRegionCopy.code377,
            "378": DialRegionCopy.code378,
            "380": DialRegionCopy.code380,
            "381": DialRegionCopy.code381,
            "382": DialRegionCopy.code382,
            "383": DialRegionCopy.code383,
            "385": DialRegionCopy.code385,
            "386": DialRegionCopy.code386,
            "387": DialRegionCopy.code387,
            "389": DialRegionCopy.code389,
            "420": DialRegionCopy.code420,
            "421": DialRegionCopy.code421,
            "423": DialRegionCopy.code423,
            "501": DialRegionCopy.code501,
            "502": DialRegionCopy.code502,
            "503": DialRegionCopy.code503,
            "504": DialRegionCopy.code504,
            "505": DialRegionCopy.code505,
            "506": DialRegionCopy.code506,
            "507": DialRegionCopy.code507,
            "591": DialRegionCopy.code591,
            "593": DialRegionCopy.code593,
            "595": DialRegionCopy.code595,
            "598": DialRegionCopy.code598,
            "852": DialRegionCopy.code852,
            "853": DialRegionCopy.code853,
            "855": DialRegionCopy.code855,
            "856": DialRegionCopy.code856,
            "880": DialRegionCopy.code880,
            "886": DialRegionCopy.code886,
            "960": DialRegionCopy.code960,
            "961": DialRegionCopy.code961,
            "962": DialRegionCopy.code962,
            "963": DialRegionCopy.code963,
            "964": DialRegionCopy.code964,
            "965": DialRegionCopy.code965,
            "966": DialRegionCopy.code966,
            "967": DialRegionCopy.code967,
            "968": DialRegionCopy.code968,
            "970": DialRegionCopy.code970,
            "971": DialRegionCopy.code971,
            "972": DialRegionCopy.code972,
            "973": DialRegionCopy.code973,
            "974": DialRegionCopy.code974,
            "975": DialRegionCopy.code975,
            "976": DialRegionCopy.code976,
            "977": DialRegionCopy.code977,
            "992": DialRegionCopy.code992,
            "993": DialRegionCopy.code993,
            "994": DialRegionCopy.code994,
            "995": DialRegionCopy.code995,
            "996": DialRegionCopy.code996,
            "998": DialRegionCopy.code998,
        ]
    }
}
