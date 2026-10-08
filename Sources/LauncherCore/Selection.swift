import Foundation

public enum Selection {
    /// Row to highlight after results change: the previously selected path if still present, else 0.
    public static func index(of path: String?, in results: [Candidate]) -> Int {
        guard let path else { return 0 }
        return results.firstIndex { $0.path == path } ?? 0
    }
}
