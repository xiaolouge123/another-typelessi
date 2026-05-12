import AVFoundation
import CoreAudio
import Foundation

final class AudioRecorder: NSObject {
    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var hasInputTap = false

    private var captureSession: AVCaptureSession?
    private var captureOutput: AVCaptureAudioFileOutput?
    private var captureCompletionSemaphore: DispatchSemaphore?

    private var currentURL: URL?
    private var recordingError: Error?

    func requestPermission(completion: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .audio, completionHandler: completion)
    }

    func start(microphone: MicrophonePreference = .systemDefault) throws -> URL {
        cancel()
        recordingError = nil

        switch microphone {
        case .builtIn:
            if let url = try? startCaptureSession() {
                currentURL = url
                return url
            }
            // Fall through to AVAudioEngine if AVCaptureSession setup failed.
            return try startAudioEngine()
        case .systemDefault:
            return try startAudioEngine()
        }
    }

    func stop() throws -> URL {
        if captureSession != nil {
            finalizeCaptureSession()
        } else {
            finalizeAudioEngine()
        }

        if let recordingError {
            self.recordingError = nil
            throw recordingError
        }

        guard let currentURL else {
            throw AudioRecorderError.noActiveRecording
        }

        self.currentURL = nil
        return currentURL
    }

    func cancel() {
        if captureSession != nil {
            finalizeCaptureSession()
        } else {
            finalizeAudioEngine()
        }

        if let currentURL {
            try? FileManager.default.removeItem(at: currentURL)
        }

        currentURL = nil
        recordingError = nil
    }

    private func startAudioEngine() throws -> URL {
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode

        let recordingFormat = inputNode.outputFormat(forBus: 0)
        guard recordingFormat.sampleRate > 0, recordingFormat.channelCount > 0 else {
            throw AudioRecorderError.microphoneUnavailable
        }

        let url = try makeRecordingURL()
        let file = try AVAudioFile(forWriting: url, settings: recordingFormat.settings)

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: recordingFormat) { [weak self] buffer, _ in
            guard let self else {
                return
            }

            do {
                try file.write(from: buffer)
            } catch {
                self.recordingError = error
            }
        }

        hasInputTap = true
        audioFile = file
        currentURL = url
        audioEngine = engine

        do {
            engine.prepare()
            try engine.start()
        } catch {
            cancel()
            throw error
        }

        return url
    }

    private func finalizeAudioEngine() {
        audioEngine?.stop()
        removeInputTapIfNeeded()
        audioEngine?.reset()
        audioEngine = nil
        audioFile = nil
    }

    private func removeInputTapIfNeeded() {
        if hasInputTap {
            audioEngine?.inputNode.removeTap(onBus: 0)
            hasInputTap = false
        }
    }

    private func startCaptureSession() throws -> URL {
        guard let device = Self.discoverBuiltInMicrophone() else {
            throw AudioRecorderError.inputDeviceUnavailable
        }

        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: device)
        } catch {
            throw AudioRecorderError.inputDeviceUnavailable
        }

        let session = AVCaptureSession()
        session.beginConfiguration()

        guard session.canAddInput(input) else {
            session.commitConfiguration()
            throw AudioRecorderError.inputDeviceUnavailable
        }
        session.addInput(input)

        let output = AVCaptureAudioFileOutput()
        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            throw AudioRecorderError.inputDeviceUnavailable
        }
        session.addOutput(output)
        session.commitConfiguration()

        let url = try makeRecordingURL()

        captureSession = session
        captureOutput = output

        session.startRunning()
        output.startRecording(to: url, outputFileType: .wav, recordingDelegate: self)

        return url
    }

    private func finalizeCaptureSession() {
        guard let session = captureSession else {
            return
        }

        if let output = captureOutput, output.isRecording {
            let semaphore = DispatchSemaphore(value: 0)
            captureCompletionSemaphore = semaphore
            output.stopRecording()
            _ = semaphore.wait(timeout: .now() + 5.0)
            captureCompletionSemaphore = nil
        }

        if session.isRunning {
            session.stopRunning()
        }

        captureOutput = nil
        captureSession = nil
    }

    private static func discoverBuiltInMicrophone() -> AVCaptureDevice? {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInMicrophone],
            mediaType: .audio,
            position: .unspecified
        )
        return discovery.devices.first
    }

    private func makeRecordingURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(AppMetadata.displayName, isDirectory: true)

        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        LocalFileSecurity.protectDirectory(directory)

        return directory.appendingPathComponent("dictation-\(UUID().uuidString).wav")
    }
}

extension AudioRecorder: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        if let error {
            let nsError = error as NSError
            let successCode = AVError.Code.maximumDurationReached.rawValue
            if nsError.domain != AVFoundationErrorDomain || nsError.code != successCode {
                recordingError = error
            }
        }
        captureCompletionSemaphore?.signal()
    }
}

enum AudioRecorderError: LocalizedError {
    case microphoneUnavailable
    case noActiveRecording
    case inputDeviceUnavailable

    var errorDescription: String? {
        switch self {
        case .microphoneUnavailable:
            return "No microphone input format is available."
        case .noActiveRecording:
            return "There is no active recording to stop."
        case .inputDeviceUnavailable:
            return "Could not bind the built-in microphone."
        }
    }
}
