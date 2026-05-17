import SwiftUI

struct MenuBarPopoverView: View {
    private let tokenUsagePanelID = "token-usage-hover-panel"

    let profiles: [CodexProfile]
    let groups: [(title: String, profiles: [CodexProfile])]
    let quotaStates: [String: UsageRefreshState]
    let tokenUsageSummary: LocalTokenUsageSummary
    let errorMessage: String?
    let currentLanguage: AppLanguage
    let resetDisplayMode: QuotaResetDisplayMode
    let openManagement: () -> Void
    let switchProfile: (String) -> Void
    let refreshAllUsage: () -> Void
    let addOAuthAccount: () -> Void
    let addProvider: () -> Void
    let changeLanguage: (AppLanguage) -> Void
    let toggleResetDisplayMode: () -> Void
    let restartCodex: () -> Void
    let refreshUsage: (CodexProfile) -> Void
    let exit: () -> Void

    @State private var collapsedGroups: Set<String> = []
    @State private var isTokenSummaryHovered = false
    @State private var isTokenPanelHovered = false
    @State private var isTokenPanelPresented = false
    @State private var pendingTokenPanelHide: DispatchWorkItem?
    @State private var tokenSummaryAnchorView: NSView?

    private var currentProfile: CodexProfile? {
        profiles.first { $0.isCurrent }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header

                    if let errorMessage {
                        InlineMessage(text: errorMessage, color: .red)
                    }

                    currentProfileCard
                    profileGroups
                }
                .padding(14)
            }

            Divider()

            footer
        }
        .frame(width: 330, height: 470)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: openManagement) {
                HStack(spacing: 10) {
                    Image(systemName: "slider.horizontal.3")
                    Text(AppText.s("Open Management Window", "打开管理窗口"))
                        .font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            TokenUsageSummaryView(summary: tokenUsageSummary)
                .background(
                    ViewReferenceReader { view in
                        resolveTokenSummaryAnchor(view)
                    }
                )
                .onHover { hovering in
                    setTokenSummaryHover(hovering)
                }
        }
    }

    private func resolveTokenSummaryAnchor(_ view: NSView) {
        if tokenSummaryAnchorView !== view {
            tokenSummaryAnchorView = view
        }
        guard isTokenPanelPresented else { return }
        showTokenUsagePanel()
    }

    private func setTokenSummaryHover(_ hovering: Bool) {
        isTokenSummaryHovered = hovering
        if hovering {
            presentTokenUsagePanel()
        } else {
            scheduleTokenUsagePanelHideIfNeeded()
        }
    }

    private func setTokenPanelHover(_ hovering: Bool) {
        isTokenPanelHovered = hovering
        if hovering {
            presentTokenUsagePanel()
        } else {
            scheduleTokenUsagePanelHideIfNeeded()
        }
    }

    private func presentTokenUsagePanel() {
        pendingTokenPanelHide?.cancel()
        pendingTokenPanelHide = nil
        isTokenPanelPresented = true
        showTokenUsagePanel()
    }

    private func scheduleTokenUsagePanelHideIfNeeded() {
        pendingTokenPanelHide?.cancel()
        let work = DispatchWorkItem {
            if !isTokenSummaryHovered && !isTokenPanelHovered {
                isTokenPanelPresented = false
                DetachedWindowPresenter.shared.close(id: tokenUsagePanelID)
            }
        }
        pendingTokenPanelHide = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16, execute: work)
    }

    private func showTokenUsagePanel() {
        guard let anchorView = tokenSummaryAnchorView,
              let window = anchorView.window else { return }

        let frameInWindow = anchorView.convert(anchorView.bounds, to: nil)
        let anchorFrame = window.convertToScreen(frameInWindow)
        let panelSize = CGSize(
            width: TokenUsageDetailView.panelWidth,
            height: TokenUsageDetailView.panelHeight(hasHistory: !tokenUsageSummary.daily.isEmpty)
        )
        let screen = NSScreen.screens.first { $0.frame.intersects(anchorFrame) } ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let spacing: CGFloat = 12
        let margin: CGFloat = 8

        var originX = anchorFrame.maxX + spacing
        if originX + panelSize.width > visibleFrame.maxX - margin {
            originX = anchorFrame.minX - spacing - panelSize.width
        }
        originX = min(max(originX, visibleFrame.minX + margin), visibleFrame.maxX - panelSize.width - margin)

        var originY = anchorFrame.maxY - panelSize.height
        originY = min(max(originY, visibleFrame.minY + margin), visibleFrame.maxY - panelSize.height - margin)

        DetachedWindowPresenter.shared.showHoverPanel(
            id: tokenUsagePanelID,
            size: panelSize,
            origin: CGPoint(x: originX, y: originY)
        ) {
            TokenUsageDetailView(summary: tokenUsageSummary)
                .onHover { hovering in
                    setTokenPanelHover(hovering)
                }
        }
    }

    private var currentProfileCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(AppText.s("Current Profile", "当前 Profile"))
                .font(.system(size: 12, weight: .semibold))

            if let currentProfile {
                ProfileSummaryCard(
                    profile: currentProfile,
                    isCurrent: true,
                    usageState: self.quotaStates[currentProfile.name] ?? .idle,
                    isProminent: true,
                    resetDisplayMode: self.resetDisplayMode,
                    onRefreshUsage: {
                        self.refreshUsage(currentProfile)
                    },
                    onToggleResetDisplayMode: self.toggleResetDisplayMode
                ) {
                    switchProfile(currentProfile.name)
                }
            } else {
                InlineMessage(
                    text: AppText.s("No matching profile", "未匹配任何 Profile"),
                    color: .secondary
                )
            }
        }
    }

    private var profileGroups: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(AppText.s("Switch Profile", "切换 Profile"))
                .font(.system(size: 12, weight: .semibold))

            if profiles.isEmpty {
                InlineMessage(text: AppText.s("No profiles", "暂无 profile"), color: .secondary)
            } else {
                ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                    if group.profiles.isEmpty == false {
                        ProfileGroupSection(
                            title: group.title,
                            profiles: group.profiles,
                            isCollapsed: self.collapsedGroups.contains(group.title),
                            quotaStates: self.quotaStates,
                            resetDisplayMode: self.resetDisplayMode,
                            onToggle: {
                                self.toggleGroup(group.title)
                            },
                            onRefreshUsage: { profile in
                                self.refreshUsage(profile)
                            },
                            onToggleResetDisplayMode: self.toggleResetDisplayMode
                        ) { profile in
                            switchProfile(profile.name)
                        }
                    }
                }
            }
        }
    }

    private func toggleGroup(_ title: String) {
        if self.collapsedGroups.contains(title) {
            self.collapsedGroups.remove(title)
        } else {
            self.collapsedGroups.insert(title)
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Menu {
                Button("EN") {
                    changeLanguage(.english)
                }
                Button("ZH") {
                    changeLanguage(.chinese)
                }
            } label: {
                Text(currentLanguage == .english ? "EN" : "ZH")
            }
            FooterIconButton(
                systemName: "arrow.clockwise",
                help: AppText.s("Refresh all OAuth usage", "刷新所有 OAuth 用量"),
                action: refreshAllUsage
            )
            FooterIconButton(
                systemName: "person.crop.circle.badge.plus",
                help: AppText.s("Add OAuth account", "添加 OAuth 账号"),
                action: addOAuthAccount
            )
            FooterIconButton(
                systemName: "server.rack",
                help: AppText.s("Add provider", "添加 Provider"),
                action: addProvider
            )
            Button("Restart", action: restartCodex)
                .help("Restart Codex")
            Spacer()
            FooterIconButton(
                systemName: "power.circle",
                help: AppText.s("Exit", "退出"),
                action: exit
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .controlSize(.small)
    }
}

private struct FooterIconButton: View {
    let systemName: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .frame(width: 14, height: 14)
                .help(help)
                .accessibilityLabel(help)
        }
        .help(help)
        .accessibilityLabel(help)
    }
}

private struct TokenUsageSummaryView: View {
    let summary: LocalTokenUsageSummary

    var body: some View {
        HStack(spacing: 8) {
            metric(
                title: AppText.s("Today", "今天"),
                value: summary.today.totalTokens
            )
            Divider()
                .frame(height: 18)
            metric(
                title: AppText.s("30d", "30天"),
                value: summary.last30Days.totalTokens
            )
            Divider()
                .frame(height: 18)
            metric(
                title: AppText.s("Total", "总用量"),
                value: summary.lifetime.totalTokens
            )
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.06))
        )
    }

    private func metric(title: String, value: Int) -> some View {
        HStack(spacing: 5) {
            Text(title)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.secondary)
            Text(compactTokenText(value))
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.primary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct TokenUsageDetailView: View {
    static let panelWidth: CGFloat = 280

    static func panelHeight(hasHistory: Bool) -> CGFloat {
        hasHistory ? 328 : 158
    }

    let summary: LocalTokenUsageSummary
    @State private var selectedDayID: Date?

    private var selectedDay: DailyTokenUsage? {
        guard let selectedDayID else { return nil }
        return summary.daily.first { $0.id == selectedDayID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(AppText.s("Token Usage", "Token 用量"))
                .font(.system(size: 12, weight: .semibold))

            VStack(spacing: 7) {
                usageRow(title: AppText.s("Today", "今天"), usage: summary.today)
                usageRow(title: AppText.s("30 days", "30天"), usage: summary.last30Days)
                usageRow(title: AppText.s("Total", "总用量"), usage: summary.lifetime)
            }

            if summary.daily.isEmpty {
                Text(AppText.s("No token history data.", "暂无 token 历史数据。"))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            } else {
                TokenUsageBarChart(days: summary.daily, selectedDayID: $selectedDayID)

                HStack {
                    if let first = summary.daily.first {
                        Text(shortDate(first.date))
                    }

                    Spacer()

                    if let last = summary.daily.last {
                        Text(shortDate(last.date))
                    }
                }
                .font(.caption2)
                .foregroundColor(.secondary)

                VStack(alignment: .leading, spacing: 0) {
                    Text(primaryDetailText())
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .frame(height: 16, alignment: .leading)
                    Text(secondaryDetailText())
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .frame(height: 16, alignment: .leading)
                }
            }
        }
        .padding(12)
        .frame(
            width: Self.panelWidth,
            height: Self.panelHeight(hasHistory: !summary.daily.isEmpty),
            alignment: .topLeading
        )
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.windowBackgroundColor))
                .shadow(color: Color.black.opacity(0.12), radius: 10, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
    }

    private func usageRow(title: String, usage: TokenUsage) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.primary)
                Spacer()
                Text(compactTokenText(usage.totalTokens))
                    .font(.system(size: 10, weight: .semibold))
            }

            HStack(spacing: 6) {
                detailPill(title: "In", value: usage.inputTokens)
                detailPill(title: "Cached", value: usage.cachedInputTokens)
                detailPill(title: "Out", value: usage.outputTokens)
            }
        }
    }

    private func detailPill(title: String, value: Int) -> some View {
        HStack(spacing: 3) {
            Text(title)
            Text(compactTokenText(value))
                .fontWeight(.semibold)
        }
        .font(.system(size: 9))
        .foregroundColor(.secondary)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.secondary.opacity(0.08)))
    }

    private func primaryDetailText() -> String {
        if let selectedDay {
            return "\(shortDate(selectedDay.date)) · \(compactTokenText(selectedDay.usage.totalTokens)) tokens"
        }
        return AppText.s("Last 14 days trend", "最近 14 天趋势")
    }

    private func secondaryDetailText() -> String {
        guard let selectedDay else {
            return ""
        }

        return "In \(compactTokenText(selectedDay.usage.inputTokens)) · Cached \(compactTokenText(selectedDay.usage.cachedInputTokens)) · Out \(compactTokenText(selectedDay.usage.outputTokens))"
    }

    private func shortDate(_ date: Date) -> String {
        date.formatted(.dateTime.month(.twoDigits).day(.twoDigits))
    }
}

private struct TokenUsageBarChart: View {
    let days: [DailyTokenUsage]
    @Binding var selectedDayID: Date?

    private let minBarHeight: CGFloat = 6
    private let barSpacing: CGFloat = 4

    var body: some View {
        GeometryReader { geometry in
            let maxTokens = max(days.map(\.usage.totalTokens).max() ?? 0, 1)
            let slotWidth = geometry.size.width / CGFloat(Swift.max(days.count, 1))

            HStack(alignment: .bottom, spacing: barSpacing) {
                ForEach(days) { day in
                    let isSelected = selectedDayID == day.id
                    RoundedRectangle(cornerRadius: 3)
                        .fill(fillColor(for: day, isSelected: isSelected))
                        .frame(maxWidth: .infinity)
                        .frame(height: barHeight(for: day, totalHeight: geometry.size.height, maxTokens: maxTokens))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    guard days.isEmpty == false,
                          location.x >= 0,
                          location.x <= geometry.size.width else {
                        selectedDayID = nil
                        return
                    }

                    let index = min(max(Int(location.x / max(slotWidth, 1)), 0), days.count - 1)
                    selectedDayID = days[index].id
                case .ended:
                    selectedDayID = nil
                }
            }
        }
        .frame(height: 92)
    }

    private func barHeight(for day: DailyTokenUsage, totalHeight: CGFloat, maxTokens: Int) -> CGFloat {
        guard totalHeight > 0 else { return minBarHeight }
        let usableHeight = max(totalHeight - 4, minBarHeight)
        let ratio = day.usage.totalTokens > 0 ? CGFloat(day.usage.totalTokens) / CGFloat(maxTokens) : 0
        return max(minBarHeight, usableHeight * ratio)
    }

    private func fillColor(for day: DailyTokenUsage, isSelected: Bool) -> Color {
        if isSelected {
            return .accentColor
        }
        if day.usage.totalTokens == 0 {
            return Color.secondary.opacity(0.12)
        }
        return Color.accentColor.opacity(0.68)
    }
}

private func compactTokenText(_ value: Int) -> String {
    if value >= 10_000_000 {
        let number = Double(value) / 1_000_000
        return String(format: "%.0fM", number)
    }
    let number = Double(value) / 1_000
    return String(format: number >= 10 ? "%.0fk" : "%.1fk", number)
}

private struct ProfileGroupSection: View {
    let title: String
    let profiles: [CodexProfile]
    let isCollapsed: Bool
    let quotaStates: [String: UsageRefreshState]
    let resetDisplayMode: QuotaResetDisplayMode
    let onToggle: () -> Void
    let onRefreshUsage: (CodexProfile) -> Void
    let onToggleResetDisplayMode: () -> Void
    let onSelect: (CodexProfile) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: onToggle) {
                HStack {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 10)
                    Text(title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                    Text("\(profiles.count)")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.secondary.opacity(0.12)))
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !isCollapsed {
                VStack(spacing: 6) {
                    ForEach(profiles, id: \.name) { profile in
                        ProfileSummaryCard(
                            profile: profile,
                            isCurrent: profile.isCurrent,
                            usageState: self.quotaStates[profile.name] ?? .idle,
                            isProminent: false,
                            resetDisplayMode: self.resetDisplayMode,
                            onRefreshUsage: {
                                self.onRefreshUsage(profile)
                            },
                            onToggleResetDisplayMode: self.onToggleResetDisplayMode
                        ) {
                            onSelect(profile)
                        }
                    }
                }
            }
        }
    }
}

private struct ProfileSummaryCard: View {
    let profile: CodexProfile
    let isCurrent: Bool
    let usageState: UsageRefreshState
    let isProminent: Bool
    let resetDisplayMode: QuotaResetDisplayMode
    let onRefreshUsage: () -> Void
    let onToggleResetDisplayMode: () -> Void
    let action: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Button(action: action) {
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: isCurrent ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(isCurrent ? .accentColor : .secondary)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(primaryLine)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .layoutPriority(1)

                        if case .openAIOAuth = profile.kind {
                            UsageStatusLine(state: usageState, prominent: isProminent)
                                .padding(.top, 1)
                        } else {
                            ProfileMetadataLine(profile: profile, showModel: true)
                        }
                    }
                    .layoutPriority(1)

                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .layoutPriority(1)

            if let resetDisplay = resetCountdownDisplay {
                ResetCountdownText(
                    display: resetDisplay,
                    action: onToggleResetDisplayMode
                )
                .layoutPriority(2)
            }

            if case .openAIOAuth = profile.kind {
                Button(action: onRefreshUsage) {
                    Image(systemName: usageState.isLoading ? "hourglass" : "arrow.clockwise")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .disabled(usageState.isLoading)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isCurrent ? Color.accentColor.opacity(0.08) : Color.secondary.opacity(0.06))
        )
        .disabled(profile.isComplete == false)
    }

    private var profileDisplayLine: String {
        let summary = profile.summary
        if let email = summary.email, case .openAIOAuth = profile.kind {
            return email
        }
        return profile.kind.detail
    }

    private var primaryLine: String {
        if case .openAIOAuth = profile.kind {
            return profile.summary.email ?? profile.summary.accountIdentifier ?? profile.name
        }
        return displayProfileName
    }

    private var displayProfileName: String {
        if profile.name == "default",
           let email = profile.summary.email,
           let prefix = email.split(separator: "@", maxSplits: 1).first {
            return String(prefix)
        }
        return profile.name
    }

    private var resetCountdownDisplay: QuotaResetCountdownDisplay? {
        guard case .openAIOAuth = profile.kind else { return nil }
        guard case .loaded(let snapshot) = usageState else { return nil }
        return quotaResetCountdownDisplay(for: snapshot, mode: resetDisplayMode)
    }
}

private struct QuotaResetCountdownDisplay {
    let title: String
    let countdown: String
    let help: String
}

private struct ResetCountdownText: View {
    let display: QuotaResetCountdownDisplay
    let action: () -> Void
    @State private var isPresented = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(display.title)
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.secondary.opacity(0.12)))

                Text(display.countdown)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.orange)
                    .lineLimit(1)
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .onHover { hovering in
            isPresented = hovering
        }
        .popover(isPresented: $isPresented, arrowEdge: .top) {
            Text(display.help)
                .font(.system(size: 11))
                .foregroundColor(.primary)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
        }
    }
}

private func quotaResetCountdownDisplay(for snapshot: OpenAIQuotaSnapshot, mode: QuotaResetDisplayMode) -> QuotaResetCountdownDisplay? {
    let primaryTitle = windowTitle(seconds: snapshot.primaryLimitWindowSeconds, fallback: "5h")
    let secondaryTitle = windowTitle(seconds: snapshot.secondaryLimitWindowSeconds, fallback: "7d")
    let primaryCountdown = quotaWindowCountdown(until: snapshot.primaryResetAt)
    let secondaryCountdown = quotaWindowCountdown(until: snapshot.secondaryResetAt)

    let preferred: (String, String?) = switch mode {
    case .primary:
        (primaryTitle, primaryCountdown)
    case .secondary:
        (secondaryTitle, secondaryCountdown)
    }

    guard let countdown = preferred.1 else {
        if let primaryCountdown {
            return QuotaResetCountdownDisplay(
                title: primaryTitle,
                countdown: primaryCountdown,
                help: quotaResetHelp(primaryTitle: primaryTitle, primaryCountdown: primaryCountdown, secondaryTitle: secondaryTitle, secondaryCountdown: secondaryCountdown)
            )
        }
        if let secondaryCountdown {
            return QuotaResetCountdownDisplay(
                title: secondaryTitle,
                countdown: secondaryCountdown,
                help: quotaResetHelp(primaryTitle: primaryTitle, primaryCountdown: primaryCountdown, secondaryTitle: secondaryTitle, secondaryCountdown: secondaryCountdown)
            )
        }
        return nil
    }

    return QuotaResetCountdownDisplay(
        title: preferred.0,
        countdown: countdown,
        help: quotaResetHelp(primaryTitle: primaryTitle, primaryCountdown: primaryCountdown, secondaryTitle: secondaryTitle, secondaryCountdown: secondaryCountdown)
    )
}

private func quotaResetHelp(
    primaryTitle: String,
    primaryCountdown: String?,
    secondaryTitle: String,
    secondaryCountdown: String?
) -> String {
    [
        "\(primaryTitle) resets in \(primaryCountdown ?? "-")",
        "\(secondaryTitle) resets in \(secondaryCountdown ?? "-")"
    ].joined(separator: "\n")
}

private func quotaWindowCountdown(until date: Date?) -> String? {
    guard let date else { return nil }
    let remainingSeconds = Int(ceil(date.timeIntervalSinceNow))
    guard remainingSeconds > 0 else { return "<1m" }

    let minutes = Int(ceil(Double(remainingSeconds) / 60.0))
    if minutes >= 24 * 60 {
        let days = minutes / (24 * 60)
        let restHours = (minutes % (24 * 60)) / 60
        return restHours == 0 ? "\(days)d" : "\(days)d \(restHours)h"
    }
    if minutes < 60 {
        return "\(minutes)m"
    }

    let hours = minutes / 60
    let restMinutes = minutes % 60
    return restMinutes == 0 ? "\(hours)h" : "\(hours)h \(restMinutes)m"
}

private struct ProfileMetadataLine: View {
    let profile: CodexProfile
    var showModel: Bool = false

    var body: some View {
        let summary = profile.summary
        HStack(spacing: 6) {
            if showModel, let model = summary.model {
                Text("Model: \(model)")
            }
            if let providerHost = summary.providerHost {
                Text("·")
                Text(providerHost)
            }
            if let lastRefreshText = summary.lastRefreshText {
                Text("·")
                Text(AppText.s("Refresh: \(lastRefreshText)", "刷新：\(lastRefreshText)"))
            }
        }
        .font(.system(size: 9))
        .foregroundColor(.secondary)
        .lineLimit(1)
        .truncationMode(.tail)
    }
}

private struct UsageStatusLine: View {
    let state: UsageRefreshState
    let prominent: Bool

    var body: some View {
        switch state {
        case .idle:
            EmptyView()
        case .loading:
            Text(AppText.s("Refreshing", "刷新中"))
                .font(.system(size: 9))
                .foregroundColor(.secondary)
        case .loaded(let snapshot):
            HStack(spacing: 6) {
                Badge(text: snapshot.planType.uppercased(), color: .purple)
                UsageMetric(
                    title: windowTitle(seconds: snapshot.primaryLimitWindowSeconds, fallback: "5h"),
                    value: percentText(snapshot.primaryRemainingPercent)
                )
                Text("·")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.secondary)
                UsageMetric(
                    title: windowTitle(seconds: snapshot.secondaryLimitWindowSeconds, fallback: "7d"),
                    value: percentText(snapshot.secondaryRemainingPercent)
                )
            }
        case .failed(let message):
            Text(message)
                .font(.system(size: 9))
                .foregroundColor(.red)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

private struct UsageMetric: View {
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.green)
        }
    }
}

private func percentText(_ value: Double) -> String {
    "\(Int(value.rounded()))%"
}

private func windowTitle(seconds: Int?, fallback: String) -> String {
    guard let seconds else {
        return fallback
    }
    if seconds >= 86_400 {
        let days = max(1, seconds / 86_400)
        return "\(days)d"
    }
    if seconds >= 3_600 {
        let hours = max(1, seconds / 3_600)
        return "\(hours)h"
    }
    return fallback
}

enum UsageRefreshState {
    case idle
    case loading
    case loaded(OpenAIQuotaSnapshot)
    case failed(String)

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
}

private struct InlineMessage: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundColor(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.06))
            )
    }
}

private struct Badge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .foregroundColor(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.12)))
    }
}

private extension CodexProfileKind {
    var menuColor: Color {
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
