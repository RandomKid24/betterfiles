import Foundation

public enum Ranker {
    public static func rank(
        query: String,
        candidates: [Candidate],
        usage: (String) -> UsageRecord?,
        now: Date = Date(),
        limit: Int = 8
    ) -> [Candidate] {
        let q = fold(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !q.isEmpty else { return [] }

        let scored: [(Candidate, Double)] = candidates.compactMap { c in
            guard let m = matchScore(q, fold(c.name)) else { return nil }
            return (c, m + frecency(usage(c.path), now: now) + (c.isApp ? 15 : 0))
        }
        return scored.sorted {
            if $0.1 != $1.1 { return $0.1 > $1.1 }
            if $0.0.name.count != $1.0.name.count { return $0.0.name.count < $1.0.name.count }
            return $0.0.path < $1.0.path
        }.prefix(limit).map(\.0)
    }

    static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    static func matchScore(_ q: String, _ name: String) -> Double? {
        if name.hasPrefix(q) { return 100 }
        guard name.contains(q) else { return nil }
        let separators = [" ", "-", "_", ".", "/"]
        if separators.contains(where: { name.contains($0 + q) }) { return 60 }
        return 30
    }

    // 10 * log2(1 + opens), halved every 14 days since last open.
    static func frecency(_ r: UsageRecord?, now: Date) -> Double {
        guard let r else { return 0 }
        let days = max(0, now.timeIntervalSince(r.last) / 86_400)
        return 10 * log2(1 + Double(r.count)) * pow(0.5, days / 14)
    }
}
