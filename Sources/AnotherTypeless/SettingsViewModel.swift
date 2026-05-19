import Foundation
import AppKit

@MainActor
final class SettingsViewModel: ObservableObject {
    // Behavior
    @Published var outputMode: OutputMode
    @Published var language: RecognitionLanguage
    @Published var polishWithGPT: Bool
    @Published var restoreClipboard: Bool
    @Published var duckingLevel: Double
    @Published var preferredMicrophone: MicrophonePreference
    @Published var transcriptionProvider: TranscriptionProvider

    // Deepgram
    @Published var deepgramAPIKey: String = ""
    @Published var hasStoredDeepgramAPIKey: Bool = false
    @Published var deepgramBaseURL: String
    @Published var deepgramModel: String
    @Published var deepgramLanguage: String

    // Whisper (OpenRouter)
    @Published var whisperAPIKey: String = ""
    @Published var hasStoredWhisperAPIKey: Bool = false
    @Published var whisperBaseURL: String
    @Published var whisperModel: String
    @Published var whisperLanguage: String

    // ElevenLabs
    @Published var elevenLabsAPIKey: String = ""
    @Published var hasStoredElevenLabsAPIKey: Bool = false
    @Published var elevenLabsBaseURL: String
    @Published var elevenLabsModel: String
    @Published var elevenLabsLanguage: String

    // ElevenLabs Realtime
    @Published var elevenLabsRealtimeAPIKey: String = ""
    @Published var hasStoredElevenLabsRealtimeAPIKey: Bool = false
    @Published var elevenLabsRealtimeBaseURL: String
    @Published var elevenLabsRealtimeModel: String
    @Published var elevenLabsRealtimeLanguage: String

    // Doubao (Volcengine SAUC)
    @Published var doubaoAPIKey: String = ""
    @Published var hasStoredDoubaoAPIKey: Bool = false
    @Published var doubaoBaseURL: String
    @Published var doubaoResourceId: String
    @Published var doubaoLanguage: String

    // Polish
    @Published var polishAPIKey: String = ""
    @Published var hasStoredPolishAPIKey: Bool = false
    @Published var polishBaseURL: String
    @Published var polishModel: String

    // Misc
    @Published var configFilePath: String
    @Published var usageFilePath: String
    @Published var logFilePath: String
    @Published var usageSummaries: [WeeklyModelUsage] = []
    @Published var statusMessage: String = ""
    @Published var correctionRecords: [CorrectionRecord] = []

    private let settings: SettingsStore
    private let usageStore: UsageStore
    private let correctionStore: CorrectionStore

    init(settings: SettingsStore, usageStore: UsageStore, correctionStore: CorrectionStore) {
        self.settings = settings
        self.usageStore = usageStore
        self.correctionStore = correctionStore

        self.outputMode = settings.outputMode
        self.language = settings.language
        self.polishWithGPT = settings.polishWithGPT
        self.restoreClipboard = settings.restoreClipboard
        self.duckingLevel = settings.duckingLevel
        self.preferredMicrophone = settings.preferredMicrophone
        self.transcriptionProvider = settings.transcriptionProvider

        self.deepgramBaseURL = settings.deepgramBaseURL
        self.deepgramModel = settings.deepgramModel
        self.deepgramLanguage = settings.deepgramLanguage

        self.whisperBaseURL = settings.whisperBaseURLString
        self.whisperModel = settings.whisperModel
        self.whisperLanguage = settings.whisperLanguage

        self.elevenLabsBaseURL = settings.elevenLabsBaseURLString
        self.elevenLabsModel = settings.elevenLabsModel
        self.elevenLabsLanguage = settings.elevenLabsLanguage

        self.elevenLabsRealtimeBaseURL = settings.elevenLabsRealtimeBaseURL
        self.elevenLabsRealtimeModel = settings.elevenLabsRealtimeModel
        self.elevenLabsRealtimeLanguage = settings.elevenLabsRealtimeLanguage

        self.doubaoBaseURL = settings.doubaoBaseURL
        self.doubaoResourceId = settings.doubaoResourceId
        self.doubaoLanguage = settings.doubaoLanguage

        self.polishBaseURL = settings.polishBaseURLString
        self.polishModel = settings.polishModel

        self.configFilePath = settings.configFileURL.path
        self.usageFilePath = usageStore.usageFileURL.path
        self.logFilePath = DictationLogger.shared.fileURL.path

        self.hasStoredDeepgramAPIKey = settings.deepgramAPIKey != nil
        self.hasStoredWhisperAPIKey = settings.whisperAPIKey != nil
        self.hasStoredElevenLabsAPIKey = settings.elevenLabsAPIKey != nil
        self.hasStoredElevenLabsRealtimeAPIKey = settings.elevenLabsRealtimeAPIKey != nil
        self.hasStoredDoubaoAPIKey = settings.doubaoAPIKey != nil
        self.hasStoredPolishAPIKey = settings.polishAPIKey != nil

        refreshUsage()
    }

    func save() {
        do {
            // Validate base URLs
            _ = try Self.validateHTTPURL(whisperBaseURL, fieldLabel: "Whisper base URL")
            _ = try Self.validateHTTPURL(elevenLabsBaseURL, fieldLabel: "ElevenLabs base URL")
            _ = try Self.validateHTTPURL(polishBaseURL, fieldLabel: "Polish base URL")
            _ = try Self.validateWebSocketURL(deepgramBaseURL, fieldLabel: "Deepgram base URL")
            _ = try Self.validateWebSocketURL(elevenLabsRealtimeBaseURL, fieldLabel: "ElevenLabs Realtime base URL")
            _ = try Self.validateWebSocketURL(doubaoBaseURL, fieldLabel: "Doubao base URL")

            let trimmedDeepgramKey = deepgramAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedWhisperKey = whisperAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedElevenKey = elevenLabsAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedElevenRealtimeKey = elevenLabsRealtimeAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedDoubaoKey = doubaoAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedPolishKey = polishAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)

            let payload = SettingsStore.UpdatePayload(
                outputMode: outputMode,
                language: language,
                polishWithGPT: polishWithGPT,
                restoreClipboard: restoreClipboard,
                duckingLevel: duckingLevel,
                preferredMicrophone: preferredMicrophone,
                transcriptionProvider: transcriptionProvider,
                deepgramAPIKey: trimmedDeepgramKey.isEmpty ? nil : trimmedDeepgramKey,
                deepgramBaseURL: deepgramBaseURL,
                deepgramModel: deepgramModel,
                deepgramLanguage: deepgramLanguage,
                whisperAPIKey: trimmedWhisperKey.isEmpty ? nil : trimmedWhisperKey,
                whisperBaseURL: whisperBaseURL,
                whisperModel: whisperModel,
                whisperLanguage: whisperLanguage,
                elevenLabsAPIKey: trimmedElevenKey.isEmpty ? nil : trimmedElevenKey,
                elevenLabsBaseURL: elevenLabsBaseURL,
                elevenLabsModel: elevenLabsModel,
                elevenLabsLanguage: elevenLabsLanguage,
                elevenLabsRealtimeAPIKey: trimmedElevenRealtimeKey.isEmpty ? nil : trimmedElevenRealtimeKey,
                elevenLabsRealtimeBaseURL: elevenLabsRealtimeBaseURL,
                elevenLabsRealtimeModel: elevenLabsRealtimeModel,
                elevenLabsRealtimeLanguage: elevenLabsRealtimeLanguage,
                doubaoAPIKey: trimmedDoubaoKey.isEmpty ? nil : trimmedDoubaoKey,
                doubaoBaseURL: doubaoBaseURL,
                doubaoResourceId: doubaoResourceId,
                doubaoLanguage: doubaoLanguage,
                polishAPIKey: trimmedPolishKey.isEmpty ? nil : trimmedPolishKey,
                polishBaseURL: polishBaseURL,
                polishModel: polishModel
            )

            try settings.update(payload)

            duckingLevel = settings.duckingLevel

            if !trimmedDeepgramKey.isEmpty { deepgramAPIKey = "" }
            if !trimmedWhisperKey.isEmpty { whisperAPIKey = "" }
            if !trimmedElevenKey.isEmpty { elevenLabsAPIKey = "" }
            if !trimmedElevenRealtimeKey.isEmpty { elevenLabsRealtimeAPIKey = "" }
            if !trimmedDoubaoKey.isEmpty { doubaoAPIKey = "" }
            if !trimmedPolishKey.isEmpty { polishAPIKey = "" }

            hasStoredDeepgramAPIKey = settings.deepgramAPIKey != nil
            hasStoredWhisperAPIKey = settings.whisperAPIKey != nil
            hasStoredElevenLabsAPIKey = settings.elevenLabsAPIKey != nil
            hasStoredElevenLabsRealtimeAPIKey = settings.elevenLabsRealtimeAPIKey != nil
            hasStoredDoubaoAPIKey = settings.doubaoAPIKey != nil
            hasStoredPolishAPIKey = settings.polishAPIKey != nil

            statusMessage = "Saved to local config"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func clearDeepgramAPIKey() { runClear({ try settings.clearDeepgramAPIKey() }, label: "Deepgram") {
        deepgramAPIKey = ""; hasStoredDeepgramAPIKey = false
    }}

    func clearWhisperAPIKey() { runClear({ try settings.clearWhisperAPIKey() }, label: "Whisper") {
        whisperAPIKey = ""; hasStoredWhisperAPIKey = false
    }}

    func clearElevenLabsAPIKey() { runClear({ try settings.clearElevenLabsAPIKey() }, label: "ElevenLabs") {
        elevenLabsAPIKey = ""; hasStoredElevenLabsAPIKey = false
    }}

    func clearElevenLabsRealtimeAPIKey() { runClear({ try settings.clearElevenLabsRealtimeAPIKey() }, label: "ElevenLabs Realtime") {
        elevenLabsRealtimeAPIKey = ""; hasStoredElevenLabsRealtimeAPIKey = false
    }}

    func clearDoubaoAPIKey() { runClear({ try settings.clearDoubaoAPIKey() }, label: "Doubao") {
        doubaoAPIKey = ""; hasStoredDoubaoAPIKey = false
    }}

    func clearPolishAPIKey() { runClear({ try settings.clearPolishAPIKey() }, label: "Polish") {
        polishAPIKey = ""; hasStoredPolishAPIKey = false
    }}

    private func runClear(_ op: () throws -> Void, label: String, onSuccess: () -> Void) {
        do {
            try op()
            onSuccess()
            statusMessage = "\(label) API key cleared"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func resetToDefaults() {
        outputMode = .pasteAtCursor
        language = SettingsStore.defaultLanguage
        polishWithGPT = true
        restoreClipboard = true
        duckingLevel = SettingsStore.defaultDuckingLevel
        preferredMicrophone = SettingsStore.defaultMicrophonePreference
        transcriptionProvider = SettingsStore.defaultTranscriptionProvider

        deepgramBaseURL = SettingsStore.defaultDeepgramBaseURL
        deepgramModel = SettingsStore.defaultDeepgramModel
        deepgramLanguage = "multi"

        whisperBaseURL = SettingsStore.defaultOpenRouterBaseURL
        whisperModel = SettingsStore.defaultWhisperModel
        whisperLanguage = ""

        elevenLabsBaseURL = SettingsStore.defaultElevenLabsBaseURL
        elevenLabsModel = SettingsStore.defaultElevenLabsModel
        elevenLabsLanguage = ""

        elevenLabsRealtimeBaseURL = SettingsStore.defaultElevenLabsRealtimeBaseURL
        elevenLabsRealtimeModel = SettingsStore.defaultElevenLabsRealtimeModel
        elevenLabsRealtimeLanguage = ""

        doubaoBaseURL = SettingsStore.defaultDoubaoBaseURL
        doubaoResourceId = SettingsStore.defaultDoubaoResourceId
        doubaoLanguage = ""

        polishBaseURL = SettingsStore.defaultOpenRouterBaseURL
        polishModel = SettingsStore.defaultPolishModel

        statusMessage = "Defaults loaded; click Save"
    }

    func refreshUsage() {
        usageSummaries = usageStore.weeklySummaries()
        correctionRecords = correctionStore.getAllRecords()
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

    func clearCorrections() {
        correctionStore.clear()
        correctionRecords = []
        statusMessage = "Correction history cleared"
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

    private static func validateHTTPURL(_ rawValue: String, fieldLabel: String) throws -> URL {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil,
              !trimmed.isEmpty else {
            throw SettingsViewModelError.invalidURL(field: fieldLabel)
        }
        return url
    }

    private static func validateWebSocketURL(_ rawValue: String, fieldLabel: String) throws -> URL {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              ["ws", "wss", "http", "https"].contains(scheme),
              url.host != nil,
              !trimmed.isEmpty else {
            throw SettingsViewModelError.invalidURL(field: fieldLabel)
        }
        return url
    }
}

enum SettingsViewModelError: LocalizedError {
    case invalidURL(field: String)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let field):
            return "Enter a valid URL for \(field)."
        }
    }
}
