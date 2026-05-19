import AppKit
import Carbon.HIToolbox

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = SettingsStore()
    private let usageStore = UsageStore()
    private let correctionStore = CorrectionStore()
    private let audioRecorder = AudioRecorder()
    private let outputDuckingCoordinator = SystemOutputDuckingCoordinator()
    private let openRouter = OpenRouterClient()
    private let deepgram = DeepgramStreamingClient()
    private let elevenLabs = ElevenLabsClient()
    private let elevenLabsStreaming = ElevenLabsStreamingClient()
    private let doubao = DoubaoStreamingClient()
    private let injector = TextInjector()
    private lazy var textChangeMonitor = TextChangeMonitor(correctionStore: correctionStore)
    private lazy var preferencesWindowController = PreferencesWindowController(
        settings: settings,
        usageStore: usageStore,
        correctionStore: correctionStore
    )
    private lazy var floatingStatusWindowController = FloatingStatusWindowController()
    private let cancelHotKeyCenter = HotKeyCenter(keyCode: UInt32(kVK_Escape), modifiers: 0)

    private var statusItem: NSStatusItem?
    private var hotKeyCenter: FunctionHotKeyCenter?
    private var processingTask: Task<Void, Never>?
    private var streamingTask: Task<StreamingTranscriptResult, Error>?
    private var streamingAPIKey: String?
    private var streamingModel: String?
    private var streamingLanguage: String = "multi"
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
        outputDuckingCoordinator.restoreAfterRecording()
        processingTask?.cancel()
        streamingTask?.cancel()
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
        streamingTask?.cancel()
        streamingTask = nil
        streamingAPIKey = nil
        streamingModel = nil
        audioRecorder.cancel()
        outputDuckingCoordinator.restoreAfterRecording()

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

        let provider = settings.transcriptionProvider
        let recordingMode: RecordingMode
        switch provider {
        case .deepgram, .elevenLabsRealtime, .doubao:
            recordingMode = .livePCM
        case .openRouterWhisper, .elevenLabs:
            recordingMode = .fileBackup
        }

        do {
            outputDuckingCoordinator.duckForRecording(level: Float(settings.duckingLevel))
            _ = try audioRecorder.start(
                microphone: settings.preferredMicrophone,
                mode: recordingMode
            )

            if provider == .deepgram {
                try startDeepgramStreaming(sessionID: sessionID)
            } else if provider == .elevenLabsRealtime {
                try startElevenLabsRealtimeStreaming(sessionID: sessionID)
            } else if provider == .doubao {
                try startDoubaoStreaming(sessionID: sessionID)
            }

            isArming = false
            isRecording = true
            rebuildMenu()
            updateStatusTitle("● Rec")
            floatingStatusWindowController.showRecording()
        } catch {
            isArming = false
            isRecording = false
            streamingTask?.cancel()
            streamingTask = nil
            streamingAPIKey = nil
            streamingModel = nil
            audioRecorder.cancel()
            outputDuckingCoordinator.restoreAfterRecording()
            rebuildMenu()
            updateStatusTitle("Error")
            floatingStatusWindowController.showError(error.localizedDescription)
            showAlert(title: "Could not start recording", message: error.localizedDescription)
        }
    }

    private func startDeepgramStreaming(sessionID: Int) throws {
        guard let pcmStream = audioRecorder.pcmStream else {
            throw AudioRecorderError.microphoneUnavailable
        }
        guard let apiKey = settings.deepgramAPIKey else {
            throw DeepgramStreamingError.authenticationFailed("Deepgram API key not configured")
        }

        let model = settings.deepgramModel
        let baseURL = settings.deepgramBaseURL
        let language = settings.deepgramLanguage
        streamingAPIKey = apiKey
        streamingModel = model
        streamingLanguage = language

        streamingTask = Task { [deepgram] in
            try await deepgram.runSession(
                pcm: pcmStream,
                apiKey: apiKey,
                baseURL: baseURL,
                model: model,
                language: language
            )
        }
    }

    private func startElevenLabsRealtimeStreaming(sessionID: Int) throws {
        guard let pcmStream = audioRecorder.pcmStream else {
            throw AudioRecorderError.microphoneUnavailable
        }
        guard let apiKey = settings.elevenLabsRealtimeAPIKey else {
            throw ElevenLabsStreamingError.authenticationFailed("ElevenLabs Realtime API key not configured")
        }

        let model = settings.elevenLabsRealtimeModel
        let baseURL = settings.elevenLabsRealtimeBaseURL
        let language = settings.elevenLabsRealtimeLanguage
        streamingAPIKey = apiKey
        streamingModel = model
        streamingLanguage = language

        streamingTask = Task { [elevenLabsStreaming] in
            try await elevenLabsStreaming.runSession(
                pcm: pcmStream,
                apiKey: apiKey,
                baseURL: baseURL,
                model: model,
                language: language
            )
        }
    }

    private func startDoubaoStreaming(sessionID: Int) throws {
        guard let pcmStream = audioRecorder.pcmStream else {
            throw AudioRecorderError.microphoneUnavailable
        }
        guard let apiKey = settings.doubaoAPIKey else {
            throw DoubaoStreamingError.authenticationFailed("Doubao API key not configured")
        }

        let baseURL = settings.doubaoBaseURL
        let resourceId = settings.doubaoResourceId
        let language = settings.doubaoLanguage
        streamingAPIKey = apiKey
        streamingModel = "bigmodel"
        streamingLanguage = language

        streamingTask = Task { [doubao] in
            try await doubao.runSession(
                pcm: pcmStream,
                apiKey: apiKey,
                baseURL: baseURL,
                resourceId: resourceId,
                language: language
            )
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
            let artifacts = try audioRecorder.stop()
            outputDuckingCoordinator.restoreAfterRecording()
            isRecording = false
            isProcessing = true
            rebuildMenu()
            updateStatusTitle("Transcribe")
            floatingStatusWindowController.showTranscribing()
            processRecording(artifacts: artifacts, sessionID: activeSession)
        } catch {
            isRecording = false
            isProcessing = false
            streamingTask?.cancel()
            streamingTask = nil
            streamingAPIKey = nil
            streamingModel = nil
            audioRecorder.cancel()
            outputDuckingCoordinator.restoreAfterRecording()
            rebuildMenu()
            updateStatusTitle("Error")
            floatingStatusWindowController.showError(error.localizedDescription)
            showAlert(title: "Could not finish recording", message: error.localizedDescription)
        }
    }

    private func processRecording(artifacts: RecordingArtifacts, sessionID: Int) {
        let provider = settings.transcriptionProvider
        let language = settings.language
        let polishWithGPT = settings.polishWithGPT

        let whisperLanguage = settings.whisperLanguage
        let whisperBaseURL = settings.whisperBaseURL
        let whisperModel = settings.whisperModel
        let whisperKey = settings.whisperAPIKey

        let elevenLabsLanguage = settings.elevenLabsLanguage
        let elevenLabsBaseURL = settings.elevenLabsBaseURL
        let elevenLabsModel = settings.elevenLabsModel
        let elevenLabsKey = settings.elevenLabsAPIKey

        let elevenLabsRealtimeModel = settings.elevenLabsRealtimeModel
        let elevenLabsRealtimeKey = settings.elevenLabsRealtimeAPIKey

        let deepgramModel = settings.deepgramModel

        let polishBaseURL = settings.polishBaseURL
        let polishModel = settings.polishModel
        let polishKey = settings.polishAPIKey

        let processingStartedAt = Date()

        DictationLogger.shared.log(
            "session",
            "begin sessionID=\(sessionID) provider=\(provider.rawValue) language=\(language.rawValue) polish=\(polishWithGPT) recordedSeconds=\(String(format: "%.2f", artifacts.durationSeconds))"
        )

        if provider == .openRouterWhisper, whisperKey == nil {
            isProcessing = false
            rebuildMenu()
            updateStatusTitle("No API Key")
            floatingStatusWindowController.showError("Add Whisper (OpenRouter) API key")
            openSettings()
            if let url = artifacts.audioURL {
                try? FileManager.default.removeItem(at: url)
            }
            return
        }

        if provider == .elevenLabs, elevenLabsKey == nil {
            isProcessing = false
            rebuildMenu()
            updateStatusTitle("No API Key")
            floatingStatusWindowController.showError("Add ElevenLabs API key")
            openSettings()
            if let url = artifacts.audioURL {
                try? FileManager.default.removeItem(at: url)
            }
            return
        }

        if provider == .elevenLabsRealtime, elevenLabsRealtimeKey == nil {
            isProcessing = false
            rebuildMenu()
            updateStatusTitle("No API Key")
            floatingStatusWindowController.showError("Add ElevenLabs Realtime API key")
            openSettings()
            if let url = artifacts.audioURL {
                try? FileManager.default.removeItem(at: url)
            }
            return
        }

        if provider == .doubao, settings.doubaoAPIKey == nil {
            isProcessing = false
            rebuildMenu()
            updateStatusTitle("No API Key")
            floatingStatusWindowController.showError("Add Doubao API key")
            openSettings()
            if let url = artifacts.audioURL {
                try? FileManager.default.removeItem(at: url)
            }
            return
        }

        if polishWithGPT, polishKey == nil {
            isProcessing = false
            rebuildMenu()
            updateStatusTitle("No API Key")
            floatingStatusWindowController.showError("Add Polish API key")
            openSettings()
            if let url = artifacts.audioURL {
                try? FileManager.default.removeItem(at: url)
            }
            return
        }

        let activeStreamingTask = streamingTask
        streamingTask = nil
        streamingAPIKey = nil
        streamingModel = nil

        processingTask?.cancel()
        let task = Task { [weak self] in
            guard let self else {
                if let url = artifacts.audioURL {
                    try? FileManager.default.removeItem(at: url)
                }
                activeStreamingTask?.cancel()
                return
            }

            let cleanupAudio: () -> Void = {
                if let url = artifacts.audioURL {
                    try? FileManager.default.removeItem(at: url)
                }
            }

            do {
                try Task.checkCancellation()

                let transcript: String
                let transcribeStartedAt = Date()
                do {
                    switch provider {
                    case .deepgram, .elevenLabsRealtime, .doubao:
                        guard let streaming = activeStreamingTask else {
                            throw DeepgramStreamingError.connectionFailed("Streaming task missing")
                        }
                        let result = try await withTaskCancellationHandler {
                            try await streaming.value
                        } onCancel: {
                            streaming.cancel()
                        }
                        let requestedModel: String
                        switch provider {
                        case .deepgram: requestedModel = deepgramModel
                        case .elevenLabsRealtime: requestedModel = elevenLabsRealtimeModel
                        case .doubao: requestedModel = "bigmodel"
                        default: requestedModel = result.model
                        }
                        self.recordUsage(
                            operation: .transcription,
                            provider: result.provider,
                            requestedModel: requestedModel,
                            resolvedModel: result.model,
                            audioSeconds: result.audioSeconds,
                            elapsedSeconds: Date().timeIntervalSince(transcribeStartedAt),
                            cost: result.cost
                        )
                        transcript = result.text
                    case .openRouterWhisper:
                        guard let audioURL = artifacts.audioURL, let apiKey = whisperKey else {
                            throw OpenRouterClientError.invalidResponse
                        }
                        let transcribeResult = try await self.openRouter.transcribe(
                            audioURL: audioURL,
                            language: whisperLanguage,
                            baseURL: whisperBaseURL,
                            transcriptionModel: whisperModel,
                            apiKey: apiKey
                        )
                        self.recordUsage(
                            operation: .transcription,
                            provider: .openrouter,
                            requestedModel: whisperModel,
                            elapsedSeconds: Date().timeIntervalSince(transcribeStartedAt),
                            result: transcribeResult
                        )
                        transcript = transcribeResult.text
                        DictationLogger.shared.logText("whisper.transcript", transcript)
                    case .elevenLabs:
                        guard let audioURL = artifacts.audioURL, let apiKey = elevenLabsKey else {
                            throw ElevenLabsClientError.invalidResponse
                        }
                        let elResult = try await self.elevenLabs.transcribe(
                            audioURL: audioURL,
                            baseURL: elevenLabsBaseURL,
                            model: elevenLabsModel,
                            language: elevenLabsLanguage,
                            apiKey: apiKey
                        )
                        self.recordUsage(
                            operation: .transcription,
                            provider: .elevenLabs,
                            requestedModel: elevenLabsModel,
                            resolvedModel: elResult.model,
                            audioSeconds: artifacts.durationSeconds,
                            elapsedSeconds: Date().timeIntervalSince(transcribeStartedAt),
                            cost: ElevenLabsClient.estimatedCost(audioSeconds: artifacts.durationSeconds)
                        )
                        transcript = elResult.text
                    }
                    DictationLogger.shared.log(
                        "timing",
                        "transcribe sessionID=\(sessionID) provider=\(provider.rawValue) elapsed=\(Self.formatElapsed(transcribeStartedAt))s chars=\(transcript.count)"
                    )
                } catch OpenRouterClientError.emptyTranscription {
                    DictationLogger.shared.log("session", "empty whisper transcript sessionID=\(sessionID) elapsed=\(Self.formatElapsed(transcribeStartedAt))s")
                    cleanupAudio()
                    DictationLogger.shared.log(
                        "timing",
                        "session-total sessionID=\(sessionID) outcome=no-speech elapsed=\(Self.formatElapsed(processingStartedAt))s"
                    )
                    await self.handleNoSpeech(sessionID: sessionID)
                    return
                } catch ElevenLabsClientError.emptyTranscription {
                    DictationLogger.shared.log("session", "empty elevenlabs transcript sessionID=\(sessionID) elapsed=\(Self.formatElapsed(transcribeStartedAt))s")
                    cleanupAudio()
                    DictationLogger.shared.log(
                        "timing",
                        "session-total sessionID=\(sessionID) outcome=no-speech elapsed=\(Self.formatElapsed(processingStartedAt))s"
                    )
                    await self.handleNoSpeech(sessionID: sessionID)
                    return
                } catch DeepgramStreamingError.emptyTranscript {
                    DictationLogger.shared.log("session", "empty deepgram transcript sessionID=\(sessionID) elapsed=\(Self.formatElapsed(transcribeStartedAt))s")
                    cleanupAudio()
                    DictationLogger.shared.log(
                        "timing",
                        "session-total sessionID=\(sessionID) outcome=no-speech elapsed=\(Self.formatElapsed(processingStartedAt))s"
                    )
                    await self.handleNoSpeech(sessionID: sessionID)
                    return
                } catch ElevenLabsStreamingError.emptyTranscript {
                    DictationLogger.shared.log("session", "empty elevenlabs realtime transcript sessionID=\(sessionID) elapsed=\(Self.formatElapsed(transcribeStartedAt))s")
                    cleanupAudio()
                    DictationLogger.shared.log(
                        "timing",
                        "session-total sessionID=\(sessionID) outcome=no-speech elapsed=\(Self.formatElapsed(processingStartedAt))s"
                    )
                    await self.handleNoSpeech(sessionID: sessionID)
                    return
                } catch DoubaoStreamingError.emptyTranscript {
                    DictationLogger.shared.log("session", "empty doubao transcript sessionID=\(sessionID) elapsed=\(Self.formatElapsed(transcribeStartedAt))s")
                    cleanupAudio()
                    DictationLogger.shared.log(
                        "timing",
                        "session-total sessionID=\(sessionID) outcome=no-speech elapsed=\(Self.formatElapsed(processingStartedAt))s"
                    )
                    await self.handleNoSpeech(sessionID: sessionID)
                    return
                }

                let cleaned = TextPostProcessor.process(
                    transcript,
                    language: language
                )

                guard TextPostProcessor.hasMeaningfulContent(cleaned) else {
                    cleanupAudio()
                    DictationLogger.shared.log(
                        "timing",
                        "session-total sessionID=\(sessionID) outcome=no-speech-after-cleanup elapsed=\(Self.formatElapsed(processingStartedAt))s"
                    )
                    await self.handleNoSpeech(sessionID: sessionID)
                    return
                }

                let finalText: String
                if polishWithGPT {
                    await self.showPolishingPhase(sessionID: sessionID)
                    try Task.checkCancellation()

                    guard let apiKey = polishKey else {
                        throw OpenRouterClientError.invalidResponse
                    }

                    let polishStartedAt = Date()
                    do {
                        let correctionContext = self.correctionStore.getRecentRecords(count: 20)
                        let polishResult = try await self.openRouter.formalize(
                            text: cleaned,
                            language: language,
                            baseURL: polishBaseURL,
                            polishModel: polishModel,
                            apiKey: apiKey,
                            correctionContext: correctionContext
                        )
                        self.recordUsage(
                            operation: .polish,
                            provider: .openrouter,
                            requestedModel: polishModel,
                            elapsedSeconds: Date().timeIntervalSince(polishStartedAt),
                            result: polishResult
                        )
                        finalText = polishResult.text
                        DictationLogger.shared.logText("polished", finalText)
                        DictationLogger.shared.log(
                            "timing",
                            "polish sessionID=\(sessionID) elapsed=\(Self.formatElapsed(polishStartedAt))s chars=\(finalText.count)"
                        )
                    } catch OpenRouterClientError.emptyFormalization {
                        DictationLogger.shared.log("session", "empty polish sessionID=\(sessionID) elapsed=\(Self.formatElapsed(polishStartedAt))s")
                        cleanupAudio()
                        DictationLogger.shared.log(
                            "timing",
                            "session-total sessionID=\(sessionID) outcome=empty-polish elapsed=\(Self.formatElapsed(processingStartedAt))s"
                        )
                        await self.handleNoSpeech(sessionID: sessionID)
                        return
                    }
                } else {
                    finalText = cleaned
                }

                guard TextPostProcessor.hasMeaningfulContent(finalText) else {
                    cleanupAudio()
                    DictationLogger.shared.log(
                        "timing",
                        "session-total sessionID=\(sessionID) outcome=no-meaningful-final elapsed=\(Self.formatElapsed(processingStartedAt))s"
                    )
                    await self.handleNoSpeech(sessionID: sessionID)
                    return
                }

                cleanupAudio()
                DictationLogger.shared.log(
                    "timing",
                    "session-total sessionID=\(sessionID) outcome=ok elapsed=\(Self.formatElapsed(processingStartedAt))s recordedSeconds=\(String(format: "%.2f", artifacts.durationSeconds))"
                )
                await self.completeProcessing(with: finalText, sessionID: sessionID)
            } catch is CancellationError {
                activeStreamingTask?.cancel()
                cleanupAudio()
                DictationLogger.shared.log(
                    "timing",
                    "session-total sessionID=\(sessionID) outcome=canceled elapsed=\(Self.formatElapsed(processingStartedAt))s"
                )
                await self.handleProcessingCanceled(sessionID: sessionID)
            } catch {
                activeStreamingTask?.cancel()
                cleanupAudio()
                DictationLogger.shared.log(
                    "timing",
                    "session-total sessionID=\(sessionID) outcome=error elapsed=\(Self.formatElapsed(processingStartedAt))s message=\(error.localizedDescription)"
                )
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

        // Start monitoring for user corrections
        textChangeMonitor.startMonitoring(
            outputText: finalText,
            sessionID: sessionID,
            duration: 30.0,
            pollInterval: 5.0
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
        showAlert(title: "Transcription failed", message: error.localizedDescription)
    }

    private func ensureAPIKeyIsAvailable() -> Bool {
        let provider = settings.transcriptionProvider
        let hasTranscriberKey: Bool
        let missingMessage: String
        switch provider {
        case .deepgram:
            hasTranscriberKey = settings.deepgramAPIKey != nil
            missingMessage = "Add Deepgram API key"
        case .openRouterWhisper:
            hasTranscriberKey = settings.whisperAPIKey != nil
            missingMessage = "Add Whisper (OpenRouter) API key"
        case .elevenLabs:
            hasTranscriberKey = settings.elevenLabsAPIKey != nil
            missingMessage = "Add ElevenLabs API key"
        case .elevenLabsRealtime:
            hasTranscriberKey = settings.elevenLabsRealtimeAPIKey != nil
            missingMessage = "Add ElevenLabs Realtime API key"
        case .doubao:
            hasTranscriberKey = settings.doubaoAPIKey != nil
            missingMessage = "Add Doubao API key"
        }

        let needsPolishKey = settings.polishWithGPT
        let hasPolishKey = settings.polishAPIKey != nil

        if hasTranscriberKey, !needsPolishKey || hasPolishKey {
            return true
        }

        if !hasTranscriberKey {
            openSettings()
            floatingStatusWindowController.showError(missingMessage)
            flashStatus("Add API Key")
            return false
        }

        openSettings()
        floatingStatusWindowController.showError("Add Polish API key")
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
        provider: UsageProvider,
        requestedModel: String,
        elapsedSeconds: Double,
        result: OpenRouterTextResult
    ) {
        let record = UsageRecord(
            operation: operation,
            provider: provider,
            model: requestedModel,
            resolvedModel: result.model,
            elapsedSeconds: elapsedSeconds,
            usage: result.usage
        )
        usageStore.append(record)
    }

    private func recordUsage(
        operation: UsageOperation,
        provider: UsageProvider,
        requestedModel: String,
        resolvedModel: String,
        audioSeconds: Double,
        elapsedSeconds: Double,
        cost: Double
    ) {
        let record = UsageRecord(
            operation: operation,
            provider: provider,
            model: requestedModel,
            resolvedModel: resolvedModel,
            audioSeconds: audioSeconds,
            elapsedSeconds: elapsedSeconds,
            cost: cost
        )
        usageStore.append(record)
    }

    fileprivate static func formatElapsed(_ startedAt: Date) -> String {
        String(format: "%.2f", Date().timeIntervalSince(startedAt))
    }
}
