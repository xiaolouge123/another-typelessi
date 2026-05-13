import AppKit
import SwiftUI

final class PreferencesWindowController: NSWindowController {
    private let viewModel: SettingsViewModel

    init(settings: SettingsStore, usageStore: UsageStore) {
        let viewModel = SettingsViewModel(settings: settings, usageStore: usageStore)
        self.viewModel = viewModel

        let contentView = PreferencesView(viewModel: viewModel)
        let hostingController = NSHostingController(rootView: contentView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 920, height: 760),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.contentViewController = hostingController
        window.center()
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 820, height: 720)

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
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                GroupBox("Transcription") {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("Provider", selection: $viewModel.transcriptionProvider) {
                            ForEach(TranscriptionProvider.allCases, id: \.self) { provider in
                                Text(provider.title).tag(provider)
                            }
                        }
                        .pickerStyle(.segmented)

                        Text(viewModel.transcriptionProvider.explanation)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        switch viewModel.transcriptionProvider {
                        case .deepgram:
                            DeepgramSettingsSection(viewModel: viewModel)
                        case .openRouterWhisper:
                            WhisperSettingsSection(viewModel: viewModel)
                        }
                    }
                    .padding(.top, 4)
                }

                GroupBox("OpenRouter (GPT polish)") {
                    VStack(alignment: .leading, spacing: 12) {
                        SecureField("OpenRouter API Key", text: $viewModel.apiKey)
                            .textFieldStyle(.roundedBorder)

                        HStack {
                            Text(viewModel.hasStoredAPIKey ? "OpenRouter API key stored. Leave blank to keep it." : "No OpenRouter API key stored.")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Clear OpenRouter Key") {
                                viewModel.clearAPIKey()
                            }
                        }

                        Text("Config file: \(viewModel.configFilePath)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .textSelection(.enabled)

                        TextField("OpenRouter base URL", text: $viewModel.baseURL)
                            .textFieldStyle(.roundedBorder)

                        TextField("Formalization model", text: $viewModel.polishModel)
                            .textFieldStyle(.roundedBorder)
                    }
                    .padding(.top, 4)
                }

                GroupBox("Behavior") {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("Output", selection: $viewModel.outputMode) {
                            ForEach(OutputMode.allCases, id: \.self) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)

                        Picker("Language", selection: $viewModel.language) {
                            ForEach(RecognitionLanguage.allCases, id: \.self) { language in
                                Text(language.title).tag(language)
                            }
                        }

                        Toggle("Formalize with GPT-5.4 Mini", isOn: $viewModel.polishWithGPT)
                        Toggle("Restore clipboard after paste", isOn: $viewModel.restoreClipboard)

                        DuckingLevelControl(level: $viewModel.duckingLevel)

                        MicrophonePreferenceControl(selection: $viewModel.preferredMicrophone)
                    }
                    .padding(.top, 4)
                }

                GroupBox("Usage Analysis") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("Stored at: \(viewModel.usageFilePath)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .textSelection(.enabled)
                            Spacer()
                            Button("Refresh") {
                                viewModel.refreshUsage()
                            }
                            Button("Clear") {
                                viewModel.clearUsage()
                            }
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
                    .padding(.top, 4)
                }

                GroupBox("Dictation Log") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Logs each session's transcript, cleaned text, and polished output for inspection. No audio is stored.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(alignment: .firstTextBaseline) {
                            Text("Stored at: \(viewModel.logFilePath)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .textSelection(.enabled)
                            Spacer()
                            Button("Reveal") {
                                viewModel.revealDictationLog()
                            }
                            Button("Clear Log") {
                                viewModel.clearDictationLog()
                            }
                        }
                    }
                    .padding(.top, 4)
                }

                HStack {
                    Button("Reset Defaults") {
                        viewModel.resetToDefaults()
                    }

                    Spacer()

                    Text(viewModel.statusMessage)
                        .foregroundStyle(.secondary)

                    Button("Save") {
                        viewModel.save()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
            .frame(width: 920, alignment: .topLeading)
        }
        .frame(width: 920, height: 760)
    }
}

private struct DeepgramSettingsSection: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SecureField("Deepgram API Key", text: $viewModel.deepgramAPIKey)
                .textFieldStyle(.roundedBorder)

            HStack {
                Text(viewModel.hasStoredDeepgramAPIKey
                     ? "Deepgram API key stored. Leave blank to keep it."
                     : "No Deepgram API key stored.")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Clear Deepgram Key") {
                    viewModel.clearDeepgramAPIKey()
                }
            }

            TextField("Deepgram model", text: $viewModel.deepgramModel)
                .textFieldStyle(.roundedBorder)

            Text("Defaults to nova-3. Audio streams to Deepgram at 16 kHz mono. Billed by Deepgram per audio minute.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct WhisperSettingsSection: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Whisper transcription model", text: $viewModel.transcriptionModel)
                .textFieldStyle(.roundedBorder)

            Text("Audio is uploaded to OpenRouter as a single WAV after you release Fn. Uses the OpenRouter API key and base URL configured below.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

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
            Text(summary.weekLabel)
                .frame(width: 96, alignment: .leading)

            Text(summary.operationText)
                .frame(width: 78, alignment: .leading)

            Text(summary.providerText)
                .frame(width: 84, alignment: .leading)

            Text(summary.model)
                .frame(width: 180, alignment: .leading)
                .lineLimit(1)

            Text(summary.callsText)
                .frame(width: 54, alignment: .leading)

            Text(summary.promptTokensText)
                .frame(width: 70, alignment: .leading)

            Text(summary.completionTokensText)
                .frame(width: 70, alignment: .leading)

            Text(summary.audioText)
                .frame(width: 80, alignment: .leading)

            Text(summary.totalTokensText)
                .frame(width: 70, alignment: .leading)

            Text(summary.averageElapsedText)
                .frame(width: 80, alignment: .leading)

            Text(summary.costText)
                .frame(width: 96, alignment: .leading)
        }
        .font(.system(size: 12))
        .foregroundStyle(.primary)
    }
}
