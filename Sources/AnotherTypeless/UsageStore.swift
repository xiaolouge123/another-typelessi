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

struct UsageRecord: Codable {
    let id: UUID
    let timestamp: Date
    let operation: UsageOperation
    let model: String
    let resolvedModel: String?
    let promptTokens: Int
    let completionTokens: Int
    let totalTokens: Int
    let audioTokens: Int
    let cost: Double

    init(
        timestamp: Date = Date(),
        operation: UsageOperation,
        model: String,
        resolvedModel: String?,
        usage: OpenRouterUsage?
    ) {
        self.id = UUID()
        self.timestamp = timestamp
        self.operation = operation
        self.model = model
        self.resolvedModel = resolvedModel
        self.promptTokens = usage?.promptTokens ?? 0
        self.completionTokens = usage?.completionTokens ?? 0
        self.totalTokens = usage?.totalTokens ?? 0
        self.audioTokens = usage?.audioTokens ?? 0
        self.cost = usage?.cost ?? 0
    }
}

struct WeeklyModelUsage: Identifiable {
    let weekStart: Date
    let operation: UsageOperation
    let model: String
    let calls: Int
    let promptTokens: Int
    let completionTokens: Int
    let totalTokens: Int
    let audioTokens: Int
    let cost: Double

    var id: String {
        "\(weekStart.timeIntervalSince1970)-\(operation.rawValue)-\(model)"
    }

    var weekLabel: String {
        Self.weekFormatter.string(from: weekStart)
    }

    var operationText: String {
        operation.title
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

    var audioTokensText: String {
        Self.integerFormatter.string(from: NSNumber(value: audioTokens)) ?? "\(audioTokens)"
    }

    var callsText: String {
        Self.integerFormatter.string(from: NSNumber(value: calls)) ?? "\(calls)"
    }

    var costText: String {
        String(format: "$%.6f", cost)
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
                    model: record.resolvedModel?.nilIfBlank ?? record.model
                )
            }

            return grouped.map { key, records in
                WeeklyModelUsage(
                    weekStart: key.weekStart,
                    operation: key.operation,
                    model: key.model,
                    calls: records.count,
                    promptTokens: records.reduce(0) { $0 + $1.promptTokens },
                    completionTokens: records.reduce(0) { $0 + $1.completionTokens },
                    totalTokens: records.reduce(0) { $0 + $1.totalTokens },
                    audioTokens: records.reduce(0) { $0 + $1.audioTokens },
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
    let model: String
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
