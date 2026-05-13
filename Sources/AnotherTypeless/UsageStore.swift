import Foundation

enum UsageOperation: String, Codable {
    case transcription
    case polish

    var title: String {
        switch self {
        case .transcription:
            return "Transcribe"
        case .polish:
            return "Polish"
        }
    }

    var sortOrder: Int {
        switch self {
        case .transcription:
            return 0
        case .polish:
            return 1
        }
    }
}

enum UsageProvider: String, Codable {
    case openrouter
    case deepgram

    var title: String {
        switch self {
        case .openrouter:
            return "OpenRouter"
        case .deepgram:
            return "Deepgram"
        }
    }
}

struct UsageRecord: Codable {
    let id: UUID
    let timestamp: Date
    let operation: UsageOperation
    let provider: UsageProvider
    let model: String
    let resolvedModel: String?
    let promptTokens: Int
    let completionTokens: Int
    let totalTokens: Int
    let audioTokens: Int
    let audioSeconds: Double
    let elapsedSeconds: Double
    let cost: Double

    init(
        timestamp: Date = Date(),
        operation: UsageOperation,
        provider: UsageProvider,
        model: String,
        resolvedModel: String?,
        promptTokens: Int = 0,
        completionTokens: Int = 0,
        totalTokens: Int = 0,
        audioTokens: Int = 0,
        audioSeconds: Double = 0,
        elapsedSeconds: Double = 0,
        cost: Double = 0
    ) {
        self.id = UUID()
        self.timestamp = timestamp
        self.operation = operation
        self.provider = provider
        self.model = model
        self.resolvedModel = resolvedModel
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.totalTokens = totalTokens
        self.audioTokens = audioTokens
        self.audioSeconds = audioSeconds
        self.elapsedSeconds = elapsedSeconds
        self.cost = cost
    }

    init(
        timestamp: Date = Date(),
        operation: UsageOperation,
        provider: UsageProvider,
        model: String,
        resolvedModel: String?,
        elapsedSeconds: Double,
        usage: OpenRouterUsage?
    ) {
        self.init(
            timestamp: timestamp,
            operation: operation,
            provider: provider,
            model: model,
            resolvedModel: resolvedModel,
            promptTokens: usage?.promptTokens ?? 0,
            completionTokens: usage?.completionTokens ?? 0,
            totalTokens: usage?.totalTokens ?? 0,
            audioTokens: usage?.audioTokens ?? 0,
            audioSeconds: 0,
            elapsedSeconds: elapsedSeconds,
            cost: usage?.cost ?? 0
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id, timestamp, operation, provider, model, resolvedModel
        case promptTokens, completionTokens, totalTokens, audioTokens, audioSeconds, elapsedSeconds, cost
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.timestamp = try container.decode(Date.self, forKey: .timestamp)
        self.operation = try container.decode(UsageOperation.self, forKey: .operation)
        self.model = try container.decode(String.self, forKey: .model)
        self.resolvedModel = try container.decodeIfPresent(String.self, forKey: .resolvedModel)
        self.promptTokens = try container.decodeIfPresent(Int.self, forKey: .promptTokens) ?? 0
        self.completionTokens = try container.decodeIfPresent(Int.self, forKey: .completionTokens) ?? 0
        self.totalTokens = try container.decodeIfPresent(Int.self, forKey: .totalTokens) ?? 0
        self.audioTokens = try container.decodeIfPresent(Int.self, forKey: .audioTokens) ?? 0
        self.audioSeconds = try container.decodeIfPresent(Double.self, forKey: .audioSeconds) ?? 0
        self.elapsedSeconds = try container.decodeIfPresent(Double.self, forKey: .elapsedSeconds) ?? 0
        self.cost = try container.decodeIfPresent(Double.self, forKey: .cost) ?? 0

        let providerRaw = try container.decodeIfPresent(String.self, forKey: .provider) ?? ""
        self.provider = UsageProvider(rawValue: providerRaw) ?? .openrouter
    }
}

struct WeeklyModelUsage: Identifiable {
    let weekStart: Date
    let operation: UsageOperation
    let provider: UsageProvider
    let model: String
    let calls: Int
    let promptTokens: Int
    let completionTokens: Int
    let totalTokens: Int
    let audioTokens: Int
    let audioSeconds: Double
    let totalElapsedSeconds: Double
    let cost: Double

    var id: String {
        "\(weekStart.timeIntervalSince1970)-\(operation.rawValue)-\(provider.rawValue)-\(model)"
    }

    var weekLabel: String {
        Self.weekFormatter.string(from: weekStart)
    }

    var operationText: String {
        operation.title
    }

    var providerText: String {
        provider.title
    }

    var promptTokensText: String {
        Self.integerFormatter.string(from: NSNumber(value: promptTokens)) ?? "\(promptTokens)"
    }

    var completionTokensText: String {
        Self.integerFormatter.string(from: NSNumber(value: completionTokens)) ?? "\(completionTokens)"
    }

    var totalTokensText: String {
        Self.integerFormatter.string(from: NSNumber(value: totalTokens)) ?? "\(totalTokens)"
    }

    var audioText: String {
        switch provider {
        case .deepgram:
            return String(format: "%.1fs", audioSeconds)
        case .openrouter:
            return Self.integerFormatter.string(from: NSNumber(value: audioTokens)) ?? "\(audioTokens)"
        }
    }

    var callsText: String {
        Self.integerFormatter.string(from: NSNumber(value: calls)) ?? "\(calls)"
    }

    var costText: String {
        String(format: "$%.6f", cost)
    }

    var averageElapsedText: String {
        guard calls > 0, totalElapsedSeconds > 0 else {
            return "—"
        }
        return String(format: "%.2fs", totalElapsedSeconds / Double(calls))
    }

    private static let weekFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let integerFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()
}

final class UsageStore {
    private let queue = DispatchQueue(label: "com.local.another-typeless.usage-store")
    private let fileManager: FileManager
    private var records: [UsageRecord]

    let usageFileURL: URL

    init(fileManager: FileManager = .default, usageFileURL: URL? = nil) {
        self.fileManager = fileManager
        self.usageFileURL = usageFileURL ?? Self.defaultUsageFileURL(fileManager: fileManager)
        Self.migrateLegacyUsageIfNeeded(to: self.usageFileURL, fileManager: fileManager)
        self.records = (try? Self.loadRecords(from: self.usageFileURL)) ?? []
        persistIgnoringErrors()
    }

    func append(_ record: UsageRecord) {
        queue.sync {
            records.append(record)
            persistIgnoringErrors()
        }
    }

    func weeklySummaries(limitWeeks: Int = 8) -> [WeeklyModelUsage] {
        queue.sync {
            let calendar = Calendar(identifier: .iso8601)
            let cutoff = calendar.date(
                byAdding: .weekOfYear,
                value: -limitWeeks,
                to: Date()
            ) ?? .distantPast

            let grouped = Dictionary(grouping: records.filter { $0.timestamp >= cutoff }) { record in
                UsageAggregationKey(
                    weekStart: calendar.dateInterval(of: .weekOfYear, for: record.timestamp)?.start ?? record.timestamp,
                    operation: record.operation,
                    provider: record.provider,
                    model: record.resolvedModel?.nilIfBlank ?? record.model
                )
            }

            return grouped.map { key, records in
                WeeklyModelUsage(
                    weekStart: key.weekStart,
                    operation: key.operation,
                    provider: key.provider,
                    model: key.model,
                    calls: records.count,
                    promptTokens: records.reduce(0) { $0 + $1.promptTokens },
                    completionTokens: records.reduce(0) { $0 + $1.completionTokens },
                    totalTokens: records.reduce(0) { $0 + $1.totalTokens },
                    audioTokens: records.reduce(0) { $0 + $1.audioTokens },
                    audioSeconds: records.reduce(0) { $0 + $1.audioSeconds },
                    totalElapsedSeconds: records.reduce(0) { $0 + $1.elapsedSeconds },
                    cost: records.reduce(0) { $0 + $1.cost }
                )
            }
            .sorted {
                if $0.weekStart != $1.weekStart {
                    return $0.weekStart > $1.weekStart
                }
                if $0.operation != $1.operation {
                    return $0.operation.sortOrder < $1.operation.sortOrder
                }
                if $0.provider != $1.provider {
                    return $0.provider.rawValue < $1.provider.rawValue
                }
                return $0.model < $1.model
            }
        }
    }

    func clear() throws {
        try queue.sync {
            records = []
            try persist()
        }
    }

    private func persist() throws {
        let directory = usageFileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        LocalFileSecurity.protectDirectory(directory, fileManager: fileManager)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(records)
        try data.write(to: usageFileURL, options: [.atomic])
        LocalFileSecurity.protectFile(usageFileURL, fileManager: fileManager)
    }

    private func persistIgnoringErrors() {
        try? persist()
    }

    private static func loadRecords(from url: URL) throws -> [UsageRecord] {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([UsageRecord].self, from: data)
    }

    private static func defaultUsageFileURL(fileManager: FileManager) -> URL {
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)

        return applicationSupport
            .appendingPathComponent(AppMetadata.appSupportDirectoryName, isDirectory: true)
            .appendingPathComponent("usage.json")
    }

    private static func legacyUsageFileURL(fileManager: FileManager) -> URL {
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)

        return applicationSupport
            .appendingPathComponent(AppMetadata.legacyAppSupportDirectoryName, isDirectory: true)
            .appendingPathComponent("usage.json")
    }

    private static func migrateLegacyUsageIfNeeded(to usageFileURL: URL, fileManager: FileManager) {
        guard !fileManager.fileExists(atPath: usageFileURL.path) else {
            return
        }

        let legacyURL = legacyUsageFileURL(fileManager: fileManager)
        guard fileManager.fileExists(atPath: legacyURL.path) else {
            return
        }

        do {
            let directory = usageFileURL.deletingLastPathComponent()
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            LocalFileSecurity.protectDirectory(directory, fileManager: fileManager)
            try fileManager.moveItem(at: legacyURL, to: usageFileURL)
            LocalFileSecurity.protectFile(usageFileURL, fileManager: fileManager)
        } catch {
            try? fileManager.copyItem(at: legacyURL, to: usageFileURL)
            LocalFileSecurity.protectFile(usageFileURL, fileManager: fileManager)
        }
    }
}

private struct UsageAggregationKey: Hashable {
    let weekStart: Date
    let operation: UsageOperation
    let provider: UsageProvider
    let model: String
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
