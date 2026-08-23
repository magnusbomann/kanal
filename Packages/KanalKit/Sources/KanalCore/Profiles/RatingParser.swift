import Foundation

/// Turns whatever a rating was written as into one number.
///
/// Ratings arrive in three shapes and none of them agree: national board codes
/// ("PG-13", "FSK 16", "U"), bare ages ("15", "18+"), and marketing noise a
/// provider stuffed into a title ("[VOKSEN]"). All three collapse to
/// `MaturityRating` here, and anything not recognised collapses to `nil` —
/// which the policy treats as *unrated*, not as *safe*.
public enum RatingParser {

    /// National certification codes, keyed by ISO country, in the systems TMDB
    /// actually returns for a Nordic viewer.
    ///
    /// Only boards whose steps map cleanly are listed. A guess here would be
    /// invisible until it let something through.
    private static let boards: [String: [String: Int]] = [
        "NO": ["A": 0, "6": 6, "7": 9, "9": 9, "11": 12, "12": 12, "15": 15, "18": 18],
        "DK": ["A": 0, "7": 9, "11": 12, "15": 15],
        // Sweden writes these out in words as often as not.
        "SE": [
            "Btl": 0, "Barntillåten": 0, "Från 7 år": 9, "7": 9, "11": 12,
            "Från 11 år": 12, "15": 15, "Från 15 år": 15,
        ],
        // Finland prefixes an age with K, and uses S or T for "everyone".
        //
        // A 16 becomes fifteen, not eighteen. Countries with a 16 step have no
        // 15 — 16 *is* their equivalent of Norway's 15, and mapping it up to 18
        // treated an ordinary teenage film as adults-only. Rounding is for
        // steps that fall between ours, not for a step that plainly matches.
        "FI": [
            "S": 0, "T": 0, "K7": 9, "7": 9, "K12": 12, "12": 12,
            "K16": 15, "16": 15, "K18": 18, "18": 18,
        ],
        "IS": ["L": 0, "6": 6, "9": 9, "12": 12, "16": 15, "18": 18],
        "US": [
            "G": 0, "TV-Y": 0, "TV-G": 0, "TV-Y7": 9, "PG": 9, "TV-PG": 9,
            "PG-13": 12, "TV-14": 15, "R": 15, "TV-MA": 18, "NC-17": 18,
        ],
        "GB": ["U": 0, "PG": 9, "12": 12, "12A": 12, "15": 15, "18": 18, "R18": 18],
        "DE": ["0": 0, "6": 6, "12": 12, "16": 15, "18": 18],
        "NL": ["AL": 0, "6": 6, "9": 9, "12": 12, "14": 15, "16": 15, "18": 18],
        "FR": ["U": 0, "10": 12, "12": 12, "16": 15, "18": 18],
        "ES": ["APTA": 0, "7": 9, "12": 12, "16": 15, "18": 18],
        "IT": ["T": 0, "6": 6, "12": 12, "14": 15, "18": 18],
        "AU": ["G": 0, "PG": 9, "M": 15, "MA15+": 15, "R18+": 18, "X18+": 18],
    ]

    /// A rating as one country's board wrote it.
    ///
    /// - Parameters:
    ///   - code: the certification string, e.g. `"PG-13"`.
    ///   - country: ISO country the code belongs to. Without it the same
    ///     string means different ages — a bare `"12"` is twelve everywhere,
    ///     but `"M"` is fifteen in Australia and nothing at all elsewhere.
    public static func rating(code: String, country: String?) -> MaturityRating? {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let country, let table = boards[country.uppercased()] {
            if let age = lookup(trimmed, in: table) { return MaturityRating.nearest(atLeast: age) }
        }

        // No country, or a code that country's board does not use. A bare
        // number is unambiguous enough to read on its own; a letter code is
        // not, so it is only accepted when a board claimed it.
        if let age = bareAge(in: trimmed) { return MaturityRating.nearest(atLeast: age) }

        // Codes that mean the same thing wherever they appear, and only those.
        if let known = lookup(trimmed, in: boards["US"] ?? [:]) {
            return MaturityRating.nearest(atLeast: known)
        }

        // Last resort: a code carrying exactly one number is stating an age.
        //
        // Boards invent notation faster than any table is maintained — "K7",
        // "Från 15 år", "B-15", "U/A 16+" — and every one of them puts the age
        // in the string. Read only when there is a single number and it is a
        // plausible age, so nothing is inferred from a code that has none.
        return singleAge(in: trimmed).map(MaturityRating.nearest(atLeast:))
    }

    /// Any age limit stated in free text — a provider's category or title.
    ///
    /// Deliberately narrow: it reads "18+", "(15)", "aldersgrense 12". It does
    /// not try to infer an age from words like "family", because a wrong guess
    /// here is a rating the app would then present as verified.
    public static func rating(inText text: String) -> MaturityRating? {
        let lowered = text.lowercased()
        for pattern in agePatterns {
            guard let match = pattern.firstMatch(
                in: lowered, range: NSRange(lowered.startIndex..., in: lowered)
            ), match.numberOfRanges > 1,
                let range = Range(match.range(at: 1), in: lowered),
                let age = Int(lowered[range])
            else { continue }
            guard (0...21).contains(age) else { continue }
            return MaturityRating.nearest(atLeast: age)
        }
        return nil
    }

    // MARK: - Matching

    private static func lookup(_ code: String, in table: [String: Int]) -> Int? {
        if let exact = table[code] { return exact }
        let folded = code.uppercased().replacingOccurrences(of: " ", with: "")
        for (key, age) in table where key.uppercased().replacingOccurrences(of: " ", with: "") == folded {
            return age
        }
        return nil
    }

    /// `"18"`, `"18+"`, `"[18]"` — a number and nothing else of substance.
    private static func bareAge(in code: String) -> Int? {
        let digits = code.filter(\.isNumber)
        guard !digits.isEmpty, digits.count == code.filter({ $0.isNumber || $0.isLetter }).count,
              let age = Int(digits), (0...21).contains(age)
        else { return nil }
        return age
    }

    /// The one number in a rating code, when there is exactly one.
    private static func singleAge(in code: String) -> Int? {
        var numbers: [Int] = []
        var current = ""
        for character in code {
            if character.isNumber {
                current.append(character)
            } else if !current.isEmpty {
                numbers.append(Int(current) ?? -1)
                current = ""
            }
        }
        if !current.isEmpty { numbers.append(Int(current) ?? -1) }

        guard numbers.count == 1, let age = numbers.first, (0...21).contains(age) else {
            return nil
        }
        return age
    }

    private static let agePatterns: [NSRegularExpression] = {
        let sources = [
            // "18+", "15 +"
            #"\b(\d{1,2})\s*\+"#,
            // "fsk 16", "aldersgrense 12", "rated 15", "age 9"
            #"\b(?:fsk|aldersgrense|aldersgräns|rated|rating|age|åldersgräns)\s*:?\s*(\d{1,2})\b"#,
            // "(15)", "[18]"
            #"[\(\[](\d{1,2})[\)\]]"#,
        ]
        return sources.compactMap { try? NSRegularExpression(pattern: $0) }
    }()
}
