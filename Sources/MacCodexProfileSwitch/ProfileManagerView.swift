import AppKit
import SwiftUI

@MainActor
final class ProfileManagerViewModel: ObservableObject {
    @Published var profiles: [CodexProfile] = []
    @Published var selectedProfileName: String?
    @Published var selectedPage: ProfileSettingsPage? = .general
    @Published var language: AppLanguage = AppText.currentLanguage
    @Published var statusMessage: String?
    @Published var errorMessage: String?
    @Published var backupScanResult: BackupScanResult?

    private let profileService: ProfileSwitcherService
    private let providerProfileService = ProviderProfileService()
    private let oauthLoginService = OpenAIOAuthLoginService()
    private let backupService = BackupService()
    private let onProfilesChanged: () -> Void
    private let onClose: () -> Void

    init(
        profileService: ProfileSwitcherService,
        onProfilesChanged: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self.profileService = profileService
        self.onProfilesChanged = onProfilesChanged
        self.onClose = onClose
    }

    var selectedProfile: CodexProfile? {
        guard let selectedProfileName else { return nil }
        return self.profiles.first { $0.name.caseInsensitiveCompare(selectedProfileName) == .orderedSame }
    }

    var currentProfile: CodexProfile? {
        self.profiles.first { $0.isCurrent }
    }

    var currentProfileText: String {
        self.currentProfile?.name ?? AppText.s("No matching profile", "未匹配任何 Profile")
    }

    func refresh(selecting profileName: String? = nil) {
        do {
            self.profiles = try self.profileService.listProfiles()
            if let profileName {
                self.selectedProfileName = profileName
            } else if self.selectedProfileName == nil || self.selectedProfile == nil {
                self.selectedProfileName = self.currentProfile?.name ?? self.profiles.first?.name
            }
            self.errorMessage = nil
            self.onProfilesChanged()
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    var selectedProfileCanEditProvider: Bool {
        guard let selectedProfile else { return false }
        if case .openAICompatibleProvider = selectedProfile.kind {
            return true
        }
        return false
    }

    func editSelectedProviderProfile() {
        guard let profile = self.selectedProfile,
              case .openAICompatibleProvider = profile.kind else {
            return
        }

        let defaultInput = providerProfileService.input(for: profile)
        guard let input = ProviderProfilePrompt.run(mode: .edit, defaultInput: defaultInput) else {
            return
        }

        do {
            let updated = try providerProfileService.update(profile: profile, input: input)
            if profile.isCurrent {
                try profileService.switchTo(updated)
            }
            self.statusMessage = AppText.s("Updated provider \(updated.name).", "已更新 Provider：\(updated.name)。")
            self.refresh(selecting: updated.name)
        } catch {
            Dialogs.showError(error)
        }
    }

    func addOAuthAccount() {
        oauthLoginService.start { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let login):
                self.statusMessage = AppText.s("Added OAuth account \(login.email).", "已添加 OAuth 账号：\(login.email)。")
                self.refresh(selecting: login.profile.name)
            case .failure(let error):
                Dialogs.showError(error)
            }
        }
    }

    func addProviderProfile() {
        guard let input = ProviderProfilePrompt.run() else { return }
        do {
            let profile = try providerProfileService.create(input: input)
            self.statusMessage = AppText.s("Added provider \(profile.name).", "已添加 Provider：\(profile.name)。")
            self.refresh(selecting: profile.name)
        } catch {
            Dialogs.showError(error)
        }
    }

    func deleteOAuthProfile(_ profile: CodexProfile) {
        guard case .openAIOAuth = profile.kind else { return }
        let alert = NSAlert()
        alert.messageText = "Delete OAuth Account?"
        alert.informativeText = "This action is irreversible. The selected OAuth profile will be permanently deleted."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        do {
            try profileService.deleteProfile(profile)
            self.statusMessage = "Deleted OAuth profile \(profile.name)."
            self.refresh()
        } catch {
            Dialogs.showError(error)
        }
    }

    func selectProfile(_ profile: CodexProfile) {
        guard profile.isComplete else { return }
        self.confirmAndSwitch(profile)
    }

    func closeWindow() {
        self.onClose()
    }

    func scanBackups() {
        self.backupScanResult = self.backupService.scan()
        self.statusMessage = AppText.s("Backup scan complete.", "备份扫描完成。")
        self.errorMessage = nil
    }

    func backup(_ kind: BackupKind) {
        do {
            guard let url = try self.backupService.backup(kind) else {
                return
            }
            self.statusMessage = AppText.s("Backup saved to \(url.lastPathComponent).", "备份已保存为 \(url.lastPathComponent)。")
            self.errorMessage = nil
        } catch {
            Dialogs.showError(error)
        }
    }

    private func confirmAndSwitch(_ profile: CodexProfile) {
        let alert = NSAlert()
        alert.messageText = AppText.s("Switch Profile?", "切换 Profile？")
        alert.informativeText = AppText.s(
            "Switch to \(profile.name)? The current auth.json and config.toml will be backed up before replacement.",
            "切换到 \(profile.name)？当前 auth.json 和 config.toml 会先备份再替换。"
        )
        alert.alertStyle = .informational
        alert.addButton(withTitle: AppText.s("Switch", "切换"))
        alert.addButton(withTitle: AppText.s("Cancel", "取消"))

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        do {
            try self.profileService.switchTo(profile)
            self.statusMessage = AppText.s(
                "Switched to \(profile.name). Session history remains shared.",
                "已切换到 \(profile.name)。历史 sessions 仍然保持共享。"
            )
            self.refresh(selecting: profile.name)
        } catch {
            Dialogs.showError(error)
        }
    }

    func openSelectedProfileFolder() {
        guard let profile = self.selectedProfile else { return }
        self.profileService.openProfileFolder(profile)
    }

    func openProfilesFolder() {
        do {
            try self.profileService.openProfilesFolder()
        } catch {
            Dialogs.showError(error)
        }
    }

    func setLanguage(_ language: AppLanguage) {
        do {
            try AppText.setLanguage(language)
            self.language = language
            self.refresh()
        } catch {
            Dialogs.showError(error)
        }
    }
}

enum ProfileSettingsPage: String, CaseIterable, Identifiable {
    case general
    case profiles
    case backup
    case about

    var id: String { self.rawValue }

    @MainActor
    var title: String {
        switch self {
        case .general:
            return AppText.s("General", "通用")
        case .profiles:
            return AppText.s("Profiles", "Profiles")
        case .backup:
            return AppText.s("Backup", "备份")
        case .about:
            return AppText.s("About", "关于")
        }
    }

    var iconName: String {
        switch self {
        case .general:
            return "gearshape"
        case .profiles:
            return "person.crop.circle"
        case .backup:
            return "archivebox"
        case .about:
            return "info.circle"
        }
    }
}

struct ProfileManagerView: View {
    @ObservedObject var model: ProfileManagerViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                self.sidebar
                Divider()
                self.detail
            }

            Divider()

            self.footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(ProfileSettingsPage.allCases) { page in
                SidebarButton(
                    page: page,
                    isSelected: (self.model.selectedPage ?? .general) == page
                ) {
                    self.model.selectedPage = page
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 18)
        .frame(width: 260)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.45))
    }

    private var detail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                self.header

                switch self.model.selectedPage ?? .general {
                case .general:
                    GeneralPage(model: self.model)
                case .profiles:
                    ProfilesPage(model: self.model)
                case .backup:
                    BackupPage(model: self.model)
                case .about:
                    AboutPage()
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(AppText.s("Settings", "设置"))
                .font(.system(size: 22, weight: .semibold))
            Text(AppText.s(
                "Switch Codex Desktop profiles while keeping one shared ~/.codex session pool. Only auth.json and config.toml are replaced.",
                "切换 Codex Desktop profile，同时保留同一份 ~/.codex 历史池。切换时只替换 auth.json 和 config.toml。"
            ))
            .font(.system(size: 12))
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if let errorMessage = self.model.errorMessage {
                Text(errorMessage)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.red)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else if let statusMessage = self.model.statusMessage {
                Text(statusMessage)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Button(AppText.s("Close", "关闭")) {
                self.model.closeWindow()
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

private struct ProfilesPage: View {
    @ObservedObject var model: ProfileManagerViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            CurrentProfileSection(model: self.model)
            ProfileCategoriesSection(model: self.model)
            SelectedProfileActions(model: self.model)
        }
    }
}

private struct SidebarButton: View {
    let page: ProfileSettingsPage
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: self.action) {
            HStack(spacing: 12) {
                Image(systemName: self.page.iconName)
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 24, height: 24)
                Text(self.page.title)
                    .font(.system(size: 13, weight: self.isSelected ? .semibold : .medium))
                Spacer(minLength: 0)
            }
            .foregroundColor(.primary)
            .padding(.horizontal, 12)
            .frame(height: 42)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(self.isSelected ? Color.accentColor.opacity(0.10) : Color.secondary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(self.isSelected ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct CurrentProfileSection: View {
    @ObservedObject var model: ProfileManagerViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(
                title: AppText.s("Current Profile", "当前 Profile"),
                hint: AppText.s(
                    "Current is detected by comparing the profile files with ~/.codex/auth.json and ~/.codex/config.toml.",
                    "当前状态通过比较 profile 文件与 ~/.codex/auth.json 和 ~/.codex/config.toml 判断。"
                )
            )

            InfoCard {
                HStack(spacing: 12) {
                    Image(systemName: self.model.currentProfile == nil ? "questionmark.circle" : "checkmark.circle.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(self.model.currentProfile == nil ? .secondary : .accentColor)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(self.model.currentProfileText)
                            .font(.system(size: 14, weight: .semibold))
                        Text(AppText.s(
                            "Sessions and archived_sessions are not moved.",
                            "sessions 与 archived_sessions 不会被移动。"
                        ))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

private struct ProfileCategoriesSection: View {
    @ObservedObject var model: ProfileManagerViewModel

    private var groups: [(title: String, detail: String, color: Color, profiles: [CodexProfile])] {
        [
            (
                CodexProfileKind.openAIOAuth.title,
                CodexProfileKind.openAIOAuth.detail,
                CodexProfileKind.openAIOAuth.badgeColor,
                self.model.profiles.filter { if case .openAIOAuth = $0.kind { true } else { false } }
            ),
            (
                AppText.s("Provider", "Provider"),
                AppText.s("OpenAI-compatible provider profiles", "OpenAI 兼容 Provider profiles"),
                Color.purple,
                self.model.profiles.filter { if case .openAICompatibleProvider = $0.kind { true } else { false } }
            )
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionTitle(
                title: AppText.s("Profile Categories", "Profile 分类"),
                hint: AppText.s(
                    "Choose a profile from its category, then switch from the footer or the selected profile actions.",
                    "从分类中选择 profile，然后从底部或选中 profile 操作区切换。"
                )
            )

            if self.model.profiles.isEmpty {
                EmptyStateCard(text: AppText.s(
                    "No profiles yet. Create one from the current Codex config or import paired files.",
                    "还没有 profile。可以从当前 Codex 配置创建，或扫描导入成对文件。"
                ))
            } else {
                VStack(spacing: 10) {
                    ForEach(Array(self.groups.enumerated()), id: \.offset) { _, group in
                        CategoryCard(
                            title: group.title,
                            detail: group.detail,
                            color: group.color,
                            profiles: group.profiles,
                            selectedProfileName: self.model.selectedProfileName,
                            onAdd: addAction(for: group.title),
                            onDelete: deleteAction(for: group.title)
                        ) { profile in
                            self.model.selectProfile(profile)
                        }
                    }
                }
            }
        }
    }

    private func addAction(for title: String) -> (() -> Void)? {
        if title == CodexProfileKind.openAIOAuth.title {
            return { self.model.addOAuthAccount() }
        }
        if title == AppText.s("Provider", "Provider") {
            return { self.model.addProviderProfile() }
        }
        return nil
    }

    private func deleteAction(for title: String) -> ((CodexProfile) -> Void)? {
        guard title == CodexProfileKind.openAIOAuth.title else { return nil }
        return { profile in self.model.deleteOAuthProfile(profile) }
    }
}

private struct SelectedProfileActions: View {
    @ObservedObject var model: ProfileManagerViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(
                title: AppText.s("Selected Profile Actions", "选中 Profile 操作"),
                hint: AppText.s(
                    "Switching backs up the current active files before replacing them.",
                    "切换前会先备份当前正在使用的 auth/config 文件。"
                )
            )

            LazyVGrid(columns: actionGridColumns, spacing: 10) {
                if self.model.selectedProfileCanEditProvider {
                    ActionButton(title: AppText.s("Edit Provider", "编辑 Provider"), icon: "pencil") {
                        self.model.editSelectedProviderProfile()
                    }
                }

                ActionButton(title: AppText.s("Open Profile Folder", "打开 Profile 目录"), icon: "folder") {
                    self.model.openSelectedProfileFolder()
                }
                .disabled(self.model.selectedProfile == nil)
            }
        }
    }
}

private struct CategoryCard: View {
    private let trailingActionWidth: CGFloat = 28

    let title: String
    let detail: String
    let color: Color
    let profiles: [CodexProfile]
    let selectedProfileName: String?
    let onAdd: (() -> Void)?
    let onDelete: ((CodexProfile) -> Void)?
    let onSelect: (CodexProfile) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(self.color)
                    .frame(width: 8, height: 8)
                Text(self.title)
                    .font(.system(size: 13, weight: .semibold))
                Text("\(self.profiles.count)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(self.color)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(self.color.opacity(0.12)))
                Spacer(minLength: 0)
                if let onAdd {
                    Button(action: onAdd) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.green)
                            .frame(width: self.trailingActionWidth, height: 20)
                    }
                    .buttonStyle(.plain)
                    .help(AppText.s("Add \(self.title)", "添加 \(self.title)"))
                } else {
                    Color.clear
                        .frame(width: self.trailingActionWidth, height: 20)
                }
            }

            Text(self.detail)
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            if self.profiles.isEmpty {
                Text(AppText.s("No profiles in this category.", "这个分类暂无 profile。"))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 6) {
                    ForEach(self.profiles, id: \.name) { profile in
                        HStack(spacing: 6) {
                            Button {
                                self.onSelect(profile)
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: self.selectedProfileName == profile.name ? "largecircle.fill.circle" : "circle")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(self.selectedProfileName == profile.name ? .accentColor : .secondary)
                                    Text(profile.name)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(.primary)
                                    if profile.isCurrent {
                                        Badge(text: AppText.s("current", "当前"), color: .accentColor)
                                    }
                                    if profile.isComplete == false {
                                        Badge(text: AppText.s("missing", "缺少"), color: .orange)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            if let onDelete {
                                Button {
                                    onDelete(profile)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(.red)
                                        .frame(width: self.trailingActionWidth, height: 20)
                                }
                                .buttonStyle(.plain)
                                .help("Delete OAuth profile")
                            } else {
                                Color.clear
                                    .frame(width: self.trailingActionWidth, height: 20)
                            }
                        }
                        .padding(.leading, 9)
                        .padding(.trailing, 0)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 7)
                                .fill(self.selectedProfileName == profile.name ? Color.accentColor.opacity(0.08) : Color.clear)
                        )
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.06))
        )
    }
}

private struct GeneralPage: View {
    @ObservedObject var model: ProfileManagerViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionTitle(
                title: AppText.s("General", "通用"),
                hint: AppText.s(
                    "Manage shared profile storage and interface language.",
                    "管理共享 Profile 存储位置和界面语言。"
                )
            )

            VStack(spacing: 8) {
                FileInfoRow(title: "auth.json", path: CodexPaths.authJSON.path)
                FileInfoRow(title: "config.toml", path: CodexPaths.configTOML.path)
                FileInfoRow(title: AppText.s("profiles", "profiles"), path: CodexPaths.profilesRoot.path)
                FileInfoRow(title: AppText.s("backups", "backups"), path: CodexPaths.backupsRoot.path)
            }

            LazyVGrid(columns: actionGridColumns, spacing: 10) {
                ActionButton(title: AppText.s("Open Folder", "打开目录"), icon: "folder") {
                    self.model.openProfilesFolder()
                }
            }

            SectionTitle(
                title: AppText.s("Language", "语言"),
                hint: AppText.s(
                    "The language setting is stored locally under ~/.codex/mac-codex-profile-switch.",
                    "语言设置保存在 ~/.codex/mac-codex-profile-switch 下的本地配置中。"
                )
            )

            VStack(spacing: 8) {
                LanguageOptionCard(
                    title: "English",
                    detail: "Use English labels and messages.",
                    selected: self.model.language == .english
                ) {
                    self.model.setLanguage(.english)
                }
                LanguageOptionCard(
                    title: "中文",
                    detail: "使用中文界面和提示。",
                    selected: self.model.language == .chinese
                ) {
                    self.model.setLanguage(.chinese)
                }
            }
        }
    }
}

private struct BackupPage: View {
    @ObservedObject var model: ProfileManagerViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionTitle(
                title: AppText.s("Backup", "备份"),
                hint: AppText.s(
                    "Scan current Codex sessions and profiles first, then export the selected backup as a zip file.",
                    "先扫描当前 Codex sessions 和 profiles，再选择要导出的 zip 备份。"
                )
            )

            ActionButton(title: AppText.s("Scan Sessions and Profiles", "扫描 Sessions 和 Profiles"), icon: "magnifyingglass") {
                self.model.scanBackups()
            }

            if let result = self.model.backupScanResult {
                VStack(alignment: .leading, spacing: 10) {
                    BackupGroupCard(
                        group: result.sessions,
                        icon: "bubble.left.and.bubble.right",
                        backupTitle: AppText.s("Backup Sessions", "备份 Sessions")
                    ) {
                        self.model.backup(.sessions)
                    }

                    BackupGroupCard(
                        group: result.profiles,
                        icon: "person.crop.circle.badge.checkmark",
                        backupTitle: AppText.s("Backup Profiles", "备份 Profiles")
                    ) {
                        self.model.backup(.profiles)
                    }

                    BackupGroupCard(
                        group: result.currentFiles,
                        icon: "doc.badge.gearshape",
                        backupTitle: AppText.s("Backup Current auth/config", "备份当前 auth/config")
                    ) {
                        self.model.backup(.currentFiles)
                    }

                    Text(AppText.s(
                        "Last scanned: \(result.scannedAt.formatted(date: .omitted, time: .shortened))",
                        "上次扫描：\(result.scannedAt.formatted(date: .omitted, time: .shortened))"
                    ))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                }
            } else {
                EmptyStateCard(text: AppText.s(
                    "No scan results yet. Run a scan to preview what can be backed up.",
                    "还没有扫描结果。先扫描一次，预览可以备份的内容。"
                ))
            }
        }
    }
}

private struct BackupGroupCard: View {
    let group: BackupScanGroup
    let icon: String
    let backupTitle: String
    let backup: () -> Void

    var body: some View {
        InfoCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: self.icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.accentColor)
                        .frame(width: 20, height: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(self.group.title)
                            .font(.system(size: 13, weight: .semibold))
                        Text(summaryText)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    Spacer(minLength: 0)
                    Button(self.backupTitle, action: self.backup)
                        .font(.system(size: 11, weight: .medium))
                        .disabled(self.group.totalCount == 0)
                }

                if self.group.previewPaths.isEmpty {
                    Text(AppText.s("Nothing found.", "没有找到内容。"))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(self.group.previewPaths, id: \.self) { path in
                            Text(path)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
        }
    }

    private var summaryText: String {
        if self.group.totalCount > 5 {
            return AppText.s(
                "Showing 5 of \(self.group.totalCount) items.",
                "显示前 5 条，共 \(self.group.totalCount) 条。"
            )
        }
        return AppText.s(
            "\(self.group.totalCount) item(s) found.",
            "共 \(self.group.totalCount) 条。"
        )
    }
}

private struct AboutPage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionTitle(
                title: AppText.s("About", "关于"),
                hint: AppText.s(
                    "Mac.Codex.ProfileSwitch is a lightweight Codex profile switcher for macOS.",
                    "Mac.Codex.ProfileSwitch 是一个轻量的 macOS Codex Profile 切换工具。"
                )
            )

            VStack(spacing: 8) {
                AboutRow(
                    icon: "person.crop.circle",
                    title: AppText.s("Author", "作者"),
                    detail: "iv3n",
                    color: .accentColor
                )
                AboutRow(
                    icon: "envelope",
                    title: AppText.s("Email", "邮箱"),
                    detail: "ivenwong.xx@gmail.com",
                    color: .purple
                )
            }
        }
    }
}

private struct SectionTitle: View {
    let title: String
    let hint: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(self.title)
                .font(.system(size: 16, weight: .semibold))
            Text(self.hint)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct InfoCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        self.content
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.06))
            )
    }
}

private struct EmptyStateCard: View {
    let text: String

    var body: some View {
        Text(self.text)
            .font(.system(size: 12))
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.06))
            )
    }
}

private struct FileInfoRow: View {
    let title: String
    let path: String

    var body: some View {
        InfoCard {
            HStack(alignment: .top, spacing: 12) {
                Text(self.title)
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 110, alignment: .leading)
                Text(self.path)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Spacer(minLength: 0)
            }
        }
    }
}

private struct LanguageOptionCard: View {
    let title: String
    let detail: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: self.action) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: self.selected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(self.selected ? .accentColor : .secondary)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 3) {
                    Text(self.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.primary)
                    Text(self.detail)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(self.selected ? Color.accentColor.opacity(0.08) : Color.secondary.opacity(0.06))
            )
        }
        .buttonStyle(.plain)
    }
}

private let actionGridColumns = [
    GridItem(.flexible(), spacing: 10),
    GridItem(.flexible(), spacing: 10)
]

private struct ActionButton: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: self.action) {
            HStack(spacing: 8) {
                Image(systemName: self.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 16)
                Text(self.title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 11)
            .frame(height: 34)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.bordered)
    }
}

private struct AboutRow: View {
    let icon: String
    let title: String
    let detail: String
    let color: Color

    var body: some View {
        InfoCard {
            HStack(alignment: .center, spacing: 16) {
                Image(systemName: self.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(self.color)
                    .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text(self.title)
                        .font(.system(size: 12, weight: .semibold))
                        .frame(height: 16, alignment: .leading)
                    Text(self.detail)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(height: 14, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 0)
            }
            .frame(height: 42)
        }
    }
}

private struct Badge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(self.text)
            .font(.system(size: 9, weight: .semibold))
            .foregroundColor(self.color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(self.color.opacity(0.12))
            )
    }
}

private extension CodexProfileKind {
    var badgeColor: Color {
        switch self {
        case .openAIOAuth:
            return .accentColor
        case .openAICompatibleProvider:
            return .purple
        case .apiKey:
            return .green
        case .incomplete:
            return .orange
        case .unknown:
            return .secondary
        }
    }
}
