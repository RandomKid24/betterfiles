import AppKit

/// Remembers recent copied text (memory only, never written to disk). Skips items that password managers
/// mark as concealed or transient.
@MainActor
final class ClipboardHistory {
    private(set) var items: [String] = []
    private var lastCount = NSPasteboard.general.changeCount
    private var timer: Timer?

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        timer?.tolerance = 0.6   // lets macOS batch these wakeups with others to save battery
    }

    private func poll() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastCount else { return }
        lastCount = pb.changeCount
        guard LSettings.shared.clipboard else { items.removeAll(); return }   // turned off: collect nothing
        let types = pb.types?.map(\.rawValue) ?? []
        guard !types.contains("org.nspasteboard.ConcealedType"), !types.contains("org.nspasteboard.TransientType"),
              let text = pb.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty, text.count <= 2000 else { return }
        items.removeAll { $0 == text }
        items.insert(text, at: 0)
        if items.count > 30 { items.removeLast() }
    }
}
