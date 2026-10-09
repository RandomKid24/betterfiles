import Foundation

public enum Filter {
    public static func filter(_ items: [FileItem], text: String) -> [FileItem] {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return items }
        // Matches names and Finder tag names (so "red" finds red-tagged files too).
        func hit(_ s: String) -> Bool { s.range(of: t, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        return items.filter { hit($0.name) || $0.tags.contains(where: hit) }
    }
}
