import AppKit
import SwiftUI

private final class HoverPanelWindow: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class DetachedWindowPresenter: NSObject, NSWindowDelegate {
    static let shared = DetachedWindowPresenter()

    private var windows: [String: NSWindow] = [:]

    func showHoverPanel<Content: View>(
        id: String,
        size: CGSize,
        origin: CGPoint,
        @ViewBuilder content: () -> Content
    ) {
        let anyView = AnyView(content())

        if let existing = windows[id] {
            if existing.frame.size != size {
                existing.setContentSize(size)
            }
            if existing.frame.origin != origin {
                existing.setFrameOrigin(origin)
            }
            if let controller = existing.contentViewController as? NSHostingController<AnyView> {
                controller.rootView = anyView
            } else {
                existing.contentViewController = NSHostingController(rootView: anyView)
            }
            existing.orderFront(nil)
            return
        }

        let controller = NSHostingController(rootView: anyView)
        let window = HoverPanelWindow(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.identifier = NSUserInterfaceItemIdentifier(id)
        window.contentViewController = controller
        window.level = .statusBar
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        window.delegate = self

        windows[id] = window
        window.orderFront(nil)
    }

    func close(id: String) {
        guard let window = windows[id] else { return }
        window.close()
        windows.removeValue(forKey: id)
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let id = window.identifier?.rawValue else { return }
        windows.removeValue(forKey: id)
    }
}
