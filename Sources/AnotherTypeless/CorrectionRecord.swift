import Foundation

/// Represents a single correction made by the user
struct CorrectionRecord: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let asrOutput: String
    let userCorrected: String
    let similarity: Double
    let sessionID: Int

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        asrOutput: String,
        userCorrected: String,
        similarity: Double,
        sessionID: Int
    ) {
        self.id = id
        self.timestamp = timestamp
        self.asrOutput = asrOutput
        self.userCorrected = userCorrected
        self.similarity = similarity
        self.sessionID = sessionID
    }
}

/// Stores and manages correction records
final class CorrectionStore {
    private let fileURL: URL
    private var records: [CorrectionRecord] = []
    private let maxRecords = 100 // Keep last 100 records
    private let queue = DispatchQueue(label: "com.anothertypeless.correctionstore")

    init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let appDir = appSupport.appendingPathComponent("AnotherTypeless", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        fileURL = appDir.appendingPathComponent("corrections.json")
        load()
    }

    func append(_ record: CorrectionRecord) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.records.append(record)

            // Keep only the most recent records
            if self.records.count > self.maxRecords {
                self.records.removeFirst(self.records.count - self.maxRecords)
            }

            self.save()

            DictationLogger.shared.log(
                "correction",
                "recorded sessionID=\(record.sessionID) similarity=\(String(format: "%.2f", record.similarity)) asr=\(record.asrOutput.prefix(50)) corrected=\(record.userCorrected.prefix(50))"
            )
        }
    }

    func getRecentRecords(count: Int = 20) -> [CorrectionRecord] {
        queue.sync {
            Array(records.suffix(count))
        }
    }

    func getAllRecords() -> [CorrectionRecord] {
        queue.sync {
            records
        }
    }

    func clear() {
        queue.async { [weak self] in
            self?.records.removeAll()
            self?.save()
        }
    }

    private func load() {
        queue.async { [weak self] in
            guard let self = self,
                  FileManager.default.fileExists(atPath: self.fileURL.path),
                  let data = try? Data(contentsOf: self.fileURL),
                  let decoded = try? JSONDecoder().decode([CorrectionRecord].self, from: data) else {
                return
            }
            self.records = decoded
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(records) else {
            return
        }
        try? data.write(to: fileURL, options: .atomic)
    }
}
