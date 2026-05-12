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
                GroupBox("OpenRouter") {
                    VStack(alignment: .leading, spacing: 12) {
                        SecureField("API Key", text: $viewModel.apiKey)
                            .textFieldStyle(.roundedBorder)

                    HStack {
                        Text(viewModel.hasStoredAPIKey ? "API key stored in local config. Leave blank to keep it." : "No API key stored.")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Clear API Key") {
                            viewModel.clearAPIKey()
                        }
                    }

                    Text("Config file: \(viewModel.configFilePath)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .textSelection(.enabled)

                    TextField("Base URL", text: $viewModel.baseURL)
                        .textFieldStyle(.roundedBorder)

                    TextField("Transcription model", text: $viewModel.transcriptionModel)
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

                        Toggle("Clean filler words locally", isOn: $viewModel.cleanFillers)
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
            header("Model", width: 220)
            header("Calls", width: 54)
            header("Input", width: 76)
            header("Output", width: 76)
            header("Audio", width: 76)
            header("Total", width: 76)
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

            Text(summary.model)
                .frame(width: 220, alignment: .leading)
                .lineLimit(1)

            Text(summary.callsText)
                .frame(width: 54, alignment: .leading)

            Text(summary.promptTokensText)
                .frame(width: 76, alignment: .leading)

            Text(summary.completionTokensText)
                .frame(width: 76, alignment: .leading)

            Text(summary.audioTokensText)
                .frame(width: 76, alignment: .leading)

            Text(summary.totalTokensText)
                .frame(width: 76, alignment: .leading)

            Text(summary.costText)
                .frame(width: 96, alignment: .leading)
        }
        .font(.system(size: 12))
        .foregroundStyle(.primary)
    }
}
