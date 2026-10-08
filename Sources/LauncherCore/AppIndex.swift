import Foundation

public enum AppIndex {
    public static let defaultDirs = [
        "/Applications", "/System/Applications", "/System/Library/CoreServices/Applications",
        NSHomeDirectory() + "/Applications",
    ]

    /// Finds `.app` bundles in `dirs`, one folder level deep (so `Utilities/` is covered). No Spotlight involved.
    public static func scan(dirs: [String] = defaultDirs) -> [Candidate] {
        let fm = FileManager.default
        var out: [Candidate] = []
        for dir in dirs {
            for entry in (try? fm.contentsOfDirectory(atPath: dir)) ?? [] where !entry.hasPrefix(".") {
                let path = dir + "/" + entry
                if entry.hasSuffix(".app") {
                    out.append(Candidate(name: (entry as NSString).deletingPathExtension, path: path, isApp: true))
                } else {
                    for inner in (try? fm.contentsOfDirectory(atPath: path)) ?? [] where inner.hasSuffix(".app") {
                        out.append(Candidate(name: (inner as NSString).deletingPathExtension, path: path + "/" + inner, isApp: true))
                    }
                }
            }
        }
        return out
    }
}
