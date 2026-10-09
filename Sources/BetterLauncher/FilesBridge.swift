import AppKit

/// Hands a path to BetterFiles: a running instance gets a distributed notification, otherwise the sibling
/// executable is started with the path as its argument.
enum FilesBridge {
    static let notification = Notification.Name("com.betterfiles.open")

    static func show(_ path: String, select: Bool) {
        let running = NSWorkspace.shared.runningApplications.contains { $0.localizedName == "BetterFiles" }
        if running {
            DistributedNotificationCenter.default().postNotificationName(
                notification, object: nil, userInfo: ["path": path, "select": select], deliverImmediately: true)
            return
        }
        let args = select ? ["--select", path] : [path]
        let p = Process()
        if Bundle.main.bundlePath.hasSuffix(".app") {
            // Installed: BetterFiles.app sits next to BetterLauncher.app.
            let app = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("BetterFiles.app")
            p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            p.arguments = ["-a", app.path, "--args"] + args
        } else {
            guard let dir = Bundle.main.executableURL?.deletingLastPathComponent() else { return }
            p.executableURL = dir.appendingPathComponent("BetterFiles")
            p.arguments = args
        }
        try? p.run()
    }
}
