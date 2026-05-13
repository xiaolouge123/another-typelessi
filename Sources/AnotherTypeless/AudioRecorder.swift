import AVFoundation
import CoreAudio
import Foundation

enum RecordingMode {
    case fileBackup
    case livePCM
}

struct RecordingArtifacts {
    let audioURL: URL?
    let durationSeconds: Double
}

final class AudioRecorder: NSObject {
    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var hasInputTap = false

    private var currentURL: URL?
    private var recordingError: Error?
    private var recordingMode: RecordingMode = .fileBackup
    private var framesWritten: AVAudioFramePosition = 0
    private var recordingSampleRate: Double = 0

    private var pcmStreamContinuation: AsyncStream<Data>.Continuation?
    private(set) var pcmStream: AsyncStream<Data>?
    private var pcmConverter: AVAudioConverter?
    private var pcmOutputFormat: AVAudioFormat?

    func requestPermission(completion: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .audio, completionHandler: completion)
    }

    func start(microphone: MicrophonePreference, mode: RecordingMode) throws -> URL? {
        cancel()
        recordingError = nil
        recordingMode = mode
        framesWritten = 0

        if mode == .livePCM {
            let (stream, continuation) = Self.makePCMStream()
            pcmStream = stream
            pcmStreamContinuation = continuation
        }

        return try startAudioEngine(microphone: microphone, mode: mode)
    }

    func stop() throws -> RecordingArtifacts {
        finalizeAudioEngine()
        pcmStreamContinuation?.finish()
        pcmStreamContinuation = nil

        if let recordingError {
            self.recordingError = nil
            throw recordingError
        }

        let durationSeconds = recordingSampleRate > 0
            ? Double(framesWritten) / recordingSampleRate
            : 0

        let result = RecordingArtifacts(
            audioURL: currentURL,
            durationSeconds: durationSeconds
        )

        currentURL = nil
        framesWritten = 0
        recordingSampleRate = 0
        pcmStream = nil
        pcmConverter = nil
        pcmOutputFormat = nil

        return result
    }

    func cancel() {
        finalizeAudioEngine()
        pcmStreamContinuation?.finish()
        pcmStreamContinuation = nil

        if let currentURL {
            try? FileManager.default.removeItem(at: currentURL)
        }

        currentURL = nil
        recordingError = nil
        framesWritten = 0
        recordingSampleRate = 0
        pcmStream = nil
        pcmConverter = nil
        pcmOutputFormat = nil
    }

    private func startAudioEngine(microphone: MicrophonePreference, mode: RecordingMode) throws -> URL? {
        let engine = AVAudioEngine()

        if microphone == .builtIn {
            try Self.bindBuiltInMicrophone(to: engine)
        }

        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        guard recordingFormat.sampleRate > 0, recordingFormat.channelCount > 0 else {
            throw AudioRecorderError.microphoneUnavailable
        }

        recordingSampleRate = recordingFormat.sampleRate

        var fileURL: URL? = nil
        switch mode {
        case .fileBackup:
            let url = try makeRecordingURL()
            let file = try AVAudioFile(forWriting: url, settings: recordingFormat.settings)
            audioFile = file
            currentURL = url
            fileURL = url
        case .livePCM:
            try configurePCMConverter(from: recordingFormat)
        }

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: recordingFormat) { [weak self] buffer, _ in
            guard let self else {
                return
            }

            self.framesWritten += AVAudioFramePosition(buffer.frameLength)

            switch self.recordingMode {
            case .fileBackup:
                guard let file = self.audioFile else {
                    return
                }
                do {
                    try file.write(from: buffer)
                } catch {
                    self.recordingError = error
                }
            case .livePCM:
                self.forwardPCMBuffer(buffer)
            }
        }

        hasInputTap = true
        audioEngine = engine

        do {
            engine.prepare()
            try engine.start()
        } catch {
            cancel()
            throw error
        }

        return fileURL
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

    private static func makePCMStream() -> (AsyncStream<Data>, AsyncStream<Data>.Continuation) {
        var continuation: AsyncStream<Data>.Continuation!
        let stream = AsyncStream<Data>(bufferingPolicy: .unbounded) { cont in
            continuation = cont
        }
        return (stream, continuation)
    }

    private func configurePCMConverter(from inputFormat: AVAudioFormat) throws {
        let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16_000,
            channels: 1,
            interleaved: true
        )
        guard let targetFormat, let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw AudioRecorderError.microphoneUnavailable
        }

        pcmConverter = converter
        pcmOutputFormat = targetFormat
    }

    private func forwardPCMBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let converter = pcmConverter,
              let outputFormat = pcmOutputFormat,
              let continuation = pcmStreamContinuation else {
            return
        }

        let ratio = outputFormat.sampleRate / buffer.format.sampleRate
        let estimatedFrames = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: outputFormat,
            frameCapacity: estimatedFrames
        ) else {
            return
        }

        var delivered = false
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            if delivered {
                outStatus.pointee = .noDataNow
                return nil
            }
            delivered = true
            outStatus.pointee = .haveData
            return buffer
        }

        var error: NSError?
        let status = converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)

        guard status != .error, outputBuffer.frameLength > 0,
              let channelData = outputBuffer.int16ChannelData else {
            if let error {
                self.recordingError = error
            }
            return
        }

        let byteCount = Int(outputBuffer.frameLength) * MemoryLayout<Int16>.size
        let data = Data(bytes: channelData[0], count: byteCount)
        continuation.yield(data)
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

    private static func bindBuiltInMicrophone(to engine: AVAudioEngine) throws {
        guard let deviceID = findBuiltInMicrophoneDeviceID() else {
            throw AudioRecorderError.inputDeviceUnavailable
        }

        let audioUnit = engine.inputNode.audioUnit
        guard let audioUnit else {
            throw AudioRecorderError.inputDeviceUnavailable
        }

        var device = deviceID
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &device,
            size
        )

        guard status == noErr else {
            throw AudioRecorderError.inputDeviceUnavailable
        }
    }

    private static func findBuiltInMicrophoneDeviceID() -> AudioDeviceID? {
        guard let captureDevice = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInMicrophone],
            mediaType: .audio,
            position: .unspecified
        ).devices.first else {
            return nil
        }

        let targetUID = captureDevice.uniqueID
        return audioDeviceID(matchingUID: targetUID)
    }

    private static func audioDeviceID(matchingUID uid: String) -> AudioDeviceID? {
        var propertySize: UInt32 = 0
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &propertySize
        )
        guard status == noErr else {
            return nil
        }

        let deviceCount = Int(propertySize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)

        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &propertySize,
            &deviceIDs
        )
        guard status == noErr else {
            return nil
        }

        for deviceID in deviceIDs {
            if deviceUID(for: deviceID) == uid {
                return deviceID
            }
        }
        return nil
    }

    private static func deviceUID(for deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var cfString: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)

        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &size,
            &cfString
        )
        guard status == noErr, let cfString else {
            return nil
        }
        return cfString.takeRetainedValue() as String
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
