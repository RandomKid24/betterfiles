import Foundation

public enum SpotlightQuery {
    /// MDQuery string for a word-prefix match on the display name, or nil if the text is too short to query.
    /// Word-prefix (`w`) uses Spotlight's index, so it stays fast; a "contains" scan takes seconds on short text.
    /// User text is spliced into the string, so quote, backslash and wildcard characters are removed.
    public static func mdString(for text: String) -> String? {
        let cleaned = String(text.trimmingCharacters(in: .whitespacesAndNewlines)
            .filter { !"\"\\*?".contains($0) })
        guard cleaned.count >= 2 else { return nil }
        return "kMDItemDisplayName == \"\(cleaned)*\"wcd"
    }
}
