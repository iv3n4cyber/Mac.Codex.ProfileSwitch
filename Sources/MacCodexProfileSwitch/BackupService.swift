import AppKit
import Foundation

struct BackupScanGroup: Equatable {
    let title: String
    let totalCount: Int
    let previewPaths: [String]
}

struct BackupScanResult: Equatable {
    let sessions: BackupScanGroup
    let profiles: BackupScanGroup
    let currentFiles: BackupScanGroup
    let scannedAt: Date
}

enum BackupKind {
    case sessions
    case profiles
    case currentFiles

    var filePrefix: String {
        switch self {
        case .sessions:
            return "session"
        case .profiles:
            return "profile"
        case .currentFiles:
            return "current-auth-config"
        }
    }
}

@MainActor
final class BackupService {
    func scan() -> BackupScanResult {
        BackupScanResult(
            sessions: BackupScanGroup(
                title: AppText.s("Sessions", "Sessions"),
                totalCount: sessionFiles().count,
                previewPaths: sessionFiles().prefix(5).map(\.path)
            ),
            profiles: BackupScanGroup(
                title: AppText.s("Profiles", "Profiles"),
                totalCount: profileDirectories().count,
                previewPaths: profileDirectories().prefix(5).map(\.path)
            ),
            currentFiles: BackupScanGroup(
                title: AppText.s("Current auth/config", "当前 auth/config"),
                totalCount: currentCodexFiles().count,
                previewPaths: currentCodexFiles().prefix(5).map(\.path)
            ),
            scannedAt: Date()
        )
    }

    func backup(_ kind: BackupKind) throws -> URL? {
        let destinationName = "\(kind.filePrefix)-\(timestamp()).zip"
        guard let destinationURL = chooseDestination(defaultName: destinationName) else {
            return nil
        }

        let sourceURLs = sources(for: kind)
        guard sourceURLs.isEmpty == false else {
            throw ProfileSwitchError.message(AppText.s(
                "Nothing found to back up.",
                "没有找到可备份的内容。"
            ))
        }

        let stagingRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacCodexProfileSwitchBackup-\(UUID().uuidString)", isDirectory: true)
        let payloadRoot = stagingRoot.appendingPathComponent(kind.filePrefix, isDirectory: true)

        try FileManager.default.createDirectory(at: payloadRoot, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: stagingRoot)
        }

        for sourceURL in sourceURLs {
            let targetURL = payloadRoot.appendingPathComponent(sourceURL.lastPathComponent, isDirectory: isDirectory(sourceURL))
            try FileManager.default.copyItem(at: sourceURL, to: targetURL)
        }

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }

        try createZip(from: payloadRoot, to: destinationURL)
        return destinationURL
    }

    private func sources(for kind: BackupKind) -> [URL] {
        switch kind {
        case .sessions:
            return [
                CodexPaths.codexRoot.appendingPathComponent("sessions", isDirectory: true),
                CodexPaths.codexRoot.appendingPathComponent("archived_sessions", isDirectory: true)
            ].filter { FileManager.default.fileExists(atPath: $0.path) }
        case .profiles:
            return FileManager.default.fileExists(atPath: CodexPaths.profilesRoot.path) ? [CodexPaths.profilesRoot] : []
        case .currentFiles:
            return currentCodexFiles()
        }
    }

    private func sessionFiles() -> [URL] {
        [
            CodexPaths.codexRoot.appendingPathComponent("sessions", isDirectory: true),
            CodexPaths.codexRoot.appendingPathComponent("archived_sessions", isDirectory: true)
        ].flatMap { recursiveFiles(under: $0) }
            .sorted { $0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending }
    }

    private func profileDirectories() -> [URL] {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: CodexPaths.profilesRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return urls.filter { isDirectory($0) }
            .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
    }

    private func currentCodexFiles() -> [URL] {
        [CodexPaths.authJSON, CodexPaths.configTOML]
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    private func recursiveFiles(under root: URL) -> [URL] {
        guard FileManager.default.fileExists(atPath: root.path),
              let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
              ) else {
            return []
        }

        return enumerator.compactMap { item -> URL? in
            guard let url = item as? URL,
                  (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
                return nil
            }
            return url
        }
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    private func chooseDestination(defaultName: String) -> URL? {
        let panel = NSSavePanel()
        panel.title = AppText.s("Choose Backup Location", "选择备份保存位置")
        panel.nameFieldStringValue = defaultName
        panel.allowedContentTypes = [.zip]
        panel.canCreateDirectories = true
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func createZip(from sourceURL: URL, to destinationURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", sourceURL.path, destinationURL.path]

        let errorPipe = Pipe()
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw ProfileSwitchError.message(message?.isEmpty == false ? message! : "Failed to create zip backup.")
        }
    }

    private func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
}
