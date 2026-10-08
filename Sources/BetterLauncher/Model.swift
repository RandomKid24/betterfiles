import AppKit
import LauncherCore
import Observation

@MainActor @Observable
final class Model {
    var text = ""
    var results: [Candidate] = []
    var selected = 0
    var visible = false
    var onDismiss: () -> Void = {}

    @ObservationIgnored private let search = Search()
    @ObservationIgnored private let usage: Usage
    @ObservationIgnored private var apps: [Candidate] = []
    @ObservationIgnored private var base: [Candidate] = []   // apps + history: instant, no Spotlight
    @ObservationIgnored private var raw: [Candidate] = []    // streamed file hits

    init(usage: Usage) {
        self.usage = usage
        search.onResults = { [weak self] candidates in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.raw = candidates
                self.rerank()
            }
        }
        refreshApps()
    }

    func textChanged() {
        search.update(text)
        rerank(keepSelection: false)
    }

    func move(_ delta: Int) {
        guard !results.isEmpty else { return }
        selected = (selected + delta + results.count) % results.count
    }

    func openSelected() {
        guard results.indices.contains(selected) else { return }
        let c = results[selected]
        // Only record and hide when the open succeeded (file may have moved since indexing).
        if NSWorkspace.shared.open(URL(fileURLWithPath: c.path)) {
            usage.record(path: c.path)
            onDismiss()
        }
    }

    /// Called when the panel opens.
    func reset() {
        text = ""
        raw = []
        results = []
        selected = 0
        base = apps + usage.candidates()
        refreshApps()
    }

    /// Called once the panel is fully hidden: stop the live query so it doesn't run in the background.
    func didHide() {
        search.stop()
        raw = []
    }

    private func refreshApps() {
        Task.detached {
            let found = AppIndex.scan()
            await MainActor.run { self.apps = found; if self.base.isEmpty { self.base = found } }
        }
    }

    // Live Spotlight updates keep the user's highlighted row; a new query starts at the top.
    private func rerank(keepSelection: Bool = true) {
        let previous = keepSelection && results.indices.contains(selected) ? results[selected].path : nil
        var seen = Set<String>()
        let all = (base + raw).filter { seen.insert($0.path).inserted }
        results = Ranker.rank(query: text, candidates: all, usage: usage.get)
        selected = Selection.index(of: previous, in: results)
    }
}
