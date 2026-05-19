import Compression
import Foundation

enum DoubaoStreamingError: LocalizedError {
    case invalidResponse
    case connectionFailed(String)
    case authenticationFailed(String)
    case emptyTranscript
    case serverError(code: UInt32, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Doubao returned an unexpected response."
        case .connectionFailed(let detail):
            return "Could not connect to Doubao: \(detail)"
        case .authenticationFailed(let detail):
            return "Doubao rejected the API key: \(detail)"
        case .emptyTranscript:
            return "Doubao returned an empty transcript."
        case .serverError(let code, let message):
            return "Doubao streaming error \(code): \(message)"
        }
    }
}

final class DoubaoStreamingClient {
    // Window to wait for the server to flush remaining finals after our negative-sequence last packet.
    private static let postCloseTimeoutSeconds: UInt64 = 4_000_000_000

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Streams 16 kHz / 16-bit / mono PCM to Doubao (Volcengine SAUC) and returns the assembled transcript.
    func runSession(
        pcm: AsyncStream<Data>,
        apiKey: String,
        baseURL: String,
        resourceId: String,
        language: String
    ) async throws -> StreamingTranscriptResult {
        let trimmedBase = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let endpoint = trimmedBase.isEmpty
            ? "wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_async"
            : trimmedBase

        guard let url = URL(string: endpoint) else {
            throw DoubaoStreamingError.invalidResponse
        }

        let requestId = UUID().uuidString
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "X-Api-Key")
        request.setValue(resourceId, forHTTPHeaderField: "X-Api-Resource-Id")
        request.setValue(requestId, forHTTPHeaderField: "X-Api-Request-Id")
        request.setValue("-1", forHTTPHeaderField: "X-Api-Sequence")
        request.setValue(requestId, forHTTPHeaderField: "X-Api-Connect-Id")

        let task = session.webSocketTask(with: request)
        task.resume()

        let trimmedLanguage = language.trimmingCharacters(in: .whitespacesAndNewlines)
        let collector = DoubaoCollector()
        let startedAt = Date()
        Self.log("connect resource=\(resourceId) language=\(trimmedLanguage.isEmpty ? "auto" : trimmedLanguage) requestId=\(requestId)")

        // Send full client request immediately, before any audio.
        do {
            let initPayload = Self.buildFullClientRequestPayload(language: trimmedLanguage)
            let initFrame = DoubaoFrame.encodeFullClientRequest(json: initPayload)
            try await task.send(.data(initFrame))
            Self.log("full-client-request sent bytes=\(initFrame.count)")
        } catch {
            task.cancel(with: .goingAway, reason: nil)
            throw DoubaoStreamingError.connectionFailed(error.localizedDescription)
        }

        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask { [task] in
                    try await Self.sendPCM(pcm: pcm, task: task, startedAt: startedAt)
                }
                group.addTask { [task] in
                    try await Self.receiveLoop(task: task, collector: collector, startedAt: startedAt)
                }

                // Sender finishes when PCM stream closes + final negative-seq packet sent.
                try await group.next()

                // Give the receive loop a short grace window to drain remaining finals.
                let graceTask = Task { [task] in
                    try? await Task.sleep(nanoseconds: Self.postCloseTimeoutSeconds)
                    task.cancel(with: .goingAway, reason: nil)
                }
                defer { graceTask.cancel() }

                try await group.next()
            }
        } catch is CancellationError {
            task.cancel(with: .goingAway, reason: nil)
            throw CancellationError()
        } catch {
            task.cancel(with: .goingAway, reason: nil)
            throw error
        }

        task.cancel(with: .normalClosure, reason: nil)

        let text = await collector.assembledText()
        let audioSeconds = await collector.totalAudioSeconds()
        Self.log("done audioSeconds=\(String(format: "%.2f", audioSeconds)) transcript=\(text.count) chars")
        Self.logText("doubao.transcript", text)

        guard !text.isEmpty else {
            throw DoubaoStreamingError.emptyTranscript
        }

        return StreamingTranscriptResult(
            text: text,
            model: "bigmodel",
            audioSeconds: audioSeconds,
            cost: 0,
            provider: .doubao
        )
    }

    private static func sendPCM(
        pcm: AsyncStream<Data>,
        task: URLSessionWebSocketTask,
        startedAt: Date
    ) async throws {
        // The full client request implicitly occupies sequence 1 on the server's
        // auto-assigned counter, so the first audio chunk must be 2.
        var sequence: Int32 = 2
        var bytesSent = 0
        var lastChunk: Data? = nil

        for await chunk in pcm {
            try Task.checkCancellation()
            if let pending = lastChunk {
                let frame = DoubaoFrame.encodeAudioChunk(pcm: pending, sequence: sequence, isLast: false)
                try await task.send(.data(frame))
                bytesSent += pending.count
                sequence += 1
            }
            lastChunk = chunk
        }

        // Flush whatever we have buffered as the last (negative-sequence) packet.
        let finalPCM = lastChunk ?? Data()
        let finalSequence = -sequence
        let finalFrame = DoubaoFrame.encodeAudioChunk(pcm: finalPCM, sequence: finalSequence, isLast: true)
        try? await task.send(.data(finalFrame))
        bytesSent += finalPCM.count
        log("pcm stream closed elapsed=\(elapsed(from: startedAt))s sent=\(bytesSent) bytes lastSeq=\(finalSequence)")
    }

    private static func receiveLoop(
        task: URLSessionWebSocketTask,
        collector: DoubaoCollector,
        startedAt: Date
    ) async throws {
        while true {
            try Task.checkCancellation()

            let message: URLSessionWebSocketTask.Message
            do {
                message = try await task.receive()
            } catch {
                let nsError = error as NSError
                log("receive error elapsed=\(elapsed(from: startedAt))s domain=\(nsError.domain) code=\(nsError.code)")
                if nsError.domain == NSURLErrorDomain {
                    return
                }
                if nsError.domain == NSPOSIXErrorDomain, nsError.code == 57 {
                    return
                }
                if await collector.sawLastResponse {
                    return
                }
                throw DoubaoStreamingError.connectionFailed(error.localizedDescription)
            }

            let payload: Data
            switch message {
            case .data(let data):
                payload = data
            case .string(let text):
                payload = Data(text.utf8)
            @unknown default:
                continue
            }

            guard !payload.isEmpty else {
                continue
            }

            let decoded: DoubaoFrame.Decoded
            do {
                decoded = try DoubaoFrame.decode(payload)
            } catch {
                log("decode failed bytes=\(payload.count)")
                continue
            }

            switch decoded {
            case .fullServerResponse(let json, let sequence, let isLast):
                Self.handleServerJSON(json, sequence: sequence, isLast: isLast, collector: collector, startedAt: startedAt)
                if isLast {
                    await collector.markLastResponse()
                    return
                }
            case .error(let code, let message):
                log("server error code=\(code) message=\(message)")
                if code == 45000001 || code == 45000151 {
                    throw DoubaoStreamingError.serverError(code: code, message: message)
                }
                throw DoubaoStreamingError.serverError(code: code, message: message)
            }
        }
    }

    private static func handleServerJSON(
        _ json: Data,
        sequence: Int32?,
        isLast: Bool,
        collector: DoubaoCollector,
        startedAt: Date
    ) {
        guard let envelope = try? JSONDecoder().decode(DoubaoEnvelope.self, from: json) else {
            if let raw = String(data: json, encoding: .utf8) {
                log("response (unparsed) elapsed=\(elapsed(from: startedAt))s payload=\(raw.prefix(200))")
            }
            return
        }

        let text = envelope.result?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let duration = envelope.audio_info?.duration ?? 0
        let seqLabel = sequence.map(String.init) ?? "-"
        let lastLabel = isLast ? " last" : ""
        if !text.isEmpty {
            Task { await collector.updateText(text) }
            log("response elapsed=\(elapsed(from: startedAt))s seq=\(seqLabel)\(lastLabel) duration=\(duration)ms text=\(text)")
        } else {
            log("response elapsed=\(elapsed(from: startedAt))s seq=\(seqLabel)\(lastLabel) duration=\(duration)ms (no text)")
        }
        if duration > 0 {
            Task { await collector.updateDurationMs(duration) }
        }
    }

    fileprivate static func buildFullClientRequestPayload(language: String) -> Data {
        var audio: [String: Any] = [
            "format": "pcm",
            "codec": "raw",
            "rate": 16000,
            "bits": 16,
            "channel": 1
        ]
        if !language.isEmpty {
            audio["language"] = language
        }

        let body: [String: Any] = [
            "user": [
                "uid": AppMetadata.displayName
            ],
            "audio": audio,
            "request": [
                "model_name": "bigmodel",
                "enable_punc": true,
                "enable_itn": true,
                "show_utterances": true
            ]
        ]

        return (try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])) ?? Data()
    }

    private static func log(_ message: String) {
        DictationLogger.shared.log("doubao", message)
    }

    private static func logText(_ tag: String, _ text: String) {
        DictationLogger.shared.logText(tag, text)
    }

    private static func elapsed(from date: Date) -> String {
        String(format: "%.2f", Date().timeIntervalSince(date))
    }
}

// MARK: - Frame encoding/decoding

private enum DoubaoFrame {
    enum Decoded {
        case fullServerResponse(json: Data, sequence: Int32?, isLast: Bool)
        case error(code: UInt32, message: String)
    }

    // Header layout (4 bytes total):
    //   byte 0: (version << 4) | header_size                       — fixed 0x11 (version=1, header_size=1 = 4 bytes)
    //   byte 1: (message_type << 4) | message_type_specific_flags
    //   byte 2: (serialization << 4) | compression
    //   byte 3: reserved (0x00)

    static func encodeFullClientRequest(json: Data) -> Data {
        var out = Data()
        out.append(0x11)
        // msg_type=0b0001 (full client request), flags=0b0000 (no sequence)
        out.append((0b0001 << 4) | 0b0000)
        // serialization=0b0001 (JSON), compression=0b0000 (none)
        out.append((0b0001 << 4) | 0b0000)
        out.append(0x00)
        out.append(contentsOf: UInt32(json.count).bigEndianBytes)
        out.append(json)
        return out
    }

    static func encodeAudioChunk(pcm: Data, sequence: Int32, isLast: Bool) -> Data {
        var out = Data()
        out.append(0x11)
        let flags: UInt8 = isLast ? 0b0011 : 0b0001
        // msg_type=0b0010 (audio only), serialization=0b0000 (none), compression=0b0000 (none)
        out.append((0b0010 << 4) | flags)
        out.append((0b0000 << 4) | 0b0000)
        out.append(0x00)
        out.append(contentsOf: UInt32(bitPattern: sequence).bigEndianBytes)
        out.append(contentsOf: UInt32(pcm.count).bigEndianBytes)
        out.append(pcm)
        return out
    }

    static func decode(_ data: Data) throws -> Decoded {
        guard data.count >= 4 else {
            throw DoubaoStreamingError.invalidResponse
        }
        let version = data[0] >> 4
        let headerSize = data[0] & 0x0F
        guard version == 1, headerSize >= 1 else {
            throw DoubaoStreamingError.invalidResponse
        }
        let msgType = data[1] >> 4
        let flags = data[1] & 0x0F
        let compression = data[2] & 0x0F
        let headerLength = Int(headerSize) * 4
        var offset = headerLength
        guard offset <= data.count else {
            throw DoubaoStreamingError.invalidResponse
        }

        switch msgType {
        case 0b1001:
            // full server response
            var sequence: Int32? = nil
            if flags & 0b0001 != 0 {
                guard data.count >= offset + 4 else {
                    throw DoubaoStreamingError.invalidResponse
                }
                let raw = readUInt32(data, at: offset)
                sequence = Int32(bitPattern: raw)
                offset += 4
            }
            let isLast = (flags & 0b0010) != 0

            guard data.count >= offset + 4 else {
                throw DoubaoStreamingError.invalidResponse
            }
            let payloadSize = Int(readUInt32(data, at: offset))
            offset += 4
            guard data.count >= offset + payloadSize else {
                throw DoubaoStreamingError.invalidResponse
            }
            let payload = data.subdata(in: offset..<(offset + payloadSize))
            let json = compression == 0b0001 ? try Gzip.decompress(payload) : payload
            return .fullServerResponse(json: json, sequence: sequence, isLast: isLast)

        case 0b1111:
            // error frame: errorCode (4) + messageSize (4) + message
            guard data.count >= offset + 8 else {
                throw DoubaoStreamingError.invalidResponse
            }
            let code = readUInt32(data, at: offset)
            offset += 4
            let messageSize = Int(readUInt32(data, at: offset))
            offset += 4
            guard data.count >= offset + messageSize else {
                throw DoubaoStreamingError.invalidResponse
            }
            let raw = data.subdata(in: offset..<(offset + messageSize))
            let messageData = compression == 0b0001 ? (try? Gzip.decompress(raw)) ?? raw : raw
            let text = String(data: messageData, encoding: .utf8) ?? "<binary>"
            return .error(code: code, message: text)

        default:
            throw DoubaoStreamingError.invalidResponse
        }
    }

    private static func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        let b0 = UInt32(data[offset])
        let b1 = UInt32(data[offset + 1])
        let b2 = UInt32(data[offset + 2])
        let b3 = UInt32(data[offset + 3])
        return (b0 << 24) | (b1 << 16) | (b2 << 8) | b3
    }
}

// MARK: - Gzip via Compression framework + manual wrapper

private enum Gzip {
    static func decompress(_ data: Data) throws -> Data {
        let deflated = try stripGzipWrapper(data)
        return try inflate(deflated)
    }

    private static func stripGzipWrapper(_ data: Data) throws -> Data {
        // Minimum gzip envelope is 18 bytes (10-byte header + 8-byte trailer).
        guard data.count >= 18,
              data[0] == 0x1F,
              data[1] == 0x8B,
              data[2] == 0x08 else {
            throw DoubaoStreamingError.invalidResponse
        }
        let flg = data[3]
        var offset = 10

        if flg & 0x04 != 0 { // FEXTRA
            guard data.count > offset + 1 else {
                throw DoubaoStreamingError.invalidResponse
            }
            let xlen = Int(data[offset]) | (Int(data[offset + 1]) << 8)
            offset += 2 + xlen
        }
        if flg & 0x08 != 0 { // FNAME
            while offset < data.count, data[offset] != 0 {
                offset += 1
            }
            offset += 1
        }
        if flg & 0x10 != 0 { // FCOMMENT
            while offset < data.count, data[offset] != 0 {
                offset += 1
            }
            offset += 1
        }
        if flg & 0x02 != 0 { // FHCRC
            offset += 2
        }
        let deflatedEnd = data.count - 8
        guard deflatedEnd > offset else {
            throw DoubaoStreamingError.invalidResponse
        }
        return data.subdata(in: offset..<deflatedEnd)
    }

    private static func inflate(_ data: Data) throws -> Data {
        let maxOut = max(data.count * 64, 1 << 16)
        return try data.withUnsafeBytes { src -> Data in
            guard let srcAddr = src.bindMemory(to: UInt8.self).baseAddress else {
                throw DoubaoStreamingError.invalidResponse
            }
            let dst = UnsafeMutablePointer<UInt8>.allocate(capacity: maxOut)
            defer { dst.deallocate() }
            let written = compression_decode_buffer(
                dst,
                maxOut,
                srcAddr,
                data.count,
                nil,
                COMPRESSION_ZLIB
            )
            guard written > 0 else {
                throw DoubaoStreamingError.invalidResponse
            }
            return Data(bytes: dst, count: written)
        }
    }
}

// MARK: - Collector

private actor DoubaoCollector {
    private var latestText: String = ""
    private var durationMs: Int = 0
    private(set) var sawLastResponse = false

    func updateText(_ text: String) {
        latestText = text
    }

    func updateDurationMs(_ ms: Int) {
        if ms > durationMs {
            durationMs = ms
        }
    }

    func markLastResponse() {
        sawLastResponse = true
    }

    func assembledText() -> String {
        latestText
    }

    func totalAudioSeconds() -> Double {
        Double(durationMs) / 1000.0
    }
}

// MARK: - Server payload model

private struct DoubaoEnvelope: Decodable {
    let result: ResultBody?
    let audio_info: AudioInfo?

    struct ResultBody: Decodable {
        let text: String?
    }

    struct AudioInfo: Decodable {
        let duration: Int?
    }
}

// MARK: - Helpers

private extension UInt32 {
    var bigEndianBytes: [UInt8] {
        [
            UInt8((self >> 24) & 0xFF),
            UInt8((self >> 16) & 0xFF),
            UInt8((self >> 8) & 0xFF),
            UInt8(self & 0xFF)
        ]
    }
}
