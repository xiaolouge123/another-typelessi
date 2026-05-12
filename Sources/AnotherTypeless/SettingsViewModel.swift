import Foundation

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var apiKey: String = ""
    @Published var hasStoredAPIKey: Bool = false
    @Published var baseURL: String
    @Published var transcriptionModel: String
    @Published var polishModel: String
    @Published var outputMode: OutputMode
    @Published var language: RecognitionLanguage
    @Published var cleanFillers: Bool
    @Published var polishWithGPT: Bool
    @Published var restoreClipboard: Bool
    @Published var duckingLevel: Double
    @Published var configFilePath: String
    @Published var usageFilePath: String
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
        self.cleanFillers = settings.cleanFillers
        self.polishWithGPT = settings.polishWithGPT
        self.restoreClipboard = settings.restoreClipboard
        self.duckingLevel = settings.duckingLevel
        self.configFilePath = settings.configFileURL.path
        self.usageFilePath = usageStore.usageFileURL.path
        self.hasStoredAPIKey = settings.apiKey != nil
        refreshUsage()
    }

    func save() {
        do {
            let normalizedBaseURL = try Self.validateBaseURL(baseURL)
            let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

            try settings.update(
                baseURLString: normalizedBaseURL.absoluteString,
                transcriptionModel: transcriptionModel,
                polishModel: polishModel,
                outputMode: outputMode,
                language: language,
                cleanFillers: cleanFillers,
                polishWithGPT: polishWithGPT,
                restoreClipboard: restoreClipboard,
                duckingLevel: duckingLevel,
                apiKey: trimmedAPIKey.isEmpty ? nil : trimmedAPIKey
            )

            duckingLevel = settings.duckingLevel

            if !trimmedAPIKey.isEmpty {
                apiKey = ""
            }

            hasStoredAPIKey = settings.apiKey != nil
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
            statusMessage = "API key cleared"
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
        cleanFillers = true
        polishWithGPT = true
        restoreClipboard = true
        duckingLevel = SettingsStore.defaultDuckingLevel
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
