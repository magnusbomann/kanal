import Foundation

/// Folds text down to something two spellings of the same title can agree on.
///
/// Foundation's diacritic folding handles `ä → a`, but Nordic `ø`, `æ` and the
/// German `ß` are separate letters with no decomposition, so they survive it
/// untouched. Searching "skjonnheten" would then miss "Skjønnheten" — which is
/// exactly what a person typing on a keyboard without those keys does.
public enum SearchNormalizer {

    /// Letters that behave like an accented vowel to a reader, but are their
    /// own code point to Unicode.
    private static let letterFolds: [Character: String] = [
        "ø": "o", "æ": "ae", "å": "a",
        "ð": "d", "þ": "th", "ß": "ss",
        "ł": "l", "đ": "d",
    ]

    /// Lowercased, accent-free, punctuation-free. Words separated by spaces.
    public static func normalize(_ input: String) -> String {
        let lowered = input.lowercased()

        var folded = ""
        folded.reserveCapacity(lowered.count)
        for character in lowered {
            if let replacement = letterFolds[character] {
                folded += replacement
            } else {
                folded.append(character)
            }
        }

        // en_US keeps the folding rules stable regardless of device locale.
        let stripped = folded.folding(
            options: [.diacriticInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_US")
        )

        var result = ""
        result.reserveCapacity(stripped.count)
        var lastWasSpace = true
        for character in stripped {
            if character.isLetter || character.isNumber {
                result.append(character)
                lastWasSpace = false
            } else if !lastWasSpace {
                result.append(" ")
                lastWasSpace = true
            }
        }
        if result.hasSuffix(" ") { result.removeLast() }
        return result
    }

    public static func tokenize(_ input: String) -> [String] {
        normalize(input).split(separator: " ").map(String.init)
    }
}
