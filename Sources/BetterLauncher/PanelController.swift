import AppKit
import SwiftUI

final class Panel: NSPanel {
    override var canBecomeKey: Bool { true }
    override func resignKey() {
        super.resignKey()
        orderOut(nil)
    }
}

@MainActor
final class PanelController {
    // ponytail: fixed-height panel (field + 8 rows); transparent below the content. Resize-to-fit if it ever looks wrong.
    private static let size = NSSize(width: 640, height: 440)

    private let panel: Panel
    private let model: Model

    init(model: Model) {
        self.model = model
        panel = Panel(contentRect: NSRect(origin: .zero, size: Self.size),
                      styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: LauncherView(model: model))
        model.onDismiss = { [weak self] in self?.hide() }
    }

    func toggle() { panel.isVisible ? hide() : show() }

    func show() {
        model.reset()
        model.showCount += 1
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
            ?? NSScreen.main ?? NSScreen.screens[0]
        let f = screen.visibleFrame
        let top = f.maxY - f.height * 0.2
        panel.setFrameOrigin(NSPoint(x: f.midX - Self.size.width / 2, y: top - Self.size.height))
        // Non-activating panel: takes keys without stealing app focus, so Esc returns you to the previous app.
        panel.makeKeyAndOrderFront(nil)
    }

    func hide() { panel.orderOut(nil) }
}
