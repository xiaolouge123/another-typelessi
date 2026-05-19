import AppKit
import SwiftUI

final class PreferencesWindowController: NSWindowController {
    private let viewModel: SettingsViewModel

    init(settings: SettingsStore, usageStore: UsageStore, correctionStore: CorrectionStore) {
        let viewModel = SettingsViewModel(settings: settings, usageStore: usageStore, correctionStore: correctionStore)
        self.viewModel = viewModel

        let contentView = PreferencesView(viewModel: viewModel)
        let hostingController = NSHostingController(rootView: contentView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 720),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.contentViewController = hostingController
        window.center()
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 720, height: 640)

        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showSettings() {
        viewModel.refreshUsage()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct PreferencesView: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        VStack(spacing: 0) {
            TabView {
                TranscriptionTab(viewModel: viewModel)
                    .tabItem { Label("Transcription", systemImage: "waveform") }

                PolishTab(viewModel: viewModel)
                    .tabItem { Label("Polish", systemImage: "sparkles") }

                BehaviorTab(viewModel: viewModel)
                    .tabItem { Label("Behavior", systemImage: "slider.horizontal.3") }

                HistoryTab(viewModel: viewModel)
                    .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
            }
            .padding(16)

            Divider()

            HStack {
                Button("Reset Defaults") { viewModel.resetToDefaults() }
                Spacer()
                Text(viewModel.statusMessage)
                    .foregroundStyle(.secondary)
                    .font(.caption)
                Button("Save") { viewModel.save() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(minWidth: 720, minHeight: 640)
    }
}

// MARK: - Transcription tab

private struct TranscriptionTab: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("Active Provider", selection: $viewModel.transcriptionProvider) {
                            ForEach(TranscriptionProvider.allCases, id: \.self) { provider in
                                Text(provider.title).tag(provider)
                            }
                        }
                        Text(viewModel.transcriptionProvider.explanation)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(8)
                }

                ProviderConfigCard(
                    title: "Deepgram",
                    mode: TranscriptionProvider.deepgram.mode,
                    isActive: viewModel.transcriptionProvider == .deepgram,
                    apiKey: $viewModel.deepgramAPIKey,
                    hasStoredKey: viewModel.hasStoredDeepgramAPIKey,
                    onClearKey: { viewModel.clearDeepgramAPIKey() },
                    baseURL: $viewModel.deepgramBaseURL,
                    baseURLPlaceholder: SettingsStore.defaultDeepgramBaseURL,
                    model: $viewModel.deepgramModel,
                    modelPlaceholder: SettingsStore.defaultDeepgramModel,
                    language: $viewModel.deepgramLanguage,
                    languagePlaceholder: "multi",
                    note: "WebSocket endpoint (wss://). Use 'multi' for auto-detect or a code like 'zh', 'en'."
                )

                ProviderConfigCard(
                    title: "OpenRouter Whisper",
                    mode: TranscriptionProvider.openRouterWhisper.mode,
                    isActive: viewModel.transcriptionProvider == .openRouterWhisper,
                    apiKey: $viewModel.whisperAPIKey,
                    hasStoredKey: viewModel.hasStoredWhisperAPIKey,
                    onClearKey: { viewModel.clearWhisperAPIKey() },
                    baseURL: $viewModel.whisperBaseURL,
                    baseURLPlaceholder: SettingsStore.defaultOpenRouterBaseURL,
                    model: $viewModel.whisperModel,
                    modelPlaceholder: SettingsStore.defaultWhisperModel,
                    language: $viewModel.whisperLanguage,
                    languagePlaceholder: "auto",
                    note: "Uploads the full WAV after recording. Leave language empty to auto-detect."
                )

                ProviderConfigCard(
                    title: "ElevenLabs Scribe",
                    mode: TranscriptionProvider.elevenLabs.mode,
                    isActive: viewModel.transcriptionProvider == .elevenLabs,
                    apiKey: $viewModel.elevenLabsAPIKey,
                    hasStoredKey: viewModel.hasStoredElevenLabsAPIKey,
                    onClearKey: { viewModel.clearElevenLabsAPIKey() },
                    baseURL: $viewModel.elevenLabsBaseURL,
                    baseURLPlaceholder: SettingsStore.defaultElevenLabsBaseURL,
                    model: $viewModel.elevenLabsModel,
                    modelPlaceholder: SettingsStore.defaultElevenLabsModel,
                    language: $viewModel.elevenLabsLanguage,
                    languagePlaceholder: "auto",
                    note: "Uploads via multipart/form-data to /v1/speech-to-text. Default model scribe_v2."
                )

                ProviderConfigCard(
                    title: "ElevenLabs Scribe Realtime",
                    mode: TranscriptionProvider.elevenLabsRealtime.mode,
                    isActive: viewModel.transcriptionProvider == .elevenLabsRealtime,
                    apiKey: $viewModel.elevenLabsRealtimeAPIKey,
                    hasStoredKey: viewModel.hasStoredElevenLabsRealtimeAPIKey,
                    onClearKey: { viewModel.clearElevenLabsRealtimeAPIKey() },
                    baseURL: $viewModel.elevenLabsRealtimeBaseURL,
                    baseURLPlaceholder: SettingsStore.defaultElevenLabsRealtimeBaseURL,
                    model: $viewModel.elevenLabsRealtimeModel,
                    modelPlaceholder: SettingsStore.defaultElevenLabsRealtimeModel,
                    language: $viewModel.elevenLabsRealtimeLanguage,
                    languagePlaceholder: "auto",
                    note: "WebSocket endpoint (wss://). Streams 16 kHz PCM with input_audio_chunk JSON envelopes. Default model scribe_v2_realtime."
                )

                DoubaoConfigCard(
                    isActive: viewModel.transcriptionProvider == .doubao,
                    apiKey: $viewModel.doubaoAPIKey,
                    hasStoredKey: viewModel.hasStoredDoubaoAPIKey,
                    onClearKey: { viewModel.clearDoubaoAPIKey() },
                    baseURL: $viewModel.doubaoBaseURL,
                    resourceId: $viewModel.doubaoResourceId,
                    language: $viewModel.doubaoLanguage
                )
            }
        }
    }
}

private struct ProviderConfigCard: View {
    let title: String
    let mode: TranscriptionMode
    let isActive: Bool
    @Binding var apiKey: String
    let hasStoredKey: Bool
    let onClearKey: () -> Void
    @Binding var baseURL: String
    let baseURLPlaceholder: String
    @Binding var model: String
    let modelPlaceholder: String
    @Binding var language: String
    let languagePlaceholder: String
    let note: String

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.headline)
                    ModeBadge(mode: mode)
                    if isActive {
                        Text("ACTIVE")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor, in: Capsule())
                    }
                    Spacer()
                }

                LabeledField("API Key") {
                    HStack(spacing: 6) {
                        SecureField("", text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                        Button("Clear") { onClearKey() }
                    }
                }

                Text(hasStoredKey ? "Stored. Leave blank to keep it." : "No key stored.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LabeledField("Base URL") {
                    TextField(baseURLPlaceholder, text: $baseURL)
                        .textFieldStyle(.roundedBorder)
                }

                LabeledField("Model") {
                    TextField(modelPlaceholder, text: $model)
                        .textFieldStyle(.roundedBorder)
                }

                LabeledField("Language") {
                    TextField(languagePlaceholder, text: $language)
                        .textFieldStyle(.roundedBorder)
                }

                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(8)
        }
    }
}

private struct ModeBadge: View {
    let mode: TranscriptionMode

    var body: some View {
        Text(mode.badge)
            .font(.caption2.weight(.bold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .overlay(
                Capsule().stroke(color, lineWidth: 1)
            )
    }

    private var color: Color {
        switch mode {
        case .streaming: return .green
        case .batch: return .orange
        }
    }
}

private struct DoubaoConfigCard: View {
    let isActive: Bool
    @Binding var apiKey: String
    let hasStoredKey: Bool
    let onClearKey: () -> Void
    @Binding var baseURL: String
    @Binding var resourceId: String
    @Binding var language: String

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text("Doubao Realtime")
                        .font(.headline)
                    ModeBadge(mode: TranscriptionProvider.doubao.mode)
                    if isActive {
                        Text("ACTIVE")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor, in: Capsule())
                    }
                    Spacer()
                }

                LabeledField("API Key") {
                    HStack(spacing: 6) {
                        SecureField("", text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                        Button("Clear") { onClearKey() }
                    }
                }

                Text(hasStoredKey ? "Stored. Leave blank to keep it." : "No key stored.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LabeledField("Base URL") {
                    TextField(SettingsStore.defaultDoubaoBaseURL, text: $baseURL)
                        .textFieldStyle(.roundedBorder)
                }

                LabeledField("Resource ID") {
                    TextField(SettingsStore.defaultDoubaoResourceId, text: $resourceId)
                        .textFieldStyle(.roundedBorder)
                }

                LabeledField("Language") {
                    TextField("auto", text: $language)
                        .textFieldStyle(.roundedBorder)
                }

                Text("WebSocket endpoint (wss://). New-console single X-Api-Key. Resource ID 选择计费包：volc.seedasr.sauc.duration = 豆包 2.0 小时版（推荐）；volc.bigasr.sauc.duration = 豆包 1.0 小时版。Language 留空 = 自动检测；填如 zh-CN / en-US / yue-CN 强制指定语种。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(8)
        }
    }
}

private struct LabeledField<Content: View>: View {
    let label: String
    @ViewBuilder let content: () -> Content

    init(_ label: String, @ViewBuilder content: @escaping () -> Content) {
        self.label = label
        self.content = content
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .frame(width: 90, alignment: .leading)
                .foregroundStyle(.secondary)
                .font(.callout)
            content()
        }
    }
}

// MARK: - Polish tab

private struct PolishTab: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Enable text formalization", isOn: $viewModel.polishWithGPT)
                            .font(.headline)

                        Text("Sends the transcript to a chat completions endpoint (e.g. OpenRouter) to clean up disfluencies, fix homophones using your correction history, and adjust phrasing.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(8)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Polish Endpoint")
                            .font(.headline)

                        LabeledField("API Key") {
                            HStack(spacing: 6) {
                                SecureField("", text: $viewModel.polishAPIKey)
                                    .textFieldStyle(.roundedBorder)
                                Button("Clear") { viewModel.clearPolishAPIKey() }
                            }
                        }

                        Text(viewModel.hasStoredPolishAPIKey ? "Stored. Leave blank to keep it." : "No key stored.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        LabeledField("Base URL") {
                            TextField(SettingsStore.defaultOpenRouterBaseURL, text: $viewModel.polishBaseURL)
                                .textFieldStyle(.roundedBorder)
                        }

                        LabeledField("Model") {
                            TextField(SettingsStore.defaultPolishModel, text: $viewModel.polishModel)
                                .textFieldStyle(.roundedBorder)
                        }

                        Text("OpenAI-compatible /chat/completions endpoint. The polish step always uses these credentials regardless of the active transcription provider.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(8)
                }
                .disabled(!viewModel.polishWithGPT)
                .opacity(viewModel.polishWithGPT ? 1.0 : 0.5)
            }
        }
    }
}

// MARK: - Behavior tab

private struct BehaviorTab: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("Output", selection: $viewModel.outputMode) {
                            ForEach(OutputMode.allCases, id: \.self) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)

                        Picker("Polish Language", selection: $viewModel.language) {
                            ForEach(RecognitionLanguage.allCases, id: \.self) { language in
                                Text(language.title).tag(language)
                            }
                        }

                        Toggle("Restore clipboard after paste", isOn: $viewModel.restoreClipboard)

                        DuckingLevelControl(level: $viewModel.duckingLevel)

                        MicrophonePreferenceControl(selection: $viewModel.preferredMicrophone)
                    }
                    .padding(8)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Storage")
                            .font(.headline)
                        Text("Config: \(viewModel.configFilePath)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .textSelection(.enabled)
                        Text("Usage: \(viewModel.usageFilePath)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .textSelection(.enabled)
                        Text("Log: \(viewModel.logFilePath)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .textSelection(.enabled)
                    }
                    .padding(8)
                }
            }
        }
    }
}

// MARK: - History tab

private struct HistoryTab: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Weekly Usage")
                                .font(.headline)
                            Spacer()
                            Button("Refresh") { viewModel.refreshUsage() }
                            Button("Clear") { viewModel.clearUsage() }
                        }

                        if viewModel.usageSummaries.isEmpty {
                            Text("No usage recorded yet.")
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 10)
                        } else {
                            ScrollView(.horizontal) {
                                VStack(alignment: .leading, spacing: 8) {
                                    UsageHeaderRow()
                                    Divider()
                                    ForEach(viewModel.usageSummaries) { summary in
                                        UsageSummaryRow(summary: summary)
                                        Divider()
                                    }
                                }
                            }
                        }
                    }
                    .padding(8)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Corrections (\(viewModel.correctionRecords.count))")
                                .font(.headline)
                            Spacer()
                            Button("Refresh") { viewModel.refreshUsage() }
                            Button("Clear") { viewModel.clearCorrections() }
                        }

                        Text("Edits the app detected in your editor within 30s of paste. These feed the polish step.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        if viewModel.correctionRecords.isEmpty {
                            Text("No corrections recorded yet.")
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 10)
                        } else {
                            ScrollView {
                                VStack(alignment: .leading, spacing: 8) {
                                    ForEach(viewModel.correctionRecords.reversed()) { record in
                                        CorrectionRecordRow(record: record)
                                        Divider()
                                    }
                                }
                            }
                            .frame(maxHeight: 240)
                        }
                    }
                    .padding(8)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Dictation Log")
                                .font(.headline)
                            Spacer()
                            Button("Reveal") { viewModel.revealDictationLog() }
                            Button("Clear") { viewModel.clearDictationLog() }
                        }

                        Text("Stored at \(viewModel.logFilePath)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .textSelection(.enabled)
                    }
                    .padding(8)
                }
            }
        }
    }
}

// MARK: - Shared controls

private struct MicrophonePreferenceControl: View {
    @Binding var selection: MicrophonePreference

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Picker("Microphone", selection: $selection) {
                ForEach(MicrophonePreference.allCases, id: \.self) { preference in
                    Text(preference.title).tag(preference)
                }
            }
            .pickerStyle(.segmented)

            Text(selection.explanation)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct DuckingLevelControl: View {
    @Binding var level: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Duck other audio while recording")
                Spacer()
                Text(percentText)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Slider(value: $level, in: 0...1, step: 0.05)

            Text("0% silences other audio; 100% keeps it unchanged. Defaults to 10%.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var percentText: String {
        let clamped = max(0, min(1, level))
        return "\(Int((clamped * 100).rounded()))%"
    }
}

private struct UsageHeaderRow: View {
    var body: some View {
        HStack(spacing: 8) {
            header("Week", width: 96)
            header("Stage", width: 78)
            header("Provider", width: 84)
            header("Model", width: 180)
            header("Calls", width: 54)
            header("Input", width: 70)
            header("Output", width: 70)
            header("Audio", width: 80)
            header("Total", width: 70)
            header("Avg Time", width: 80)
            header("Cost", width: 96)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
    }

    private func header(_ text: String, width: CGFloat) -> some View {
        Text(text)
            .frame(width: width, alignment: .leading)
    }
}

private struct UsageSummaryRow: View {
    let summary: WeeklyModelUsage

    var body: some View {
        HStack(spacing: 8) {
            Text(summary.weekLabel).frame(width: 96, alignment: .leading)
            Text(summary.operationText).frame(width: 78, alignment: .leading)
            Text(summary.providerText).frame(width: 84, alignment: .leading)
            Text(summary.model).frame(width: 180, alignment: .leading).lineLimit(1)
            Text(summary.callsText).frame(width: 54, alignment: .leading)
            Text(summary.promptTokensText).frame(width: 70, alignment: .leading)
            Text(summary.completionTokensText).frame(width: 70, alignment: .leading)
            Text(summary.audioText).frame(width: 80, alignment: .leading)
            Text(summary.totalTokensText).frame(width: 70, alignment: .leading)
            Text(summary.averageElapsedText).frame(width: 80, alignment: .leading)
            Text(summary.costText).frame(width: 96, alignment: .leading)
        }
        .font(.system(size: 12))
        .foregroundStyle(.primary)
    }
}

private struct CorrectionRecordRow: View {
    let record: CorrectionRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(formatDate(record.timestamp))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Similarity: \(String(format: "%.0f%%", record.similarity * 100))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("ASR")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(record.asrOutput)
                        .font(.system(size: 11))
                        .foregroundStyle(.red.opacity(0.85))
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "arrow.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 4) {
                    Text("User")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(record.userCorrected)
                        .font(.system(size: 11))
                        .foregroundStyle(.green.opacity(0.85))
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 4)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
