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

enum TranscriptionMode: String, Codable {
    case streaming
    case batch

    var badge: String {
        switch self {
        case .streaming: return "STREAMING"
        case .batch: return "BATCH"
        }
    }
}

enum TranscriptionProvider: String, CaseIterable, Codable {
    case deepgram
    case openRouterWhisper
    case elevenLabs
    case elevenLabsRealtime
    case doubao

    var title: String {
        switch self {
        case .deepgram:
            return "Deepgram"
        case .openRouterWhisper:
            return "OpenRouter Whisper"
        case .elevenLabs:
            return "ElevenLabs Scribe"
        case .elevenLabsRealtime:
            return "ElevenLabs Scribe Realtime"
        case .doubao:
            return "Doubao Realtime"
        }
    }

    var mode: TranscriptionMode {
        switch self {
        case .deepgram, .elevenLabsRealtime, .doubao:
            return .streaming
        case .openRouterWhisper, .elevenLabs:
            return .batch
        }
    }

    var explanation: String {
        switch self {
        case .deepgram:
            return "Streams microphone audio to Deepgram while you speak. The transcript is ready almost as soon as you release Fn."
        case .openRouterWhisper:
            return "Records the full clip locally, then uploads it to OpenRouter Whisper after you release Fn."
        case .elevenLabs:
            return "Records the full clip locally, then uploads it to ElevenLabs Scribe (multipart upload) after you release Fn."
        case .elevenLabsRealtime:
            return "Streams microphone audio to ElevenLabs Scribe v2 Realtime while you speak (WebSocket, ~150ms latency)."
        case .doubao:
            return "Streams microphone audio to Doubao (Volcengine SAUC bigmodel_async) over WebSocket. New-console X-Api-Key authentication."
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
        configuration.polishAPIKey.nilIfBlank ?? configuration.apiKey.nilIfBlank
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

    var deepgramBaseURL: String {
        get {
            configuration.deepgramBaseURL.nilIfBlank ?? Self.defaultDeepgramBaseURL
        }
        set {
            configuration.deepgramBaseURL = Self.normalizeBaseURLString(newValue)
            persistIgnoringErrors()
        }
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

    var deepgramLanguage: String {
        get {
            configuration.deepgramLanguage
        }
        set {
            configuration.deepgramLanguage = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            persistIgnoringErrors()
        }
    }

    // OpenRouter Whisper

    var whisperAPIKey: String? {
        configuration.whisperAPIKey.nilIfBlank
    }

    var whisperBaseURLString: String {
        get {
            configuration.whisperBaseURL.nilIfBlank.map(Self.normalizeBaseURLString) ?? Self.defaultOpenRouterBaseURL
        }
        set {
            configuration.whisperBaseURL = Self.normalizeBaseURLString(newValue)
            persistIgnoringErrors()
        }
    }

    var whisperBaseURL: URL {
        URL(string: whisperBaseURLString) ?? URL(string: Self.defaultOpenRouterBaseURL)!
    }

    var whisperModel: String {
        get {
            configuration.whisperModel.nilIfBlank ?? Self.defaultWhisperModel
        }
        set {
            configuration.whisperModel = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            persistIgnoringErrors()
        }
    }

    var whisperLanguage: String {
        get {
            configuration.whisperLanguage
        }
        set {
            configuration.whisperLanguage = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            persistIgnoringErrors()
        }
    }

    // ElevenLabs

    var elevenLabsAPIKey: String? {
        configuration.elevenLabsAPIKey.nilIfBlank
    }

    var elevenLabsBaseURLString: String {
        get {
            configuration.elevenLabsBaseURL.nilIfBlank.map(Self.normalizeBaseURLString) ?? Self.defaultElevenLabsBaseURL
        }
        set {
            configuration.elevenLabsBaseURL = Self.normalizeBaseURLString(newValue)
            persistIgnoringErrors()
        }
    }

    var elevenLabsBaseURL: URL {
        URL(string: elevenLabsBaseURLString) ?? URL(string: Self.defaultElevenLabsBaseURL)!
    }

    var elevenLabsModel: String {
        get {
            configuration.elevenLabsModel.nilIfBlank ?? Self.defaultElevenLabsModel
        }
        set {
            configuration.elevenLabsModel = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            persistIgnoringErrors()
        }
    }

    var elevenLabsLanguage: String {
        get {
            configuration.elevenLabsLanguage
        }
        set {
            configuration.elevenLabsLanguage = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            persistIgnoringErrors()
        }
    }

    // ElevenLabs Realtime

    var elevenLabsRealtimeAPIKey: String? {
        configuration.elevenLabsRealtimeAPIKey.nilIfBlank
    }

    var elevenLabsRealtimeBaseURL: String {
        get {
            configuration.elevenLabsRealtimeBaseURL.nilIfBlank ?? Self.defaultElevenLabsRealtimeBaseURL
        }
        set {
            configuration.elevenLabsRealtimeBaseURL = Self.normalizeBaseURLString(newValue)
            persistIgnoringErrors()
        }
    }

    var elevenLabsRealtimeModel: String {
        get {
            configuration.elevenLabsRealtimeModel.nilIfBlank ?? Self.defaultElevenLabsRealtimeModel
        }
        set {
            configuration.elevenLabsRealtimeModel = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            persistIgnoringErrors()
        }
    }

    var elevenLabsRealtimeLanguage: String {
        get {
            configuration.elevenLabsRealtimeLanguage
        }
        set {
            configuration.elevenLabsRealtimeLanguage = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            persistIgnoringErrors()
        }
    }

    // Doubao (Volcengine SAUC, streaming, wss://)

    var doubaoAPIKey: String? {
        configuration.doubaoAPIKey.nilIfBlank
    }

    var doubaoBaseURL: String {
        get {
            configuration.doubaoBaseURL.nilIfBlank ?? Self.defaultDoubaoBaseURL
        }
        set {
            configuration.doubaoBaseURL = Self.normalizeBaseURLString(newValue)
            persistIgnoringErrors()
        }
    }

    var doubaoResourceId: String {
        get {
            configuration.doubaoResourceId.nilIfBlank ?? Self.defaultDoubaoResourceId
        }
        set {
            configuration.doubaoResourceId = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            persistIgnoringErrors()
        }
    }

    var doubaoLanguage: String {
        get {
            configuration.doubaoLanguage
        }
        set {
            configuration.doubaoLanguage = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            persistIgnoringErrors()
        }
    }

    // Polish

    var polishAPIKey: String? {
        configuration.polishAPIKey.nilIfBlank ?? configuration.apiKey.nilIfBlank
    }

    var polishBaseURLString: String {
        get {
            (configuration.polishBaseURL.nilIfBlank ?? configuration.baseURL.nilIfBlank)
                .map(Self.normalizeBaseURLString) ?? Self.defaultOpenRouterBaseURL
        }
        set {
            configuration.polishBaseURL = Self.normalizeBaseURLString(newValue)
            persistIgnoringErrors()
        }
    }

    var polishBaseURL: URL {
        URL(string: polishBaseURLString) ?? URL(string: Self.defaultOpenRouterBaseURL)!
    }

    var polishModel: String {
        get {
            configuration.polishModelName.nilIfBlank ?? configuration.polishModel.nilIfBlank ?? Self.defaultPolishModel
        }
        set {
            configuration.polishModelName = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            persistIgnoringErrors()
        }
    }

    struct UpdatePayload {
        var outputMode: OutputMode
        var language: RecognitionLanguage
        var polishWithGPT: Bool
        var restoreClipboard: Bool
        var duckingLevel: Double
        var preferredMicrophone: MicrophonePreference
        var transcriptionProvider: TranscriptionProvider

        // Per-provider editable fields (nil API keys mean "leave as stored").
        var deepgramAPIKey: String?
        var deepgramBaseURL: String
        var deepgramModel: String
        var deepgramLanguage: String

        var whisperAPIKey: String?
        var whisperBaseURL: String
        var whisperModel: String
        var whisperLanguage: String

        var elevenLabsAPIKey: String?
        var elevenLabsBaseURL: String
        var elevenLabsModel: String
        var elevenLabsLanguage: String

        var elevenLabsRealtimeAPIKey: String?
        var elevenLabsRealtimeBaseURL: String
        var elevenLabsRealtimeModel: String
        var elevenLabsRealtimeLanguage: String

        var doubaoAPIKey: String?
        var doubaoBaseURL: String
        var doubaoResourceId: String
        var doubaoLanguage: String

        var polishAPIKey: String?
        var polishBaseURL: String
        var polishModel: String
    }

    func update(_ payload: UpdatePayload) throws {
        configuration.outputMode = payload.outputMode
        configuration.language = payload.language
        configuration.polishWithGPT = payload.polishWithGPT
        configuration.restoreClipboard = payload.restoreClipboard
        configuration.duckingLevel = Self.clampDuckingLevel(payload.duckingLevel)
        configuration.preferredMicrophone = payload.preferredMicrophone
        configuration.transcriptionProvider = payload.transcriptionProvider

        configuration.deepgramBaseURL = Self.normalizeBaseURLString(payload.deepgramBaseURL)
        configuration.deepgramModel = payload.deepgramModel.trimmingCharacters(in: .whitespacesAndNewlines)
        configuration.deepgramLanguage = payload.deepgramLanguage.trimmingCharacters(in: .whitespacesAndNewlines)
        if let key = payload.deepgramAPIKey {
            configuration.deepgramAPIKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        configuration.whisperBaseURL = Self.normalizeBaseURLString(payload.whisperBaseURL)
        configuration.whisperModel = payload.whisperModel.trimmingCharacters(in: .whitespacesAndNewlines)
        configuration.whisperLanguage = payload.whisperLanguage.trimmingCharacters(in: .whitespacesAndNewlines)
        if let key = payload.whisperAPIKey {
            configuration.whisperAPIKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        configuration.elevenLabsBaseURL = Self.normalizeBaseURLString(payload.elevenLabsBaseURL)
        configuration.elevenLabsModel = payload.elevenLabsModel.trimmingCharacters(in: .whitespacesAndNewlines)
        configuration.elevenLabsLanguage = payload.elevenLabsLanguage.trimmingCharacters(in: .whitespacesAndNewlines)
        if let key = payload.elevenLabsAPIKey {
            configuration.elevenLabsAPIKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        configuration.elevenLabsRealtimeBaseURL = Self.normalizeBaseURLString(payload.elevenLabsRealtimeBaseURL)
        configuration.elevenLabsRealtimeModel = payload.elevenLabsRealtimeModel.trimmingCharacters(in: .whitespacesAndNewlines)
        configuration.elevenLabsRealtimeLanguage = payload.elevenLabsRealtimeLanguage.trimmingCharacters(in: .whitespacesAndNewlines)
        if let key = payload.elevenLabsRealtimeAPIKey {
            configuration.elevenLabsRealtimeAPIKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        configuration.doubaoBaseURL = Self.normalizeBaseURLString(payload.doubaoBaseURL)
        configuration.doubaoResourceId = payload.doubaoResourceId.trimmingCharacters(in: .whitespacesAndNewlines)
        configuration.doubaoLanguage = payload.doubaoLanguage.trimmingCharacters(in: .whitespacesAndNewlines)
        if let key = payload.doubaoAPIKey {
            configuration.doubaoAPIKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        configuration.polishBaseURL = Self.normalizeBaseURLString(payload.polishBaseURL)
        configuration.polishModelName = payload.polishModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if let key = payload.polishAPIKey {
            configuration.polishAPIKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        try persist()
    }

    func clearWhisperAPIKey() throws {
        configuration.whisperAPIKey = ""
        try persist()
    }

    func clearDeepgramAPIKey() throws {
        configuration.deepgramAPIKey = ""
        try persist()
    }

    func clearElevenLabsAPIKey() throws {
        configuration.elevenLabsAPIKey = ""
        try persist()
    }

    func clearElevenLabsRealtimeAPIKey() throws {
        configuration.elevenLabsRealtimeAPIKey = ""
        try persist()
    }

    func clearDoubaoAPIKey() throws {
        configuration.doubaoAPIKey = ""
        try persist()
    }

    func clearPolishAPIKey() throws {
        configuration.polishAPIKey = ""
        try persist()
    }

    static let defaultOpenRouterBaseURL = "https://openrouter.ai/api/v1"
    static let defaultDeepgramBaseURL = "wss://api.deepgram.com/v1/listen"
    static let defaultElevenLabsBaseURL = "https://api.elevenlabs.io"
    static let defaultElevenLabsRealtimeBaseURL = "wss://api.elevenlabs.io/v1/speech-to-text/realtime"
    static let defaultDoubaoBaseURL = "wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_async"
    static let defaultDoubaoResourceId = "volc.seedasr.sauc.duration"
    static let defaultWhisperModel = "openai/whisper-large-v3-turbo"
    static let defaultPolishModel = "openai/gpt-5.4-mini"
    static let defaultElevenLabsModel = "scribe_v2"
    static let defaultElevenLabsRealtimeModel = "scribe_v2_realtime"
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
    // Legacy combined fields (still persisted for backward read; new code routes through *_API_KEY etc.).
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

    // Deepgram (streaming)
    var deepgramAPIKey: String
    var deepgramBaseURL: String
    var deepgramModel: String
    var deepgramLanguage: String

    // OpenRouter Whisper (batch)
    var whisperAPIKey: String
    var whisperBaseURL: String
    var whisperModel: String
    var whisperLanguage: String

    // ElevenLabs Scribe (batch)
    var elevenLabsAPIKey: String
    var elevenLabsBaseURL: String
    var elevenLabsModel: String
    var elevenLabsLanguage: String

    // ElevenLabs Scribe v2 Realtime (streaming, wss://)
    var elevenLabsRealtimeAPIKey: String
    var elevenLabsRealtimeBaseURL: String
    var elevenLabsRealtimeModel: String
    var elevenLabsRealtimeLanguage: String

    // Doubao (Volcengine SAUC, streaming, wss://)
    var doubaoAPIKey: String
    var doubaoBaseURL: String
    var doubaoResourceId: String
    var doubaoLanguage: String

    // Polish (text formalization, separate from any STT provider)
    var polishAPIKey: String
    var polishBaseURL: String
    var polishModelName: String

    init() {
        self.apiKey = ""
        self.baseURL = SettingsStore.defaultOpenRouterBaseURL
        self.transcriptionModel = SettingsStore.defaultWhisperModel
        self.polishModel = SettingsStore.defaultPolishModel

        self.outputMode = .pasteAtCursor
        self.language = SettingsStore.defaultLanguage
        self.polishWithGPT = true
        self.restoreClipboard = true
        self.duckingLevel = SettingsStore.defaultDuckingLevel
        self.preferredMicrophone = SettingsStore.defaultMicrophonePreference
        self.transcriptionProvider = SettingsStore.defaultTranscriptionProvider

        self.deepgramAPIKey = ""
        self.deepgramBaseURL = SettingsStore.defaultDeepgramBaseURL
        self.deepgramModel = SettingsStore.defaultDeepgramModel
        self.deepgramLanguage = "multi"

        self.whisperAPIKey = ""
        self.whisperBaseURL = SettingsStore.defaultOpenRouterBaseURL
        self.whisperModel = SettingsStore.defaultWhisperModel
        self.whisperLanguage = ""

        self.elevenLabsAPIKey = ""
        self.elevenLabsBaseURL = SettingsStore.defaultElevenLabsBaseURL
        self.elevenLabsModel = SettingsStore.defaultElevenLabsModel
        self.elevenLabsLanguage = ""

        self.elevenLabsRealtimeAPIKey = ""
        self.elevenLabsRealtimeBaseURL = SettingsStore.defaultElevenLabsRealtimeBaseURL
        self.elevenLabsRealtimeModel = SettingsStore.defaultElevenLabsRealtimeModel
        self.elevenLabsRealtimeLanguage = ""

        self.doubaoAPIKey = ""
        self.doubaoBaseURL = SettingsStore.defaultDoubaoBaseURL
        self.doubaoResourceId = SettingsStore.defaultDoubaoResourceId
        self.doubaoLanguage = ""

        self.polishAPIKey = ""
        self.polishBaseURL = SettingsStore.defaultOpenRouterBaseURL
        self.polishModelName = SettingsStore.defaultPolishModel
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let outputModeRaw = try container.decodeIfPresent(String.self, forKey: .outputMode) ?? ""
        let languageRaw = try container.decodeIfPresent(String.self, forKey: .language) ?? ""
        let migratedLanguageRaw = SettingsStore.migrateLanguageCode(languageRaw)

        let legacyAPIKey = try container.decodeIfPresent(String.self, forKey: .apiKey) ?? ""
        let legacyBaseURL = try container.decodeIfPresent(String.self, forKey: .baseURL) ?? SettingsStore.defaultOpenRouterBaseURL
        let legacyTranscriptionModel = try container.decodeIfPresent(String.self, forKey: .transcriptionModel) ?? SettingsStore.defaultWhisperModel
        let legacyPolishModel = try container.decodeIfPresent(String.self, forKey: .polishModel) ?? SettingsStore.defaultPolishModel

        self.apiKey = legacyAPIKey
        self.baseURL = legacyBaseURL
        self.transcriptionModel = legacyTranscriptionModel
        self.polishModel = legacyPolishModel

        self.outputMode = OutputMode(rawValue: outputModeRaw) ?? .pasteAtCursor
        self.language = RecognitionLanguage(rawValue: migratedLanguageRaw) ?? SettingsStore.defaultLanguage
        self.polishWithGPT = try container.decodeIfPresent(Bool.self, forKey: .polishWithGPT) ?? true
        self.restoreClipboard = try container.decodeIfPresent(Bool.self, forKey: .restoreClipboard) ?? true
        let rawDucking = try container.decodeIfPresent(Double.self, forKey: .duckingLevel) ?? SettingsStore.defaultDuckingLevel
        self.duckingLevel = SettingsStore.clampDuckingLevel(rawDucking)
        let micRaw = try container.decodeIfPresent(String.self, forKey: .preferredMicrophone) ?? ""
        self.preferredMicrophone = MicrophonePreference(rawValue: micRaw) ?? SettingsStore.defaultMicrophonePreference

        let providerRaw = try container.decodeIfPresent(String.self, forKey: .transcriptionProvider) ?? ""
        self.transcriptionProvider = TranscriptionProvider(rawValue: providerRaw) ?? .openRouterWhisper

        // Deepgram
        self.deepgramAPIKey = try container.decodeIfPresent(String.self, forKey: .deepgramAPIKey) ?? ""
        self.deepgramBaseURL = try container.decodeIfPresent(String.self, forKey: .deepgramBaseURL) ?? SettingsStore.defaultDeepgramBaseURL
        self.deepgramModel = try container.decodeIfPresent(String.self, forKey: .deepgramModel) ?? SettingsStore.defaultDeepgramModel
        self.deepgramLanguage = try container.decodeIfPresent(String.self, forKey: .deepgramLanguage) ?? "multi"

        // Whisper — fall back to legacy apiKey/baseURL/transcriptionModel for upgrades.
        self.whisperAPIKey = (try container.decodeIfPresent(String.self, forKey: .whisperAPIKey)) ?? legacyAPIKey
        self.whisperBaseURL = (try container.decodeIfPresent(String.self, forKey: .whisperBaseURL)) ?? legacyBaseURL
        self.whisperModel = (try container.decodeIfPresent(String.self, forKey: .whisperModel)) ?? legacyTranscriptionModel
        self.whisperLanguage = try container.decodeIfPresent(String.self, forKey: .whisperLanguage) ?? ""

        // ElevenLabs (always defaults; new install)
        self.elevenLabsAPIKey = try container.decodeIfPresent(String.self, forKey: .elevenLabsAPIKey) ?? ""
        self.elevenLabsBaseURL = try container.decodeIfPresent(String.self, forKey: .elevenLabsBaseURL) ?? SettingsStore.defaultElevenLabsBaseURL
        self.elevenLabsModel = try container.decodeIfPresent(String.self, forKey: .elevenLabsModel) ?? SettingsStore.defaultElevenLabsModel
        self.elevenLabsLanguage = try container.decodeIfPresent(String.self, forKey: .elevenLabsLanguage) ?? ""

        // ElevenLabs Realtime — share key/language with batch ElevenLabs by default for convenience.
        let elevenLabsKeyForFallback = try container.decodeIfPresent(String.self, forKey: .elevenLabsAPIKey) ?? ""
        self.elevenLabsRealtimeAPIKey = (try container.decodeIfPresent(String.self, forKey: .elevenLabsRealtimeAPIKey)) ?? elevenLabsKeyForFallback
        self.elevenLabsRealtimeBaseURL = try container.decodeIfPresent(String.self, forKey: .elevenLabsRealtimeBaseURL) ?? SettingsStore.defaultElevenLabsRealtimeBaseURL
        self.elevenLabsRealtimeModel = try container.decodeIfPresent(String.self, forKey: .elevenLabsRealtimeModel) ?? SettingsStore.defaultElevenLabsRealtimeModel
        self.elevenLabsRealtimeLanguage = try container.decodeIfPresent(String.self, forKey: .elevenLabsRealtimeLanguage) ?? ""

        // Doubao (Volcengine SAUC)
        self.doubaoAPIKey = try container.decodeIfPresent(String.self, forKey: .doubaoAPIKey) ?? ""
        self.doubaoBaseURL = try container.decodeIfPresent(String.self, forKey: .doubaoBaseURL) ?? SettingsStore.defaultDoubaoBaseURL
        self.doubaoResourceId = try container.decodeIfPresent(String.self, forKey: .doubaoResourceId) ?? SettingsStore.defaultDoubaoResourceId
        self.doubaoLanguage = try container.decodeIfPresent(String.self, forKey: .doubaoLanguage) ?? ""

        // Polish — fall back to legacy fields too.
        self.polishAPIKey = (try container.decodeIfPresent(String.self, forKey: .polishAPIKey)) ?? legacyAPIKey
        self.polishBaseURL = (try container.decodeIfPresent(String.self, forKey: .polishBaseURL)) ?? legacyBaseURL
        self.polishModelName = (try container.decodeIfPresent(String.self, forKey: .polishModelName)) ?? legacyPolishModel
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
