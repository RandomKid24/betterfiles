import Foundation

public enum Filter {
    /// Matches file names, ignoring case and accents. What you type is tried as an exact phrase first
    /// ("file 1" finds "file 12.txt" but not "file 21.txt"); if nothing contains the phrase, every word
    /// must appear in any order ("meeting notes" finds "Notes - weekly meeting.md").
    /// Tags are matched only when asked for: "tag:red" or "#red" (just "#" means any tagged item).
    public static func filter(_ items: [FileItem], text: String) -> [FileItem] {
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return items }
        let tagWords = words.compactMap(tagQuery)
        let nameWords = words.filter { tagQuery($0) == nil }

        func hit(_ s: String, _ w: String) -> Bool { s.range(of: w, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        func tagsOK(_ item: FileItem) -> Bool {
            tagWords.allSatisfy { tag in tag.isEmpty ? !item.tags.isEmpty : item.tags.contains { hit($0, tag) } }
        }
        let tagged = tagWords.isEmpty ? items : items.filter(tagsOK)
        guard !nameWords.isEmpty else { return tagged }

        let phrase = nameWords.joined(separator: " ")
        let exact = tagged.filter { hit($0.name, phrase) }
        if !exact.isEmpty || nameWords.count == 1 { return exact }
        return tagged.filter { item in nameWords.allSatisfy { hit(item.name, $0) } }
    }

    /// "tag:red" -> "red", "#red" -> "red", "#" -> "", anything else -> nil.
    static func tagQuery(_ word: String) -> String? {
        if word.hasPrefix("#") { return String(word.dropFirst()) }
        if word.lowercased().hasPrefix("tag:") { return String(word.dropFirst(4)) }
        return nil
    }
}
