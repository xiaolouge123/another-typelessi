import AppKit
import Carbon.HIToolbox

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = SettingsStore()
    private let usageStore = UsageStore()
    private let audioRecorder = AudioRecorder()
    private let openRouter = OpenRouterClient()
    private let injector = TextInjector()
    private lazy var preferencesWindowController = PreferencesWindowController(
        settings: settings,
        usageStore: usageStore
    )
    private lazy var floatingStatusWindowController = FloatingStatusWindowController()
    private let cancelHotKeyCenter = HotKeyCenter(keyCode: UInt32(kVK_Escape), modifiers: 0)

    private var statusItem: NSStatusItem?
    private var hotKeyCenter: FunctionHotKeyCenter?
    private var processingTask: Task<Void, Never>?
    private var isRecording = false
    private var isArming = false
    private var isProcessing = false
    private var sessionCounter = 0
    private var activeSession = 0
    private var lastStatusReset: DispatchWorkItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureMenuBarItem()
        configureHotKey()
        configureCancelHotKey()
        rebuildMenu()
        updateStatusTitle("Fn")
    }

    func applicationWillTerminate(_ notification: Notification) {
        audioRecorder.cancel()
        processingTask?.cancel()
        floatingStatusWindowController.hide()
        hotKeyCenter?.unregister()
        cancelHotKeyCenter.unregister()
    }

    @objc private func toggleRecordingFromMenu() {
        toggleRecording()
    }

    @objc private func setOutputMode(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let mode = OutputMode(rawValue: rawValue) else {
            return
        }

        settings.outputMode = mode
        rebuildMenu()
        flashStatus(mode.title)
    }

    @objc private func setLanguage(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let language = RecognitionLanguage(rawValue: rawValue) else {
            return
        }

        settings.language = language
        rebuildMenu()
        flashStatus(language.title)
    }

    @objc private func toggleCleanFillers() {
        settings.cleanFillers.toggle()
        rebuildMenu()
        flashStatus(settings.cleanFillers ? "Cleaner On" : "Cleaner Off")
    }

    @objc private func togglePolishWithGPT() {
        settings.polishWithGPT.toggle()
        rebuildMenu()
        flashStatus(settings.polishWithGPT ? "GPT Polish On" : "GPT Polish Off")
    }

    @objc private func toggleRestoreClipboard() {
        settings.restoreClipboard.toggle()
        rebuildMenu()
        flashStatus(settings.restoreClipboard ? "Restore Clipboard" : "Keep Dictation")
    }

    @objc private func openSettings() {
        preferencesWindowController.showSettings()
    }

    @objc private func requestAccessibility() {
        let granted = injector.requestAccessibilityPermission()
        flashStatus(granted ? "Accessibility Ready" : "Grant Accessibility")
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func configureMenuBarItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.imagePosition = .imageOnly
        item.button?.imageScaling = .scaleProportionallyDown
        item.button?.toolTip = "\(AppMetadata.displayName) dictation. Press Fn to start or stop. Press Esc to cancel."
        statusItem = item
    }

    private func configureHotKey() {
        let center = FunctionHotKeyCenter()
        center.onHotKey = { [weak self] in
            self?.toggleRecording()
        }

        do {
            try center.register()
            hotKeyCenter = center
        } catch {
            flashStatus("Fn Failed")
            showAlert(title: "Fn hotkey registration failed", message: error.localizedDescription)
        }
    }

    private func configureCancelHotKey() {
        cancelHotKeyCenter.onHotKey = { [weak self] in
            self?.cancelCurrentOperation()
        }
        updateCancelHotKeyRegistration()
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        let recordingTitle: String
        if isRecording {
            recordingTitle = "Stop Recording (Fn)"
        } else if isArming {
            recordingTitle = "Cancel Pending Start"
        } else if isProcessing {
            recordingTitle = "Processing..."
        } else {
            recordingTitle = "Start Recording (Fn)"
        }

        let recordingItem = NSMenuItem(title: recordingTitle, action: #selector(toggleRecordingFromMenu), keyEquivalent: "")
        recordingItem.target = self
        recordingItem.isEnabled = !isProcessing
        menu.addItem(recordingItem)
        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        settingsItem.keyEquivalentModifierMask = [.command]
        menu.addItem(settingsItem)

        let outputMenu = NSMenu()
        addOutputMode(.pasteAtCursor, to: outputMenu)
        addOutputMode(.clipboardOnly, to: outputMenu)
        let outputItem = NSMenuItem(title: "Output", action: nil, keyEquivalent: "")
        outputItem.submenu = outputMenu
        menu.addItem(outputItem)

        let languageMenu = NSMenu()
        RecognitionLanguage.allCases.forEach { language in
            addLanguage(language, to: languageMenu)
        }
        let languageItem = NSMenuItem(title: "Transcription Language", action: nil, keyEquivalent: "")
        languageItem.submenu = languageMenu
        menu.addItem(languageItem)

        let cleanItem = NSMenuItem(title: "Clean filler words locally", action: #selector(toggleCleanFillers), keyEquivalent: "")
        cleanItem.target = self
        cleanItem.state = settings.cleanFillers ? .on : .off
        menu.addItem(cleanItem)

        let polishItem = NSMenuItem(title: "Formalize with GPT-5.4 Mini", action: #selector(togglePolishWithGPT), keyEquivalent: "")
        polishItem.target = self
        polishItem.state = settings.polishWithGPT ? .on : .off
        menu.addItem(polishItem)

        let restoreItem = NSMenuItem(title: "Restore clipboard after paste", action: #selector(toggleRestoreClipboard), keyEquivalent: "")
        restoreItem.target = self
        restoreItem.state = settings.restoreClipboard ? .on : .off
        menu.addItem(restoreItem)

        menu.addItem(.separator())

        let accessibilityItem = NSMenuItem(title: "Request Accessibility Permission", action: #selector(requestAccessibility), keyEquivalent: "")
        accessibilityItem.target = self
        menu.addItem(accessibilityItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit \(AppMetadata.displayName)", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        quitItem.keyEquivalentModifierMask = [.command]
        menu.addItem(quitItem)

        statusItem?.menu = menu
        updateCancelHotKeyRegistration()
    }

    private func addOutputMode(_ mode: OutputMode, to menu: NSMenu) {
        let item = NSMenuItem(title: mode.title, action: #selector(setOutputMode(_:)), keyEquivalent: "")
        item.representedObject = mode.rawValue
        item.state = settings.outputMode == mode ? .on : .off
        item.target = self
        menu.addItem(item)
    }

    private func addLanguage(_ language: RecognitionLanguage, to menu: NSMenu) {
        let item = NSMenuItem(title: language.title, action: #selector(setLanguage(_:)), keyEquivalent: "")
        item.representedObject = language.rawValue
        item.state = settings.language == language ? .on : .off
        item.target = self
        menu.addItem(item)
    }

    private func toggleRecording() {
        if isProcessing {
            flashStatus("Processing")
        } else if isRecording {
            finishRecording()
        } else if isArming {
            cancelPendingStart()
        } else {
            startRecording()
        }
    }

    private func updateCancelHotKeyRegistration() {
        let shouldBeActive = isArming || isRecording || isProcessing

        if shouldBeActive {
            if !cancelHotKeyCenter.isRegistered {
                try? cancelHotKeyCenter.register()
            }
        } else if cancelHotKeyCenter.isRegistered {
            cancelHotKeyCenter.unregister()
        }
    }

    private func cancelCurrentOperation() {
        guard isArming || isRecording || isProcessing else {
            return
        }

        sessionCounter += 1
        activeSession = sessionCounter
        processingTask?.cancel()
        processingTask = nil
        audioRecorder.cancel()

        isArming = false
        isRecording = false
        isProcessing = false
        rebuildMenu()
        updateStatusTitle("Canceled")
        floatingStatusWindowController.showCanceled()
        scheduleIdleStatus()
    }

    private func startRecording() {
        guard ensureAPIKeyIsAvailable() else {
            return
        }

        isArming = true
        sessionCounter += 1
        activeSession = sessionCounter
        let sessionID = activeSession
        rebuildMenu()
        updateStatusTitle("Waiting")
        floatingStatusWindowController.showRecording()

        audioRecorder.requestPermission { [weak self] microphoneAllowed in
            DispatchQueue.main.async {
                guard let self else {
                    return
                }

                guard self.isArming, sessionID == self.activeSession else {
                    return
                }

                guard microphoneAllowed else {
                    self.isArming = false
                    self.rebuildMenu()
                    self.updateStatusTitle("Mic Permission")
                    self.floatingStatusWindowController.showError("Microphone permission needed")
                    self.showAlert(
                        title: "Microphone permission needed",
                        message: "\(AppMetadata.displayName) records local audio before sending it to OpenRouter for transcription."
                    )
                    return
                }

                self.beginRecording(sessionID: sessionID)
            }
        }
    }

    private func beginRecording(sessionID: Int) {
        guard isArming, sessionID == activeSession else {
            return
        }

        do {
            _ = try audioRecorder.start()
            isArming = false
            isRecording = true
            rebuildMenu()
            updateStatusTitle("● Rec")
            floatingStatusWindowController.showRecording()
        } catch {
            isArming = false
            isRecording = false
            audioRecorder.cancel()
            rebuildMenu()
            updateStatusTitle("Error")
            floatingStatusWindowController.showError(error.localizedDescription)
            showAlert(title: "Could not start recording", message: error.localizedDescription)
        }
    }

    private func cancelPendingStart() {
        guard isArming else {
            return
        }

        isArming = false
        sessionCounter += 1
        activeSession = sessionCounter
        rebuildMenu()
        updateStatusTitle("Fn")
        floatingStatusWindowController.hide()
        scheduleIdleStatus()
    }

    private func finishRecording() {
        do {
            let audioURL = try audioRecorder.stop()
            isRecording = false
            isProcessing = true
            rebuildMenu()
            updateStatusTitle("Transcribe")
            floatingStatusWindowController.showTranscribing()
            processRecording(at: audioURL, sessionID: activeSession)
        } catch {
            isRecording = false
            isProcessing = false
            audioRecorder.cancel()
            rebuildMenu()
            updateStatusTitle("Error")
            floatingStatusWindowController.showError(error.localizedDescription)
            showAlert(title: "Could not finish recording", message: error.localizedDescription)
        }
    }

    private func processRecording(at audioURL: URL, sessionID: Int) {
        guard let apiKey = settings.apiKey else {
            isProcessing = false
            rebuildMenu()
            updateStatusTitle("No API Key")
            floatingStatusWindowController.showError("Add OpenRouter API key")
            openSettings()
            return
        }

        let language = settings.language
        let cleanFillers = settings.cleanFillers
        let polishWithGPT = settings.polishWithGPT
        let baseURL = settings.baseURL
        let transcriptionModel = settings.transcriptionModel
        let polishModel = settings.polishModel

        processingTask?.cancel()
        let task = Task { [weak self] in
            guard let self else {
                try? FileManager.default.removeItem(at: audioURL)
                return
            }

            do {
                try Task.checkCancellation()
                let transcript: String
                do {
                    let transcribeResult = try await self.openRouter.transcribe(
                        audioURL: audioURL,
                        language: language,
                        baseURL: baseURL,
                        transcriptionModel: transcriptionModel,
                        apiKey: apiKey
                    )
                    self.recordUsage(
                        operation: .transcription,
                        requestedModel: transcriptionModel,
                        result: transcribeResult
                    )
                    transcript = transcribeResult.text
                } catch OpenRouterClientError.emptyTranscription {
                    try? FileManager.default.removeItem(at: audioURL)
                    await self.handleNoSpeech(sessionID: sessionID)
                    return
                }

                let cleaned = TextPostProcessor.process(
                    transcript,
                    language: language,
                    cleanFillers: cleanFillers
                )

                guard TextPostProcessor.hasMeaningfulContent(cleaned) else {
                    try? FileManager.default.removeItem(at: audioURL)
                    await self.handleNoSpeech(sessionID: sessionID)
                    return
                }

                let finalText: String
                if polishWithGPT {
                    await self.showPolishingPhase(sessionID: sessionID)
                    try Task.checkCancellation()
                    do {
                        let polishResult = try await self.openRouter.formalize(
                            text: cleaned,
                            language: language,
                            baseURL: baseURL,
                            polishModel: polishModel,
                            apiKey: apiKey
                        )
                        self.recordUsage(
                            operation: .polish,
                            requestedModel: polishModel,
                            result: polishResult
                        )
                        finalText = polishResult.text
                    } catch OpenRouterClientError.emptyFormalization {
                        try? FileManager.default.removeItem(at: audioURL)
                        await self.handleNoSpeech(sessionID: sessionID)
                        return
                    }
                } else {
                    finalText = cleaned
                }

                guard TextPostProcessor.hasMeaningfulContent(finalText) else {
                    try? FileManager.default.removeItem(at: audioURL)
                    await self.handleNoSpeech(sessionID: sessionID)
                    return
                }

                try? FileManager.default.removeItem(at: audioURL)
                await self.completeProcessing(with: finalText, sessionID: sessionID)
            } catch is CancellationError {
                try? FileManager.default.removeItem(at: audioURL)
                await self.handleProcessingCanceled(sessionID: sessionID)
            } catch {
                try? FileManager.default.removeItem(at: audioURL)
                await self.completeProcessing(with: error, sessionID: sessionID)
            }
        }

        processingTask = task
    }

    @MainActor
    private func showPolishingPhase(sessionID: Int) {
        guard sessionID == activeSession, isProcessing else {
            return
        }

        updateStatusTitle("Polish")
        floatingStatusWindowController.showPolishing()
    }

    @MainActor
    private func handleNoSpeech(sessionID: Int) {
        guard sessionID == activeSession else {
            return
        }

        processingTask = nil
        isProcessing = false
        rebuildMenu()
        updateStatusTitle("No Speech")
        floatingStatusWindowController.showNoSpeech()
        scheduleIdleStatus()
    }

    @MainActor
    private func handleProcessingCanceled(sessionID: Int) {
        guard sessionID == activeSession else {
            return
        }

        processingTask = nil
        isProcessing = false
        rebuildMenu()
        updateStatusTitle("Canceled")
        floatingStatusWindowController.showCanceled()
        scheduleIdleStatus()
    }

    @MainActor
    private func completeProcessing(with text: String, sessionID: Int) {
        guard sessionID == activeSession else {
            return
        }

        processingTask = nil
        isProcessing = false
        rebuildMenu()

        let finalText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !finalText.isEmpty else {
            updateStatusTitle("No Speech")
            floatingStatusWindowController.showNoSpeech()
            scheduleIdleStatus()
            return
        }

        let result = injector.insert(
            text: finalText,
            mode: settings.outputMode,
            restoreClipboard: settings.restoreClipboard
        )

        switch result {
        case .pasted:
            updateStatusTitle("Pasted")
            floatingStatusWindowController.showSuccess("Pasted at cursor")
        case .copied:
            updateStatusTitle("Copied")
            floatingStatusWindowController.showSuccess("Copied to clipboard")
        case .copiedBecauseAccessibilityMissing:
            updateStatusTitle("Copied")
            floatingStatusWindowController.showSuccess("Copied: no paste permission")
        }

        scheduleIdleStatus()
    }

    @MainActor
    private func completeProcessing(with error: Error, sessionID: Int) {
        guard sessionID == activeSession else {
            return
        }

        processingTask = nil
        isProcessing = false
        rebuildMenu()
        updateStatusTitle("Error")
        floatingStatusWindowController.showError(error.localizedDescription)
        showAlert(title: "OpenRouter request failed", message: error.localizedDescription)
    }

    private func ensureAPIKeyIsAvailable() -> Bool {
        if settings.apiKey != nil {
            return true
        }

        openSettings()
        floatingStatusWindowController.showError("Add OpenRouter API key")
        flashStatus("Add API Key")
        return false
    }

    private func updateStatusTitle(_ title: String) {
        let iconState = statusBarIconState(for: title)
        statusItem?.button?.title = ""
        statusItem?.button?.image = StatusBarIconFactory.image(for: iconState)
        statusItem?.button?.toolTip = "\(AppMetadata.displayName): \(title)"
        statusItem?.button?.setAccessibilityLabel("\(AppMetadata.displayName) \(title)")
    }

    private func flashStatus(_ title: String) {
        updateStatusTitle(title)
        scheduleIdleStatus()
    }

    private func statusBarIconState(for title: String) -> StatusBarIconState {
        let normalized = title.lowercased()

        if title.contains("●") ||
            normalized.contains("rec") {
            return .recording
        }

        if normalized.contains("transcribe") ||
            normalized.contains("polish") ||
            normalized.contains("processing") ||
            normalized.contains("waiting") {
            return .working
        }

        if normalized.contains("pasted") ||
            normalized.contains("copied") ||
            normalized.contains("ready") {
            return .success
        }

        if normalized.contains("failed") ||
            normalized.contains("error") {
            return .error
        }

        if normalized.contains("permission") ||
            normalized.contains("api key") ||
            normalized.contains("grant") {
            return .warning
        }

        return .idle
    }

    private func scheduleIdleStatus() {
        lastStatusReset?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard self?.isRecording != true,
                  self?.isProcessing != true else {
                return
            }
            self?.updateStatusTitle("Fn")
        }

        lastStatusReset = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: workItem)
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func recordUsage(
        operation: UsageOperation,
        requestedModel: String,
        result: OpenRouterTextResult
    ) {
        let record = UsageRecord(
            operation: operation,
            model: requestedModel,
            resolvedModel: result.model,
            usage: result.usage
        )
        usageStore.append(record)
    }
}
