import Foundation

/// Makes real-world provider XML parseable.
///
/// `XMLParser` is strict, and provider guides are not. Measured against the
/// malformations panels actually emit, seven of eight killed the parser
/// outright — and because every `<programme>` element comes after every
/// `<channel>`, a single bad byte a third of the way in costs the whole
/// schedule. The user sees an empty guide and no reason for it.
///
/// So the input gets a ladder of repairs, each one aimed at a failure seen in
/// the wild, applied only when it changes something. Nothing here alters
/// meaning: it fixes encoding and escaping, never content.
public enum XMLRepair {

    /// What had to be fixed, so the app can say the guide was repaired rather
    /// than pretending it arrived clean.
    public enum Fix: String, Sendable, CaseIterable, Codable {
        case leadingJunk
        case encoding
        case controlCharacters
        case undefinedEntities
        case bareAmpersands
        case strayAngleBrackets
        case truncation
    }

    public struct Result: Sendable {
        public var data: Data
        public var fixes: [Fix]
        public var isRepaired: Bool { !fixes.isEmpty }
    }

    /// Returns repaired data, or nil when there was nothing to repair.
    public static func repair(_ data: Data) -> Result? {
        var fixes: [Fix] = []

        // 1. Anything before the first tag: byte-order marks, stray newlines,
        //    the occasional proxy banner.
        var working = data
        if let start = working.firstIndex(of: UInt8(ascii: "<")), start != working.startIndex {
            working = Data(working[start...])
            fixes.append(.leadingJunk)
        }

        // 2. Encoding. Panels serving Europe routinely declare UTF-8 and send
        //    Latin-1, which fails on the first accented character.
        var text: String
        if let utf8 = String(data: working, encoding: .utf8) {
            text = utf8
        } else if let latin1 = String(data: working, encoding: .isoLatin1) {
            text = latin1
            fixes.append(.encoding)
        } else {
            text = String(decoding: working, as: UTF8.self)
            fixes.append(.encoding)
        }

        // The declaration must not contradict what we are about to hand over.
        if fixes.contains(.encoding) {
            let corrected = text.replacingOccurrences(
                of: #"(<\?xml[^>]*encoding=")[^"]*(")"#,
                with: "$1UTF-8$2",
                options: .regularExpression
            )
            text = corrected
        }

        // 3. Control characters XML 1.0 forbids outright. Tab, newline and
        //    carriage return are the only ones below 0x20 that are legal.
        let cleaned = String(text.unicodeScalars.filter { scalar in
            scalar.value >= 0x20 || scalar == "\t" || scalar == "\n" || scalar == "\r"
        })
        if cleaned != text {
            text = cleaned
            fixes.append(.controlCharacters)
        }

        // 4. Entities. XML predefines five; everything else is fatal, and EPG
        //    text is full of HTML entities from whatever scraped it.
        let (entitiesFixed, entityFix) = repairEntities(text)
        if let entityFix {
            text = entitiesFixed
            fixes.append(entityFix)
        }

        // 5. A `<` that does not begin a tag. Rare, but fatal when it happens.
        let (anglesFixed, didFixAngles) = repairStrayAngleBrackets(text)
        if didFixAngles {
            text = anglesFixed
            fixes.append(.strayAngleBrackets)
        }

        // 6. A download that stopped early. Closing the root recovers every
        //    complete element before the cut.
        if let closed = closingTruncatedRoot(text) {
            text = closed
            fixes.append(.truncation)
        }

        guard !fixes.isEmpty, let repaired = text.data(using: .utf8) else { return nil }
        return Result(data: repaired, fixes: fixes)
    }

    // MARK: - Entities

    /// XML's five predefined entities. Everything else must be numeric or
    /// declared, and provider text is neither.
    private static let predefined: Set<String> = ["lt", "gt", "amp", "quot", "apos"]

    /// The HTML entities that actually turn up in programme titles and plots.
    private static let htmlEntities: [String: String] = [
        "nbsp": "\u{00A0}", "eacute": "é", "egrave": "è", "ecirc": "ê", "euml": "ë",
        "aacute": "á", "agrave": "à", "acirc": "â", "auml": "ä", "aring": "å",
        "aelig": "æ", "oslash": "ø", "oacute": "ó", "ograve": "ò", "ocirc": "ô",
        "ouml": "ö", "iacute": "í", "icirc": "î", "iuml": "ï", "uacute": "ú",
        "ugrave": "ù", "ucirc": "û", "uuml": "ü", "ccedil": "ç", "ntilde": "ñ",
        "szlig": "ß", "Aring": "Å", "Aelig": "Æ", "AElig": "Æ", "Oslash": "Ø",
        "Auml": "Ä", "Ouml": "Ö", "Uuml": "Ü", "Eacute": "É",
        "mdash": "—", "ndash": "–", "hellip": "…", "rsquo": "’", "lsquo": "‘",
        "ldquo": "“", "rdquo": "”", "bull": "•", "middot": "·", "deg": "°",
        "copy": "©", "reg": "®", "trade": "™", "euro": "€", "pound": "£",
        "laquo": "«", "raquo": "»", "shy": "", "iexcl": "¡", "iquest": "¿",
    ]

    /// Rewrites every ampersand that XML would reject.
    ///
    /// Known HTML entities become the character they mean; unknown ones and
    /// bare ampersands are escaped so the text survives verbatim.
    static func repairEntities(_ text: String) -> (String, Fix?) {
        guard text.contains("&") else { return (text, nil) }

        var output = ""
        output.reserveCapacity(text.count)
        var replacedNamedEntity = false
        var escapedBareAmpersand = false

        var index = text.startIndex
        while let ampersand = text[index...].firstIndex(of: "&") {
            output += text[index..<ampersand]

            // An entity reference is short; anything longer is a stray `&`.
            let limit = text.index(ampersand, offsetBy: 12, limitedBy: text.endIndex) ?? text.endIndex
            let window = text[ampersand..<limit]

            if let semicolon = window.firstIndex(of: ";") {
                let name = String(text[text.index(after: ampersand)..<semicolon])
                if name.hasPrefix("#"), isNumericReference(name) {
                    output += text[ampersand...semicolon]
                } else if predefined.contains(name) {
                    output += text[ampersand...semicolon]
                } else if let character = htmlEntities[name] {
                    output += character
                    replacedNamedEntity = true
                } else {
                    // Unknown name: keep the text, lose the entity meaning.
                    output += "&amp;\(name);"
                    replacedNamedEntity = true
                }
                index = text.index(after: semicolon)
            } else {
                output += "&amp;"
                escapedBareAmpersand = true
                index = text.index(after: ampersand)
            }
        }
        output += text[index...]

        let fix: Fix? =
            replacedNamedEntity ? .undefinedEntities
            : escapedBareAmpersand ? .bareAmpersands
            : nil
        return (output, fix)
    }

    private static func isNumericReference(_ name: String) -> Bool {
        let digits = name.dropFirst()
        if digits.first == "x" || digits.first == "X" {
            let hex = digits.dropFirst()
            return !hex.isEmpty && hex.allSatisfy(\.isHexDigit)
        }
        return !digits.isEmpty && digits.allSatisfy(\.isNumber)
    }

    // MARK: - Angle brackets

    /// Escapes a `<` that is not the start of a tag, comment or declaration.
    static func repairStrayAngleBrackets(_ text: String) -> (String, Bool) {
        // A tag starts with a letter, `/`, `!` or `?`. Anything else is text.
        let pattern = #"<(?![A-Za-z/!?])"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return (text, false) }
        let range = NSRange(text.startIndex..., in: text)
        guard regex.firstMatch(in: text, range: range) != nil else { return (text, false) }
        let fixed = regex.stringByReplacingMatches(in: text, range: range, withTemplate: "&lt;")
        return (fixed, true)
    }

    // MARK: - Truncation

    /// Closes an unterminated document so the elements that did arrive parse.
    ///
    /// Only the root is closed, and only when the file plainly stops mid-way —
    /// a partial guide is far better than none, and a complete one is left
    /// untouched.
    static func closingTruncatedRoot(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.hasSuffix("</tv>") else { return nil }
        guard trimmed.contains("<tv") else { return nil }

        // Drop whatever fragment of an element was cut off mid-write.
        var body = trimmed
        if let lastClose = body.lastIndex(of: ">") {
            body = String(body[...lastClose])
        }
        // A `<programme>` opened but never closed would still be fatal.
        if let lastOpen = body.range(of: "<programme", options: .backwards),
           body.range(of: "</programme>", options: .backwards)?.upperBound ?? body.startIndex
            < lastOpen.lowerBound {
            body = String(body[..<lastOpen.lowerBound])
        }
        return body + "</tv>"
    }
}
