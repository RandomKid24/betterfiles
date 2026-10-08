import AppKit
import SwiftUI

final class Panel: NSPanel {
    var onResign: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func resignKey() {
        super.resignKey()
        onResign?()
    }
}

@MainActor
final class PanelController {
    // ponytail: fixed-size transparent panel (content + shadow room). Resize-to-fit if it ever looks wrong.
    private static let size = NSSize(width: 720, height: 600)
    private static let fadeOut = 0.16

    private let panel: Panel
    private let model: Model
    private var pendingHide: DispatchWorkItem?

    init(model: Model) {
        self.model = model
        panel = Panel(contentRect: NSRect(origin: .zero, size: Self.size),
                      styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false // SwiftUI draws the shadow so it fades with the content
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: LauncherView(model: model))
        panel.onResign = { [weak self] in self?.hide() }
        model.onDismiss = { [weak self] in self?.hide() }
    }

    func toggle() { model.visible ? hide() : show() }

    func show() {
        pendingHide?.cancel()
        model.reset()
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
            ?? NSScreen.main ?? NSScreen.screens[0]
        let f = screen.visibleFrame
        let top = f.maxY - f.height * 0.18
        panel.setFrameOrigin(NSPoint(x: f.midX - Self.size.width / 2, y: top - Self.size.height))
        // Non-activating panel: takes keys without stealing app focus, so Esc returns you to the previous app.
        panel.makeKeyAndOrderFront(nil)
        // Next turn, so the view renders hidden first and the pop-in animates.
        DispatchQueue.main.async { self.model.visible = true }
    }

    func hide() {
        guard model.visible else { return }
        model.visible = false // fade/shrink out, then remove the window
        let work = DispatchWorkItem { [weak self] in
            self?.panel.orderOut(nil)
            self?.model.didHide()
        }
        pendingHide = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.fadeOut, execute: work)
    }
}
