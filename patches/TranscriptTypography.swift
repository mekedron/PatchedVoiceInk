// Injected by patches/apply.py from the `patch` branch.
// Restores characters that Parakeet's tokenizer cannot produce. The v3 family
// (V3, Ultra) has no "ё", "Ё" or dash tokens: it emits "<unk>" where it hears
// "ё" and a spaced hyphen where a dash belongs. VoiceInk runs this before the
// user's dictionary, so dictionary rules see the restored text.

import Foundation

enum TranscriptTypography {
    static func normalize(_ text: String) -> String {
        restoreDashes(in: restoreYo(in: text))
    }

    /// "<unk>" becomes "ё", or "Ё" when it opens a sentence or the next letter
    /// is uppercase. The tokenizer has no other Cyrillic gaps, so in Russian
    /// text "<unk>" is "ё".
    static func restoreYo(in text: String) -> String {
        let marker = "<unk>"
        guard text.contains(marker) else { return text }

        var result = ""
        var rest = Substring(text)
        while let range = rest.range(of: marker) {
            let before = result + rest[..<range.lowerBound]
            let after = rest[range.upperBound...]
            result = before + (isUppercaseContext(before: before, after: after) ? "Ё" : "ё")
            rest = after
        }
        return result + rest
    }

    /// " - " between two words becomes " — ". Hyphens inside words
    /// ("ёлки-палки") and ranges ("5-10") have no spaces and stay.
    static func restoreDashes(in text: String) -> String {
        text.replacingOccurrences(
            of: #"(?<=\S) - (?=\S)"#,
            with: " — ",
            options: .regularExpression
        )
    }

    private static func isUppercaseContext(before: String, after: Substring) -> Bool {
        if let next = after.first, next.isUppercase { return true }
        // Inside a word ("вс<unk>", "е<unk>") the letter is never a capital.
        if let previous = before.last, previous.isLetter || previous.isNumber { return false }
        let trimmed = before.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = trimmed.last else { return true }
        return ".!?…".contains(last)
    }
}
