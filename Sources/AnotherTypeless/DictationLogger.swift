import Foundation

final class DictationLogger: @unchecked Sendable {
    static let shared = DictationLogger()

    let fileURL: URL

    private let queue = DispatchQueue(label: "com.local.another-typeless.dictation-log")
    private let mirrorToStandardError: Bool

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private init() {
        self.fileURL = Self.defaultLogFileURL()
        self.mirrorToStandardError = ProcessInfo.processInfo.environment["ANOTHER_TYPELESS_LOG_STDERR"] != nil
        ensureLogFileExists()
    }

    func log(_ tag: String, _ message: String) {
        queue.async { [self] in
            append("\(timestampPrefix()) [\(tag)] \(message)\n")
        }
    }

    func logText(_ tag: String, _ text: String) {
        queue.async { [self] in
            let indented = text
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map { "    \($0)" }
                .joined(separator: "\n")
            let header = "\(timestampPrefix()) [\(tag)] (\(text.count) chars)"
            append("\(header)\n\(indented)\n")
        }
    }

    private func timestampPrefix() -> String {
        Self.timestampFormatter.string(from: Date())
    }

    private func append(_ line: String) {
        guard let data = line.data(using: .utf8) else {
            return
        }

        if mirrorToStandardError {
            FileHandle.standardError.write(data)
        }

        ensureLogFileExists()
        guard let handle = try? FileHandle(forWritingTo: fileURL) else {
            return
        }
        defer { try? handle.close() }

        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            // Best-effort logging; if the file handle misbehaves, swallow the
            // error so a failed log write never takes the main flow down.
        }
    }

    private func ensureLogFileExists() {
        let directory = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        LocalFileSecurity.protectDirectory(directory)

        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
            LocalFileSecurity.protectFile(fileURL)
        }
    }

    private static func defaultLogFileURL() -> URL {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)

        return applicationSupport
            .appendingPathComponent(AppMetadata.appSupportDirectoryName, isDirectory: true)
            .appendingPathComponent("dictation.log")
    }
}
