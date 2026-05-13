import Foundation

enum OutputMode: String, CaseIterable, Codable {
    case pasteAtCursor
    case clipboardOnly

    var title: String {
        switch self {
        case .pasteAtCursor:
            return "Paste at Cursor"
        case .clipboardOnly:
            return "Copy to Clipboard"
        }
    }
}

enum MicrophonePreference: String, CaseIterable, Codable {
    case systemDefault
    case builtIn

    var title: String {
        switch self {
        case .systemDefault:
            return "System Default"
        case .builtIn:
            return "Always Built-in Mic"
        }
    }

    var explanation: String {
        switch self {
        case .systemDefault:
            return "Uses whatever microphone macOS has selected. Bluetooth headsets will drop into call (HFP) mode while recording, which narrows their soundstage and audio quality."
        case .builtIn:
            return "Forces recording to the Mac's built-in microphone, so Bluetooth headphones stay in high-fidelity (A2DP) mode and their soundstage is preserved."
        }
    }
}

enum RecognitionLanguage: String, CaseIterable, Codable {
    case auto = "auto"
    case zhCN = "zh"
    case enUS = "en"
    case jaJP = "ja"
    case koKR = "ko"
    case esES = "es"

    var title: String {
        switch self {
        case .auto:
            return "Auto Detect"
        case .zhCN:
            return "Chinese (Mandarin)"
        case .enUS:
            return "English (US)"
        case .jaJP:
            return "Japanese"
        case .koKR:
            return "Korean"
        case .esES:
            return "Spanish"
        }
    }

    var transcriptionLanguageCode: String? {
        switch self {
        case .auto:
            return nil
        default:
            return rawValue
        }
    }

    var deepgramLanguageCode: String {
        switch self {
        case .auto:
            return "multi"
        case .zhCN:
            return "zh"
        case .enUS:
            return "en-US"
        case .jaJP:
            return "ja"
        case .koKR:
            return "ko"
        case .esES:
            return "es"
        }
    }
}

enum TranscriptionProvider: String, CaseIterable, Codable {
    case deepgram
    case openRouterWhisper

    var title: String {
        switch self {
        case .deepgram:
            return "Deepgram (streaming)"
        case .openRouterWhisper:
            return "OpenRouter Whisper (batch)"
        }
    }

    var explanation: String {
        switch self {
        case .deepgram:
            return "Streams microphone audio to Deepgram while you speak. The transcript is ready almost as soon as you release Fn."
        case .openRouterWhisper:
            return "Records the full clip locally, then uploads it to OpenRouter Whisper after you release Fn."
        }
    }
}

final class SettingsStore {
    private var configuration: Configuration
    private let fileManager: FileManager

    let configFileURL: URL

    init(fileManager: FileManager = .default, configFileURL: URL? = nil) {
        self.fileManager = fileManager
        self.configFileURL = configFileURL ?? Self.defaultConfigFileURL(fileManager: fileManager)
        Self.migrateLegacyConfigIfNeeded(to: self.configFileURL, fileManager: fileManager)
        self.configuration = (try? Self.loadConfiguration(from: self.configFileURL)) ?? Configuration()
        persistIgnoringErrors()
    }

    var apiKey: String? {
        configuration.apiKey.nilIfBlank
    }

    var outputMode: OutputMode {
        get {
            configuration.outputMode
        }
        set {
            configuration.outputMode = newValue
            persistIgnoringErrors()
        }
    }

    var language: RecognitionLanguage {
        get {
            configuration.language
        }
        set {
            configuration.language = newValue
            persistIgnoringErrors()
        }
    }

    var polishWithGPT: Bool {
        get {
            configuration.polishWithGPT
        }
        set {
            configuration.polishWithGPT = newValue
            persistIgnoringErrors()
        }
    }

    var restoreClipboard: Bool {
        get {
            configuration.restoreClipboard
        }
        set {
            configuration.restoreClipboard = newValue
            persistIgnoringErrors()
        }
    }

    var duckingLevel: Double {
        get {
            configuration.duckingLevel
        }
        set {
            configuration.duckingLevel = Self.clampDuckingLevel(newValue)
            persistIgnoringErrors()
        }
    }

    var preferredMicrophone: MicrophonePreference {
        get {
            configuration.preferredMicrophone
        }
        set {
            configuration.preferredMicrophone = newValue
            persistIgnoringErrors()
        }
    }

    var transcriptionProvider: TranscriptionProvider {
        get {
            configuration.transcriptionProvider
        }
        set {
            configuration.transcriptionProvider = newValue
            persistIgnoringErrors()
        }
    }

    var deepgramAPIKey: String? {
        configuration.deepgramAPIKey.nilIfBlank
    }

    var deepgramModel: String {
        get {
            configuration.deepgramModel.nilIfBlank ?? Self.defaultDeepgramModel
        }
        set {
            configuration.deepgramModel = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            persistIgnoringErrors()
        }
    }

    var baseURLString: String {
        get {
            configuration.baseURL.nilIfBlank.map(Self.normalizeBaseURLString) ?? Self.defaultBaseURLString
        }
        set {
            configuration.baseURL = Self.normalizeBaseURLString(newValue)
            persistIgnoringErrors()
        }
    }

    var baseURL: URL {
        URL(string: baseURLString) ?? URL(string: Self.defaultBaseURLString)!
    }

    var transcriptionModel: String {
        get {
            configuration.transcriptionModel.nilIfBlank ?? Self.defaultTranscriptionModel
        }
        set {
            configuration.transcriptionModel = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            persistIgnoringErrors()
        }
    }

    var polishModel: String {
        get {
            configuration.polishModel.nilIfBlank ?? Self.defaultPolishModel
        }
        set {
            configuration.polishModel = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            persistIgnoringErrors()
        }
    }

    func update(
        baseURLString: String,
        transcriptionModel: String,
        polishModel: String,
        outputMode: OutputMode,
        language: RecognitionLanguage,
        polishWithGPT: Bool,
        restoreClipboard: Bool,
        duckingLevel: Double,
        preferredMicrophone: MicrophonePreference,
        transcriptionProvider: TranscriptionProvider,
        deepgramModel: String,
        apiKey: String?,
        deepgramAPIKey: String?
    ) throws {
        configuration.baseURL = Self.normalizeBaseURLString(baseURLString)
        configuration.transcriptionModel = transcriptionModel.trimmingCharacters(in: .whitespacesAndNewlines)
        configuration.polishModel = polishModel.trimmingCharacters(in: .whitespacesAndNewlines)
        configuration.outputMode = outputMode
        configuration.language = language
        configuration.polishWithGPT = polishWithGPT
        configuration.restoreClipboard = restoreClipboard
        configuration.duckingLevel = Self.clampDuckingLevel(duckingLevel)
        configuration.preferredMicrophone = preferredMicrophone
        configuration.transcriptionProvider = transcriptionProvider
        configuration.deepgramModel = deepgramModel.trimmingCharacters(in: .whitespacesAndNewlines)

        if let apiKey {
            configuration.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let deepgramAPIKey {
            configuration.deepgramAPIKey = deepgramAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        try persist()
    }

    func clearAPIKey() throws {
        configuration.apiKey = ""
        try persist()
    }

    func clearDeepgramAPIKey() throws {
        configuration.deepgramAPIKey = ""
        try persist()
    }

    static let defaultBaseURLString = "https://openrouter.ai/api/v1"
    static let defaultTranscriptionModel = "openai/whisper-large-v3-turbo"
    static let defaultPolishModel = "openai/gpt-5.4-mini"
    static let defaultLanguage = RecognitionLanguage.auto
    static let defaultDuckingLevel: Double = 0.1
    static let defaultMicrophonePreference: MicrophonePreference = .systemDefault
    static let defaultTranscriptionProvider: TranscriptionProvider = .deepgram
    static let defaultDeepgramModel = "nova-3"

    fileprivate static func clampDuckingLevel(_ value: Double) -> Double {
        max(0, min(1, value))
    }

    private func persist() throws {
        let directory = configFileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        LocalFileSecurity.protectDirectory(directory, fileManager: fileManager)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(configuration)
        try data.write(to: configFileURL, options: [.atomic])
        LocalFileSecurity.protectFile(configFileURL, fileManager: fileManager)
    }

    private func persistIgnoringErrors() {
        try? persist()
    }

    private static func loadConfiguration(from url: URL) throws -> Configuration {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Configuration.self, from: data)
    }

    private static func defaultConfigFileURL(fileManager: FileManager) -> URL {
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)

        return applicationSupport
            .appendingPathComponent(AppMetadata.appSupportDirectoryName, isDirectory: true)
            .appendingPathComponent("config.json")
    }

    private static func legacyConfigFileURL(fileManager: FileManager) -> URL {
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)

        return applicationSupport
            .appendingPathComponent(AppMetadata.legacyAppSupportDirectoryName, isDirectory: true)
            .appendingPathComponent("config.json")
    }

    private static func migrateLegacyConfigIfNeeded(to configFileURL: URL, fileManager: FileManager) {
        guard !fileManager.fileExists(atPath: configFileURL.path) else {
            return
        }

        let legacyURL = legacyConfigFileURL(fileManager: fileManager)
        guard fileManager.fileExists(atPath: legacyURL.path) else {
            return
        }

        do {
            let directory = configFileURL.deletingLastPathComponent()
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            LocalFileSecurity.protectDirectory(directory, fileManager: fileManager)
            try fileManager.moveItem(at: legacyURL, to: configFileURL)
            LocalFileSecurity.protectFile(configFileURL, fileManager: fileManager)
        } catch {
            try? fileManager.copyItem(at: legacyURL, to: configFileURL)
            LocalFileSecurity.protectFile(configFileURL, fileManager: fileManager)
        }
    }

    private static func normalizeBaseURLString(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
    }

    fileprivate static func migrateLanguageCode(_ code: String) -> String {
        switch code {
        case "":
            return RecognitionLanguage.auto.rawValue
        case "zh-CN":
            return RecognitionLanguage.zhCN.rawValue
        case "en-US":
            return RecognitionLanguage.enUS.rawValue
        case "ja-JP":
            return RecognitionLanguage.jaJP.rawValue
        case "ko-KR":
            return RecognitionLanguage.koKR.rawValue
        case "es-ES":
            return RecognitionLanguage.esES.rawValue
        default:
            return code
        }
    }
}

private struct Configuration: Codable {
    var apiKey: String
    var baseURL: String
    var transcriptionModel: String
    var polishModel: String
    var outputMode: OutputMode
    var language: RecognitionLanguage
    var polishWithGPT: Bool
    var restoreClipboard: Bool
    var duckingLevel: Double
    var preferredMicrophone: MicrophonePreference
    var transcriptionProvider: TranscriptionProvider
    var deepgramAPIKey: String
    var deepgramModel: String

    init() {
        self.apiKey = ""
        self.baseURL = SettingsStore.defaultBaseURLString
        self.transcriptionModel = SettingsStore.defaultTranscriptionModel
        self.polishModel = SettingsStore.defaultPolishModel
        self.outputMode = .pasteAtCursor
        self.language = SettingsStore.defaultLanguage
        self.polishWithGPT = true
        self.restoreClipboard = true
        self.duckingLevel = SettingsStore.defaultDuckingLevel
        self.preferredMicrophone = SettingsStore.defaultMicrophonePreference
        self.transcriptionProvider = SettingsStore.defaultTranscriptionProvider
        self.deepgramAPIKey = ""
        self.deepgramModel = SettingsStore.defaultDeepgramModel
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let outputModeRaw = try container.decodeIfPresent(String.self, forKey: .outputMode) ?? ""
        let languageRaw = try container.decodeIfPresent(String.self, forKey: .language) ?? ""
        let migratedLanguageRaw = SettingsStore.migrateLanguageCode(languageRaw)

        self.apiKey = try container.decodeIfPresent(String.self, forKey: .apiKey) ?? ""
        self.baseURL = try container.decodeIfPresent(String.self, forKey: .baseURL) ?? SettingsStore.defaultBaseURLString
        self.transcriptionModel = try container.decodeIfPresent(String.self, forKey: .transcriptionModel) ?? SettingsStore.defaultTranscriptionModel
        self.polishModel = try container.decodeIfPresent(String.self, forKey: .polishModel) ?? SettingsStore.defaultPolishModel
        self.outputMode = OutputMode(rawValue: outputModeRaw) ?? .pasteAtCursor
        self.language = RecognitionLanguage(rawValue: migratedLanguageRaw) ?? SettingsStore.defaultLanguage
        self.polishWithGPT = try container.decodeIfPresent(Bool.self, forKey: .polishWithGPT) ?? true
        self.restoreClipboard = try container.decodeIfPresent(Bool.self, forKey: .restoreClipboard) ?? true
        let rawDucking = try container.decodeIfPresent(Double.self, forKey: .duckingLevel) ?? SettingsStore.defaultDuckingLevel
        self.duckingLevel = SettingsStore.clampDuckingLevel(rawDucking)
        let micRaw = try container.decodeIfPresent(String.self, forKey: .preferredMicrophone) ?? ""
        self.preferredMicrophone = MicrophonePreference(rawValue: micRaw) ?? SettingsStore.defaultMicrophonePreference

        let providerRaw = try container.decodeIfPresent(String.self, forKey: .transcriptionProvider) ?? ""
        if let provider = TranscriptionProvider(rawValue: providerRaw) {
            self.transcriptionProvider = provider
        } else {
            // Existing installs without this field stay on the OpenRouter Whisper path
            // until the user opts in to Deepgram from Settings.
            self.transcriptionProvider = .openRouterWhisper
        }
        self.deepgramAPIKey = try container.decodeIfPresent(String.self, forKey: .deepgramAPIKey) ?? ""
        self.deepgramModel = try container.decodeIfPresent(String.self, forKey: .deepgramModel) ?? SettingsStore.defaultDeepgramModel
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
