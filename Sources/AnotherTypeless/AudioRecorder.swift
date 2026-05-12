import AVFoundation
import Foundation

final class AudioRecorder {
    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var currentURL: URL?
    private var hasInputTap = false
    private var recordingError: Error?

    func requestPermission(completion: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .audio, completionHandler: completion)
    }

    func start() throws -> URL {
        cancel()
        recordingError = nil

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

    func stop() throws -> URL {
        audioEngine?.stop()
        removeInputTapIfNeeded()
        audioEngine?.reset()
        audioEngine = nil
        audioFile = nil

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
        audioEngine?.stop()
        removeInputTapIfNeeded()
        audioEngine?.reset()
        audioEngine = nil
        audioFile = nil

        if let currentURL {
            try? FileManager.default.removeItem(at: currentURL)
        }

        currentURL = nil
        recordingError = nil
    }

    private func removeInputTapIfNeeded() {
        if hasInputTap {
            audioEngine?.inputNode.removeTap(onBus: 0)
            hasInputTap = false
        }
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

enum AudioRecorderError: LocalizedError {
    case microphoneUnavailable
    case noActiveRecording

    var errorDescription: String? {
        switch self {
        case .microphoneUnavailable:
            return "No microphone input format is available."
        case .noActiveRecording:
            return "There is no active recording to stop."
        }
    }
}
