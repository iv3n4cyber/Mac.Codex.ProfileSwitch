import AppKit
import SwiftUI

@MainActor
final class ProfileManagerWindowController: NSWindowController {
    private let model: ProfileManagerViewModel

    init(profileService: ProfileSwitcherService, onProfilesChanged: @escaping () -> Void) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = AppText.s("Settings", "设置")
        window.minSize = NSSize(width: 760, height: 520)
        window.center()

        self.model = ProfileManagerViewModel(
            profileService: profileService,
            onProfilesChanged: onProfilesChanged,
            onClose: { [weak window] in
                window?.close()
            }
        )
        window.contentViewController = NSHostingController(rootView: ProfileManagerView(model: self.model))

        super.init(window: window)
        self.model.refresh()
    }

    required init?(coder: NSCoder) {
        nil
    }

    func applyLanguage() {
        self.window?.title = AppText.s("Settings", "设置")
        self.model.language = AppText.currentLanguage
        self.model.refresh()
    }
}
