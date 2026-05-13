import Foundation
import AppKit

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var apiKey: String = ""
    @Published var hasStoredAPIKey: Bool = false
    @Published var baseURL: String
    @Published var transcriptionModel: String
    @Published var polishModel: String
    @Published var outputMode: OutputMode
    @Published var language: RecognitionLanguage
    @Published var polishWithGPT: Bool
    @Published var restoreClipboard: Bool
    @Published var duckingLevel: Double
    @Published var preferredMicrophone: MicrophonePreference
    @Published var transcriptionProvider: TranscriptionProvider
    @Published var deepgramAPIKey: String = ""
    @Published var hasStoredDeepgramAPIKey: Bool = false
    @Published var deepgramModel: String
    @Published var configFilePath: String
    @Published var usageFilePath: String
    @Published var logFilePath: String
    @Published var usageSummaries: [WeeklyModelUsage] = []
    @Published var statusMessage: String = ""

    private let settings: SettingsStore
    private let usageStore: UsageStore

    init(settings: SettingsStore, usageStore: UsageStore) {
        self.settings = settings
        self.usageStore = usageStore
        self.baseURL = settings.baseURLString
        self.transcriptionModel = settings.transcriptionModel
        self.polishModel = settings.polishModel
        self.outputMode = settings.outputMode
        self.language = settings.language
        self.polishWithGPT = settings.polishWithGPT
        self.restoreClipboard = settings.restoreClipboard
        self.duckingLevel = settings.duckingLevel
        self.preferredMicrophone = settings.preferredMicrophone
        self.transcriptionProvider = settings.transcriptionProvider
        self.deepgramModel = settings.deepgramModel
        self.configFilePath = settings.configFileURL.path
        self.usageFilePath = usageStore.usageFileURL.path
        self.logFilePath = DictationLogger.shared.fileURL.path
        self.hasStoredAPIKey = settings.apiKey != nil
        self.hasStoredDeepgramAPIKey = settings.deepgramAPIKey != nil
        refreshUsage()
    }

    func save() {
        do {
            let normalizedBaseURL = try Self.validateBaseURL(baseURL)
            let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedDeepgramAPIKey = deepgramAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)

            try settings.update(
                baseURLString: normalizedBaseURL.absoluteString,
                transcriptionModel: transcriptionModel,
                polishModel: polishModel,
                outputMode: outputMode,
                language: language,
                polishWithGPT: polishWithGPT,
                restoreClipboard: restoreClipboard,
                duckingLevel: duckingLevel,
                preferredMicrophone: preferredMicrophone,
                transcriptionProvider: transcriptionProvider,
                deepgramModel: deepgramModel,
                apiKey: trimmedAPIKey.isEmpty ? nil : trimmedAPIKey,
                deepgramAPIKey: trimmedDeepgramAPIKey.isEmpty ? nil : trimmedDeepgramAPIKey
            )

            duckingLevel = settings.duckingLevel

            if !trimmedAPIKey.isEmpty {
                apiKey = ""
            }
            if !trimmedDeepgramAPIKey.isEmpty {
                deepgramAPIKey = ""
            }

            hasStoredAPIKey = settings.apiKey != nil
            hasStoredDeepgramAPIKey = settings.deepgramAPIKey != nil
            statusMessage = "Saved to local config"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func clearAPIKey() {
        do {
            try settings.clearAPIKey()
            apiKey = ""
            hasStoredAPIKey = false
            statusMessage = "OpenRouter API key cleared"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func clearDeepgramAPIKey() {
        do {
            try settings.clearDeepgramAPIKey()
            deepgramAPIKey = ""
            hasStoredDeepgramAPIKey = false
            statusMessage = "Deepgram API key cleared"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func resetToDefaults() {
        baseURL = SettingsStore.defaultBaseURLString
        transcriptionModel = SettingsStore.defaultTranscriptionModel
        polishModel = SettingsStore.defaultPolishModel
        outputMode = .pasteAtCursor
        language = SettingsStore.defaultLanguage
        polishWithGPT = true
        restoreClipboard = true
        duckingLevel = SettingsStore.defaultDuckingLevel
        preferredMicrophone = SettingsStore.defaultMicrophonePreference
        transcriptionProvider = SettingsStore.defaultTranscriptionProvider
        deepgramModel = SettingsStore.defaultDeepgramModel
        statusMessage = "Defaults loaded; click Save"
    }

    func refreshUsage() {
        usageSummaries = usageStore.weeklySummaries()
    }

    func clearUsage() {
        do {
            try usageStore.clear()
            refreshUsage()
            statusMessage = "Usage cleared"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func clearDictationLog() {
        let url = DictationLogger.shared.fileURL
        do {
            try Data().write(to: url, options: [.atomic])
            LocalFileSecurity.protectFile(url)
            statusMessage = "Dictation log cleared"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func revealDictationLog() {
        NSWorkspace.shared.selectFile(
            DictationLogger.shared.fileURL.path,
            inFileViewerRootedAtPath: DictationLogger.shared.fileURL.deletingLastPathComponent().path
        )
    }

    private static func validateBaseURL(_ rawValue: String) throws -> URL {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil,
              !trimmed.isEmpty else {
            throw SettingsViewModelError.invalidBaseURL
        }

        return url
    }
}

enum SettingsViewModelError: LocalizedError {
    case invalidBaseURL

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            return "Enter a valid base URL such as https://openrouter.ai/api/v1."
        }
    }
}
