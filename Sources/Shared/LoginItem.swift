import Foundation
import ServiceManagement

/// Start-at-login for an installed app (a bare executable can't register).
public enum LoginItem {
    public static var available: Bool { Bundle.main.bundlePath.hasSuffix(".app") }
    public static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    public static func set(_ on: Bool) {
        if on { try? SMAppService.mainApp.register() } else { try? SMAppService.mainApp.unregister() }
    }

    /// Turns it on the first time an installed app runs, and never again, so switching it off sticks.
    public static func enableOnFirstRun() {
        let key = "loginItemOffered"
        guard available, !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        set(true)
    }

    /// True when macOS started this app because the user logged in (so it should stay out of the way).
    public static var launchedAtLogin: Bool {
        NSAppleEventManager.shared().currentAppleEvent?
            .paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue == OSType(keyAELaunchedAsLogInItem)
    }
}
