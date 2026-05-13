import Foundation

struct TokenUsage: Codable, Equatable {
    var inputTokens: Int = 0
    var cachedInputTokens: Int = 0
    var outputTokens: Int = 0

    var totalTokens: Int {
        inputTokens + cachedInputTokens + outputTokens
    }

    var isZero: Bool {
        inputTokens == 0 && cachedInputTokens == 0 && outputTokens == 0
    }

    static func +(lhs: TokenUsage, rhs: TokenUsage) -> TokenUsage {
        TokenUsage(
            inputTokens: lhs.inputTokens + rhs.inputTokens,
            cachedInputTokens: lhs.cachedInputTokens + rhs.cachedInputTokens,
            outputTokens: lhs.outputTokens + rhs.outputTokens
        )
    }

    func delta(from previous: TokenUsage) -> TokenUsage {
        TokenUsage(
            inputTokens: max(0, inputTokens - previous.inputTokens),
            cachedInputTokens: max(0, cachedInputTokens - previous.cachedInputTokens),
            outputTokens: max(0, outputTokens - previous.outputTokens)
        )
    }
}

struct DailyTokenUsage: Codable, Identifiable, Equatable {
    let date: Date
    let usage: TokenUsage

    var id: Date { date }
}

struct LocalTokenUsageSummary: Equatable {
    let today: TokenUsage
    let last30Days: TokenUsage
    let lifetime: TokenUsage
    let daily: [DailyTokenUsage]

    static let empty = LocalTokenUsageSummary(
        today: TokenUsage(),
        last30Days: TokenUsage(),
        lifetime: TokenUsage(),
        daily: []
    )
}

struct LocalTokenUsageService {
    private struct FileFingerprint: Codable, Equatable {
        let fileSize: Int
        let modificationDate: Date
    }

    private struct UsageEvent: Codable, Equatable {
        let timestamp: Date
        let usage: TokenUsage
    }

    private struct CachedSessionUsage: Codable {
        let fingerprint: FileFingerprint
        let events: [UsageEvent]
    }

    private struct PersistedCache: Codable {
        let version: Int
        let files: [String: CachedSessionUsage]
    }

    private struct UsageSample {
        let timestamp: Date?
        let totalUsage: TokenUsage
        let incrementalUsage: TokenUsage?
    }

    private let persistedCacheVersion = 1

    private let fileManager: FileManager
    private let codexRoot: URL
    private let calendar: Calendar
    private let cacheURL: URL

    init(
        fileManager: FileManager = .default,
        codexRoot: URL = CodexPaths.codexRoot,
        calendar: Calendar = .current,
        cacheURL: URL = CodexPaths.tokenUsageSessionCache
    ) {
        self.fileManager = fileManager
        self.codexRoot = codexRoot
        self.calendar = calendar
        self.cacheURL = cacheURL
    }

    func load(now: Date = Date()) -> LocalTokenUsageSummary {
        let todayStart = calendar.startOfDay(for: now)
        let last30Start = calendar.date(byAdding: .day, value: -29, to: todayStart) ?? todayStart

        var today = TokenUsage()
        var last30 = TokenUsage()
        var lifetime = TokenUsage()
        var daily: [Date: TokenUsage] = [:]

        for event in self.usageEvents(refreshCache: true) {
            lifetime = lifetime + event.usage
            let day = calendar.startOfDay(for: event.timestamp)
            daily[day] = (daily[day] ?? TokenUsage()) + event.usage
            if event.timestamp >= last30Start {
                last30 = last30 + event.usage
            }
            if event.timestamp >= todayStart {
                today = today + event.usage
            }
        }

        let chartStart = calendar.date(byAdding: .day, value: -13, to: todayStart) ?? todayStart
        let chartDays = (0..<14).compactMap { offset -> DailyTokenUsage? in
            guard let day = calendar.date(byAdding: .day, value: offset, to: chartStart) else {
                return nil
            }
            return DailyTokenUsage(date: day, usage: daily[day] ?? TokenUsage())
        }

        return LocalTokenUsageSummary(
            today: today,
            last30Days: last30,
            lifetime: lifetime,
            daily: chartDays
        )
    }

    private func usageEvents(refreshCache: Bool) -> [UsageEvent] {
        let files = self.sessionFiles()
        var previousCache = refreshCache ? self.loadPersistedCache() : [:]
        var nextCache: [URL: CachedSessionUsage] = [:]
        nextCache.reserveCapacity(files.count)

        var events: [UsageEvent] = []
        events.reserveCapacity(previousCache.values.reduce(0) { $0 + $1.events.count })

        for fileURL in files {
            autoreleasepool {
                guard let fingerprint = self.fingerprint(for: fileURL) else { return }
                let cached = previousCache.removeValue(forKey: fileURL)
                let sessionUsage: CachedSessionUsage
                if let cached, cached.fingerprint == fingerprint {
                    sessionUsage = cached
                } else {
                    sessionUsage = CachedSessionUsage(
                        fingerprint: fingerprint,
                        events: self.usageEvents(in: fileURL, fingerprint: fingerprint)
                    )
                }

                nextCache[fileURL] = sessionUsage
                events.append(contentsOf: sessionUsage.events)
            }
        }

        if refreshCache {
            self.persistSessionCache(nextCache)
        }

        return events
    }

    private func sessionFiles() -> [URL] {
        let directories = [
            codexRoot.appendingPathComponent("sessions", isDirectory: true),
            codexRoot.appendingPathComponent("archived_sessions", isDirectory: true)
        ]

        var files: [URL] = []
        for directory in directories where fileManager.fileExists(atPath: directory.path) {
            guard let enumerator = fileManager.enumerator(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }
            while let url = enumerator.nextObject() as? URL {
                guard url.pathExtension == "jsonl" else { continue }
                files.append(url)
            }
        }
        return files.sorted { $0.path < $1.path }
    }

    private func fingerprint(for fileURL: URL) -> FileFingerprint? {
        guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]),
              values.isRegularFile == true else { return nil }

        return FileFingerprint(
            fileSize: values.fileSize ?? 0,
            modificationDate: values.contentModificationDate ?? .distantPast
        )
    }

    private func usageEvents(in fileURL: URL, fingerprint: FileFingerprint) -> [UsageEvent] {
        var highWater: TokenUsage?
        var events: [UsageEvent] = []

        self.enumerateLines(in: fileURL) { line in
            guard let sample = self.parseUsageSample(from: line) else { return }
            let incremental = highWater.map { sample.totalUsage.delta(from: $0) }
                ?? sample.incrementalUsage
                ?? sample.totalUsage
            highWater = highWater.map {
                TokenUsage(
                    inputTokens: max($0.inputTokens, sample.totalUsage.inputTokens),
                    cachedInputTokens: max($0.cachedInputTokens, sample.totalUsage.cachedInputTokens),
                    outputTokens: max($0.outputTokens, sample.totalUsage.outputTokens)
                )
            } ?? sample.totalUsage

            guard incremental.isZero == false else { return }
            let timestamp = sample.timestamp ?? fingerprint.modificationDate.addingTimeInterval(Double(events.count) / 1000)
            events.append(UsageEvent(timestamp: timestamp, usage: incremental))
        }

        return events
    }

    private func parseUsageSample(from line: String) -> UsageSample? {
        guard line.contains("\"type\":\"event_msg\""),
              line.contains("\"token_count\""),
              line.contains("\"total_token_usage\""),
              let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = object["payload"] as? [String: Any] else {
            return nil
        }

        let timestamp = (object["timestamp"] as? String).flatMap(Self.parseDate)
        if let payloadType = payload["type"] as? String,
           payloadType == "event_msg",
           let total = payload["total_token_usage"] as? [String: Any] {
            return UsageSample(
                timestamp: timestamp,
                totalUsage: self.parseUsage(total),
                incrementalUsage: (payload["last_token_usage"] as? [String: Any]).map(self.parseUsage)
            )
        }

        guard let payloadType = payload["type"] as? String,
              payloadType == "token_count",
              let info = payload["info"] as? [String: Any],
              let total = info["total_token_usage"] as? [String: Any] else {
            return nil
        }

        return UsageSample(
            timestamp: timestamp,
            totalUsage: self.parseUsage(total),
            incrementalUsage: (info["last_token_usage"] as? [String: Any]).map(self.parseUsage)
        )
    }

    private func parseUsage(_ object: [String: Any]) -> TokenUsage {
        TokenUsage(
            inputTokens: object["input_tokens"] as? Int ?? 0,
            cachedInputTokens: object["cached_input_tokens"] as? Int ?? 0,
            outputTokens: object["output_tokens"] as? Int ?? 0
        )
    }

    private func enumerateLines(in fileURL: URL, handleLine: (String) -> Void) {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return }
        defer { try? handle.close() }

        var buffer = Data()
        let newline = UInt8(ascii: "\n")
        while let chunk = try? handle.read(upToCount: 64 * 1024), chunk.isEmpty == false {
            buffer.append(chunk)
            while let newlineIndex = buffer.firstIndex(of: newline) {
                emitLine(buffer[..<newlineIndex], handleLine: handleLine)
                buffer.removeSubrange(buffer.startIndex...newlineIndex)
            }
        }
        if buffer.isEmpty == false {
            emitLine(buffer[buffer.startIndex..<buffer.endIndex], handleLine: handleLine)
        }
    }

    private func emitLine(_ bytes: Data.SubSequence, handleLine: (String) -> Void) {
        var slice = bytes
        if slice.last == UInt8(ascii: "\r") {
            slice = slice.dropLast()
        }
        guard slice.isEmpty == false,
              let line = String(data: Data(slice), encoding: .utf8) else {
            return
        }
        handleLine(line)
    }

    private static func parseDate(_ value: String) -> Date? {
        ISO8601DateFormatter().date(from: value)
    }

    private func loadPersistedCache() -> [URL: CachedSessionUsage] {
        guard let data = try? Data(contentsOf: cacheURL) else { return [:] }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let persisted = try? decoder.decode(PersistedCache.self, from: data),
              persisted.version == persistedCacheVersion else {
            return [:]
        }

        var cache: [URL: CachedSessionUsage] = [:]
        cache.reserveCapacity(persisted.files.count)
        for (path, record) in persisted.files {
            cache[URL(fileURLWithPath: path)] = record
        }
        return cache
    }

    private func persistSessionCache(_ cache: [URL: CachedSessionUsage]) {
        let payload = PersistedCache(
            version: persistedCacheVersion,
            files: Dictionary(uniqueKeysWithValues: cache.map { ($0.key.path, $0.value) })
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        guard let data = try? encoder.encode(payload) else { return }
        do {
            try fileManager.createDirectory(
                at: cacheURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: cacheURL, options: [.atomic])
        } catch {
            return
        }
    }
}
