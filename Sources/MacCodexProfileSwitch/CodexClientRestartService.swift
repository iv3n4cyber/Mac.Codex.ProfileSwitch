import AppKit
import Foundation

struct RestartResult {
    let started: Bool
    let message: String
}

@MainActor
final class CodexClientRestartService {
    private let bundleIdentifiers = [
        "com.openai.codex",
        "com.openai.Codex",
        "ai.openai.codex"
    ]

    func restart() -> RestartResult {
        let runningApplications = findRunningCodexApplications()
        let knownURL = runningApplications.compactMap(\.bundleURL).first

        stopApplications(runningApplications)

        if let knownURL {
            NSWorkspace.shared.openApplication(at: knownURL, configuration: NSWorkspace.OpenConfiguration())
            return RestartResult(
                started: true,
                message: AppText.s(
                    "Closed and restarted the Codex client.",
                    "已关闭并重新启动 Codex 客户端。"
                )
            )
        }

        if openCodexByName() {
            return RestartResult(
                started: true,
                message: AppText.s(
                    "Closed and restarted the Codex client.",
                    "已关闭并重新启动 Codex 客户端。"
                )
            )
        }

        return RestartResult(
            started: false,
            message: AppText.s(
                "Closed the running Codex client, but no launchable Codex app was found. Please open Codex manually once.",
                "已关闭正在运行的 Codex 客户端，但没有找到可启动的 Codex app。请手动打开一次 Codex。"
            )
        )
    }

    private func findRunningCodexApplications() -> [NSRunningApplication] {
        var applications: [NSRunningApplication] = []
        for bundleIdentifier in bundleIdentifiers {
            applications.append(contentsOf: NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier))
        }

        let namedApplications = NSWorkspace.shared.runningApplications.filter {
            ($0.localizedName ?? "").caseInsensitiveCompare("Codex") == .orderedSame
        }

        let allApplications = applications + namedApplications
        var seen = Set<pid_t>()
        return allApplications.filter { application in
            seen.insert(application.processIdentifier).inserted
        }
    }

    private func stopApplications(_ applications: [NSRunningApplication]) {
        for application in applications {
            application.terminate()
        }

        waitUntilStopped(applications, timeout: 5)

        for application in applications where !application.isTerminated {
            application.forceTerminate()
        }

        waitUntilStopped(applications, timeout: 3)
    }

    private func waitUntilStopped(_ applications: [NSRunningApplication], timeout: TimeInterval) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline && applications.contains(where: { !$0.isTerminated }) {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.1))
        }
    }

    private func openCodexByName() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", "Codex"]

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}
