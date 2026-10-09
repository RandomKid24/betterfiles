import Foundation

public enum Column: String, CaseIterable, Sendable {
    case name, modified, size, kind, created
}

public enum Sorter {
    /// When sorting by name, folders come first by default, in both directions. Other columns (date, size, kind)
    /// mix folders and files so the newest or largest item really is at the top. Ties always fall back to name ascending.
    public static func sort(_ items: [FileItem], by column: Column, ascending: Bool, foldersFirst: Bool = true) -> [FileItem] {
        items.sorted { a, b in
            if foldersFirst, column == .name, a.isFolder != b.isFolder { return a.isFolder }
            let r = compare(a, b, column)
            if r != .orderedSame { return ascending ? r == .orderedAscending : r == .orderedDescending }
            let n = compareNames(a.name, b.name)
            return n != .orderedSame ? n == .orderedAscending : a.name < b.name
        }
    }

    private static func compare(_ a: FileItem, _ b: FileItem, _ column: Column) -> ComparisonResult {
        switch column {
        case .name: return compareNames(a.name, b.name)
        case .modified: return cmp(a.modified ?? .distantPast, b.modified ?? .distantPast)
        case .created: return cmp(a.created ?? .distantPast, b.created ?? .distantPast)
        case .size: return cmp(a.size ?? -1, b.size ?? -1)
        case .kind: return compareNames(a.kind, b.kind)
        }
    }

    private static func compareNames(_ a: String, _ b: String) -> ComparisonResult {
        a.compare(b, options: [.caseInsensitive, .diacriticInsensitive, .numeric])
    }

    private static func cmp<T: Comparable>(_ a: T, _ b: T) -> ComparisonResult {
        a < b ? .orderedAscending : (a > b ? .orderedDescending : .orderedSame)
    }
}
