import AppKit

/// Hands a path to Butterfinder: a running instance gets a distributed notification, otherwise the sibling
/// executable is started with the path as its argument.
enum FilesBridge {
    static let notification = Notification.Name("com.butterfinder.open")

    static func show(_ path: String, select: Bool) {
        let running = NSWorkspace.shared.runningApplications.contains { $0.localizedName == "Butterfinder" }
        if running {
            DistributedNotificationCenter.default().postNotificationName(
                notification, object: nil, userInfo: ["path": path, "select": select], deliverImmediately: true)
            return
        }
        let args = select ? ["--select", path] : [path]
        let p = Process()
        if Bundle.main.bundlePath.hasSuffix(".app") {
            // Installed: wherever macOS knows Butterfinder is, else next to this app.
            let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.butterfinder.app")
                ?? Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("Butterfinder.app")
            p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            p.arguments = ["-a", app.path, "--args"] + args
        } else {
            guard let dir = Bundle.main.executableURL?.deletingLastPathComponent() else { return }
            p.executableURL = dir.appendingPathComponent("Butterfinder")
            p.arguments = args
        }
        try? p.run()
    }
}
