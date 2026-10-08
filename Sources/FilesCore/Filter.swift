import Foundation

public enum Filter {
    public static func filter(_ items: [FileItem], text: String) -> [FileItem] {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return items }
        return items.filter { $0.name.range(of: t, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }
}
