import AppKit
import SwiftUI

@MainActor
final class MenuBarController {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let profileService = ProfileSwitcherService()
    private let restartService = CodexClientRestartService()
    private let oauthLoginService = OpenAIOAuthLoginService()
    private let providerProfileService = ProviderProfileService()
    private var managerWindowController: ProfileManagerWindowController?
    private var currentQuotaSnapshot: OpenAIQuotaSnapshot?
    private var quotaStates: [String: UsageRefreshState] = [:]
    private var tokenUsageSummary: LocalTokenUsageSummary = .empty

    init() {
        popover.behavior = .transient
        configureStatusItem()
        refreshStatusItem()
    }

    func showManagerWindow() {
        closePopover()
        if managerWindowController == nil {
            managerWindowController = ProfileManagerWindowController(profileService: profileService) { [weak self] in
                self?.refreshStatusItem()
            }
        }

        guard let windowController = managerWindowController else {
            return
        }

        NSApp.activate()
        windowController.showWindow(nil)
        windowController.window?.makeKeyAndOrderFront(nil)
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else {
            return
        }

        button.title = ""
        button.image = MenuBarUsageIcon.make()
        button.imagePosition = .imageLeading
        button.target = self
        button.action = #selector(togglePopover)
    }

    private func refreshStatusItem() {
        let profiles: [CodexProfile]
        do {
            profiles = try profileService.listProfiles()
        } catch {
            updateStatusTitle(currentProfileName: nil)
            updatePopoverContent(profiles: [], errorMessage: error.localizedDescription)
            return
        }

        let currentProfile = profiles.first { $0.isCurrent }
        updateStatusTitle(currentProfileName: currentProfile?.name)
        if popover.isShown {
            updatePopoverContent(profiles: profiles)
        }
    }

    private func profileMenuGroups(for profiles: [CodexProfile]) -> [(title: String, profiles: [CodexProfile])] {
        [
            (
                "OAuth",
                profiles.filter { if case .openAIOAuth = $0.kind { true } else { false } }
            ),
            (
                AppText.s("Provider", "Provider"),
                profiles.filter { if case .openAICompatibleProvider = $0.kind { true } else { false } }
            ),
            (
                "API Key",
                profiles.filter { if case .apiKey = $0.kind { true } else { false } }
            ),
            (
                AppText.s("Other", "其他"),
                profiles.filter {
                    if case .incomplete = $0.kind { return true }
                    if case .unknown = $0.kind { return true }
                    return false
                }
            )
        ]
    }

    private func updateStatusTitle(currentProfileName: String?) {
        statusItem.button?.title = ""
        statusItem.button?.image = MenuBarUsageIcon.make(snapshot: currentQuotaSnapshot)
        statusItem.button?.toolTip = currentProfileName.map {
            "Mac.Codex.ProfileSwitch - \($0)"
        } ?? AppText.s(
            "Mac.Codex.ProfileSwitch - No Matching Profile",
            "Mac.Codex.ProfileSwitch - 未匹配 Profile"
        )
    }

    private func updatePopoverContent(profiles: [CodexProfile], errorMessage: String? = nil) {
        let content = MenuBarPopoverView(
            profiles: profiles,
            groups: profileMenuGroups(for: profiles),
            quotaStates: quotaStates,
            tokenUsageSummary: tokenUsageSummary,
            errorMessage: errorMessage,
            currentLanguage: AppText.currentLanguage,
            resetDisplayMode: AppText.quotaResetDisplayMode,
            openManagement: { [weak self] in self?.showManagerWindow() },
            switchProfile: { [weak self] name in self?.switchProfile(named: name) },
            refreshAllUsage: { [weak self] in self?.refreshAllOAuthUsage() },
            addOAuthAccount: { [weak self] in self?.addOAuthAccount() },
            addProvider: { [weak self] in self?.addProvider() },
            changeLanguage: { [weak self] language in self?.changeLanguage(to: language) },
            toggleResetDisplayMode: { [weak self] in self?.toggleResetDisplayMode() },
            restartCodex: { [weak self] in self?.restartCodexClient() },
            refreshUsage: { [weak self] profile in self?.refreshUsage(for: profile) },
            exit: { NSApp.terminate(nil) }
        )

        if let controller = popover.contentViewController as? NSHostingController<MenuBarPopoverView> {
            controller.rootView = content
        } else {
            popover.contentViewController = NSHostingController(rootView: content)
        }
        popover.contentSize = NSSize(width: 330, height: 470)
    }

    @objc private func togglePopover() {
        if popover.isShown {
            closePopover()
            return
        }
        showPopover()
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        let profiles = (try? profileService.listProfiles()) ?? []
        updateStatusTitle(currentProfileName: profiles.first { $0.isCurrent }?.name)
        updatePopoverContent(profiles: profiles)
        NSApp.activate()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        button.highlight(true)
        refreshTokenUsageSummary()
        refreshOAuthUsage(for: profiles)
    }

    private func closePopover() {
        guard popover.isShown else { return }
        popover.performClose(nil)
        statusItem.button?.highlight(false)
    }

    private func changeLanguage(to language: AppLanguage) {
        do {
            try AppText.setLanguage(language)
            managerWindowController?.applyLanguage()
            refreshStatusItem()
        } catch {
            Dialogs.showError(error)
        }
    }

    private func toggleResetDisplayMode() {
        do {
            try AppText.setQuotaResetDisplayMode(AppText.quotaResetDisplayMode.next)
            refreshStatusItem()
        } catch {
            Dialogs.showError(error)
        }
    }

    private func switchProfile(named profileName: String) {
        do {
            guard let profile = try profileService.listProfiles().first(where: {
                $0.name.caseInsensitiveCompare(profileName) == .orderedSame
            }) else {
                return
            }

            try profileService.switchTo(profile)
            currentQuotaSnapshot = nil
            refreshStatusItem()
            managerWindowController?.applyLanguage()
            if let currentProfile = (try? profileService.listProfiles().first(where: { $0.isCurrent })) {
                refreshUsage(for: currentProfile)
            }
        } catch {
            Dialogs.showError(error)
        }
    }

    private func restartCodexClient() {
        _ = restartService.restart()
        refreshStatusItem()
    }

    private func addOAuthAccount() {
        oauthLoginService.start { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let login):
                self.refreshStatusItem()
                self.refreshUsage(for: login.profile)
            case .failure(let error):
                Dialogs.showError(error)
            }
        }
    }

    private func addProvider() {
        guard let input = ProviderProfilePrompt.run() else { return }
        do {
            _ = try providerProfileService.create(input: input)
            refreshStatusItem()
        } catch {
            Dialogs.showError(error)
        }
    }

    private func refreshOAuthUsage(for profiles: [CodexProfile]) {
        for profile in profiles {
            guard case .openAIOAuth = profile.kind else { continue }
            refreshUsage(for: profile)
        }
    }

    private func refreshAllOAuthUsage() {
        let profiles = (try? profileService.listProfiles()) ?? []
        refreshTokenUsageSummary()
        refreshStatusItem()
        refreshOAuthUsage(for: profiles)
    }

    private func refreshTokenUsageSummary() {
        Task { [weak self] in
            let summary = await Task.detached {
                LocalTokenUsageService().load()
            }.value
            guard let self else { return }
            self.tokenUsageSummary = summary
            self.refreshStatusItem()
        }
    }

    private func refreshUsage(for profile: CodexProfile) {
        guard case .openAIOAuth = profile.kind else { return }
        quotaStates[profile.name] = .loading
        refreshStatusItem()

        Task { [weak self] in
            do {
                let snapshot = try await OpenAIQuotaService.shared.refresh(profile: profile)
                await MainActor.run {
                    self?.quotaStates[profile.name] = .loaded(snapshot)
                    if profile.isCurrent {
                        self?.currentQuotaSnapshot = snapshot
                    }
                    self?.refreshStatusItem()
                }
            } catch {
                await MainActor.run {
                    self?.quotaStates[profile.name] = .failed(error.localizedDescription)
                    if profile.isCurrent {
                        self?.currentQuotaSnapshot = nil
                    }
                    self?.refreshStatusItem()
                }
            }
        }
    }
}

private enum MenuBarUsageIcon {
    static func make(snapshot: OpenAIQuotaSnapshot? = nil) -> NSImage? {
        let width: CGFloat = snapshot == nil ? 18 : 30
        let height: CGFloat = 18
        let image = NSImage(size: NSSize(width: width, height: height))

        image.lockFocus()
        defer { image.unlockFocus() }

        NSColor.labelColor.setStroke()
        let symbolRect = NSRect(x: 0, y: 1, width: 16, height: 16)
        let gauge = NSImage(
            systemSymbolName: "gauge.with.dots.needle.bottom.50percent",
            accessibilityDescription: "Codex Profile Usage"
        ) ?? NSImage(systemSymbolName: "gauge.with.needle", accessibilityDescription: "Codex Profile Usage")
        gauge?.isTemplate = true
        gauge?.draw(in: symbolRect)

        guard let snapshot else {
            image.isTemplate = true
            return image
        }

        drawBar(
            x: 20,
            remaining: snapshot.primaryRemainingPercent / 100,
            inHeight: height
        )
        drawBar(
            x: 25,
            remaining: snapshot.secondaryRemainingPercent / 100,
            inHeight: height
        )

        image.isTemplate = true
        return image
    }

    private static func drawBar(x: CGFloat, remaining: Double, inHeight height: CGFloat) {
        let clamped = CGFloat(max(0, min(1, remaining)))
        let barHeight: CGFloat = 13
        let barWidth: CGFloat = 3
        let baseY: CGFloat = 2
        let background = NSBezierPath(
            roundedRect: NSRect(x: x, y: baseY, width: barWidth, height: barHeight),
            xRadius: 1.5,
            yRadius: 1.5
        )
        NSColor.labelColor.withAlphaComponent(0.22).setFill()
        background.fill()

        let fillHeight = max(1, barHeight * clamped)
        let fill = NSBezierPath(
            roundedRect: NSRect(x: x, y: baseY, width: barWidth, height: fillHeight),
            xRadius: 1.5,
            yRadius: 1.5
        )
        NSColor.labelColor.setFill()
        fill.fill()
    }
}
