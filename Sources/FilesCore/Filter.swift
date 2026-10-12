import Foundation

public enum Filter {
    /// Matches file names, ignoring case and accents. What you type is tried as an exact phrase first
    /// ("file 1" finds "file 12.txt" but not "file 21.txt"); if nothing contains the phrase, every word
    /// must appear in any order ("meeting notes" finds "Notes - weekly meeting.md").
    /// Tags are matched only when asked for: "tag:red" or "#red" (just "#" means any tagged item).
    ///
    /// Operators narrow the results, and combine with words and each other:
    /// - `kind:image` (also pdf, document, spreadsheet, video, audio, archive, code, folder, app)
    /// - `ext:pdf`
    /// - `size>10mb`, `size<500kb` (units b, kb, mb, gb)
    /// - `newer:7d`, `older:1y` (units h, d, w, m for 30 days, y)
    public static func filter(_ items: [FileItem], text: String, now: Date = Date()) -> [FileItem] {
        let allWords = text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !allWords.isEmpty else { return items }
        var operators: [(FileItem) -> Bool] = []
        var words: [String] = []
        for w in allWords {
            if tagQuery(w) == nil, let op = operatorPredicate(w, now: now) { operators.append(op) } else { words.append(w) }
        }
        let items = operators.isEmpty ? items : items.filter { item in operators.allSatisfy { $0(item) } }
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

    // MARK: operators

    static let kindExtensions: [String: Set<String>] = [
        "image": ["png", "jpg", "jpeg", "gif", "heic", "webp", "tiff", "tif", "bmp", "svg", "raw", "psd"],
        "pdf": ["pdf"],
        "document": ["doc", "docx", "pages", "txt", "md", "rtf", "odt"],
        "spreadsheet": ["xls", "xlsx", "csv", "numbers", "ods"],
        "video": ["mov", "mp4", "m4v", "avi", "mkv", "webm"],
        "audio": ["mp3", "m4a", "wav", "aiff", "flac", "aac", "ogg"],
        "archive": ["zip", "gz", "tar", "7z", "rar", "dmg", "tgz", "bz2"],
        "code": ["swift", "js", "ts", "tsx", "jsx", "py", "go", "rs", "java", "kt", "c", "cpp", "h", "m", "rb", "php", "sh", "json", "yml", "yaml", "html", "css"],
    ]

    static func operatorPredicate(_ word: String, now: Date) -> ((FileItem) -> Bool)? {
        let w = word.lowercased()
        if w.hasPrefix("kind:") {
            let group = String(w.dropFirst(5))
            if group.isEmpty { return { _ in true } }   // still typing
            let names = ["folder", "app"] + kindExtensions.keys
            guard let match = names.sorted().first(where: { $0.hasPrefix(group) }) else { return { _ in false } }
            switch match {
            case "folder": return { $0.isFolder }
            case "app": return { $0.url.pathExtension.lowercased() == "app" }
            default: return { !$0.isFolder && kindExtensions[match]?.contains($0.url.pathExtension.lowercased()) == true }
            }
        }
        if w.hasPrefix("ext:") {
            let ext = w.dropFirst(4).drop { $0 == "." }
            return ext.isEmpty ? { _ in true } : { !$0.isFolder && $0.url.pathExtension.lowercased() == ext }
        }
        if w.hasPrefix("size>") || w.hasPrefix("size<") {
            guard let bytes = parseSize(String(w.dropFirst(5))) else { return nil }
            let bigger = w.hasPrefix("size>")
            return { item in item.size.map { bigger ? $0 > bytes : $0 < bytes } ?? false }
        }
        if w.hasPrefix("newer:") || w.hasPrefix("older:") {
            guard let seconds = parseDuration(String(w.dropFirst(6))) else { return nil }
            let newer = w.hasPrefix("newer:")
            let cutoff = now.addingTimeInterval(-seconds)
            return { item in item.modified.map { newer ? $0 > cutoff : $0 < cutoff } ?? false }
        }
        return nil
    }

    static func parseSize(_ s: String) -> Int64? {
        let units: [(String, Double)] = [("gb", 1e9), ("mb", 1e6), ("kb", 1e3), ("b", 1)]
        for (suffix, factor) in units where s.hasSuffix(suffix) {
            return Double(s.dropLast(suffix.count)).map { Int64($0 * factor) }
        }
        return Double(s).map { Int64($0) }   // bare number = bytes
    }

    static func parseDuration(_ s: String) -> TimeInterval? {
        guard let unit = s.last, let n = Double(s.dropLast()) else { return nil }
        let per: [Character: Double] = ["h": 3600, "d": 86_400, "w": 604_800, "m": 2_592_000, "y": 31_536_000]
        return per[unit].map { n * $0 }
    }
}
