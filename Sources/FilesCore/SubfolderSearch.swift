import Foundation

/// Finds files inside a folder and everything below it, using the same search words and operators as the filter box.
public enum SubfolderSearch {
    static let skippedFolders: Set<String> = ["node_modules"]

    /// Blocking: call off the main thread. `shouldStop` is polled so a newer search can cancel this one.
    public static func find(in root: URL, text: String, includeHidden: Bool, limit: Int = 5000, shouldStop: () -> Bool = { false }) -> [FileItem] {
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return [] }
        // Names are checked first (cheap). Only files whose names could match get their attributes read,
        // which matters in big trees because tags and dates cost a disk read each.
        let nameWords = words.filter { $0.hasPrefix("#") == false && !$0.lowercased().hasPrefix("tag:") && Filter.operatorPredicate($0, now: Date()) == nil }
        var options: FileManager.DirectoryEnumerationOptions = [.skipsPackageDescendants]
        if !includeHidden { options.insert(.skipsHiddenFiles) }
        guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: options) else { return [] }

        var candidates: [FileItem] = []
        var examined = 0
        for case let url as URL in e {
            if examined % 512 == 0, shouldStop() { return [] }
            examined += 1
            if skippedFolders.contains(url.lastPathComponent), (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                e.skipDescendants()
                continue
            }
            let name = url.lastPathComponent
            // With name words, at least one has to appear; with only operators or tags, every item is a candidate.
            if !nameWords.isEmpty, !nameWords.contains(where: { name.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }) { continue }
            candidates.append(FileItem(url: url))
            if candidates.count >= 50_000 { break }
        }
        let full = candidates.map { FolderListing.item(for: $0.url) }
        return Array(Filter.filter(full, text: text).prefix(limit))
    }
}
