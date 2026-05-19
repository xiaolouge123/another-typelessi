import Foundation

enum ElevenLabsStreamingError: LocalizedError {
    case invalidResponse
    case connectionFailed(String)
    case authenticationFailed(String)
    case emptyTranscript
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "ElevenLabs Realtime returned an unexpected response."
        case .connectionFailed(let detail):
            return "Could not connect to ElevenLabs Realtime: \(detail)"
        case .authenticationFailed(let detail):
            return "ElevenLabs Realtime rejected the API key: \(detail)"
        case .emptyTranscript:
            return "ElevenLabs Realtime returned an empty transcript."
        case .serverError(let detail):
            return "ElevenLabs Realtime streaming error: \(detail)"
        }
    }
}

final class ElevenLabsStreamingClient {
    // Window we wait for the server to flush its remaining committed segments
    // after we send the final commit message.
    private static let postCommitTimeoutSeconds: UInt64 = 4_000_000_000

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Streams 16 kHz / 16-bit / mono PCM to ElevenLabs Scribe Realtime and returns the assembled transcript.
    func runSession(
        pcm: AsyncStream<Data>,
        apiKey: String,
        baseURL: String,
        model: String,
        language: String
    ) async throws -> StreamingTranscriptResult {
        let trimmedBase = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let endpoint = trimmedBase.isEmpty ? "wss://api.elevenlabs.io/v1/speech-to-text/realtime" : trimmedBase
        guard var components = URLComponents(string: endpoint) else {
            throw ElevenLabsStreamingError.invalidResponse
        }

        var query = components.queryItems ?? []
        query.append(URLQueryItem(name: "model_id", value: model))
        let trimmedLanguage = language.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedLanguage.isEmpty {
            query.append(URLQueryItem(name: "language_code", value: trimmedLanguage))
        }
        components.queryItems = query

        guard let url = components.url else {
            throw ElevenLabsStreamingError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")

        let task = session.webSocketTask(with: request)
        task.resume()

        let collector = ScribeCollector()
        let startedAt = Date()
        Self.log("connect model=\(model) language=\(trimmedLanguage.isEmpty ? "auto" : trimmedLanguage)")

        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask { [task] in
                    try await Self.sendPCM(pcm: pcm, task: task, collector: collector, startedAt: startedAt)
                }
                group.addTask { [task] in
                    try await Self.receiveLoop(task: task, collector: collector, startedAt: startedAt)
                }

                // Wait for sender to finish (PCM stream closed + commit sent).
                try await group.next()

                // Then give the receive loop a short window to drain final committed transcripts.
                let graceTask = Task { [task] in
                    try? await Task.sleep(nanoseconds: Self.postCommitTimeoutSeconds)
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
        Self.logText("elevenlabs.realtime.transcript", text)

        guard !text.isEmpty else {
            throw ElevenLabsStreamingError.emptyTranscript
        }

        return StreamingTranscriptResult(
            text: text,
            model: model,
            audioSeconds: audioSeconds,
            cost: ElevenLabsClient.estimatedCost(audioSeconds: audioSeconds),
            provider: .elevenLabs
        )
    }

    private static func sendPCM(
        pcm: AsyncStream<Data>,
        task: URLSessionWebSocketTask,
        collector: ScribeCollector,
        startedAt: Date
    ) async throws {
        var bytesSent = 0
        for await chunk in pcm {
            try Task.checkCancellation()

            let payload: [String: Any] = [
                "message_type": "input_audio_chunk",
                "audio_base_64": chunk.base64EncodedString(),
                "commit": false,
                "sample_rate": 16000
            ]
            let data = try JSONSerialization.data(withJSONObject: payload, options: [])
            guard let message = String(data: data, encoding: .utf8) else {
                throw ElevenLabsStreamingError.invalidResponse
            }
            try await task.send(.string(message))
            bytesSent += chunk.count
            await collector.recordSentBytes(chunk.count)
        }
        log("pcm stream closed elapsed=\(elapsed(from: startedAt))s sent=\(bytesSent) bytes")

        // Final commit: empty audio + commit=true to flush the last segment.
        let finalPayload: [String: Any] = [
            "message_type": "input_audio_chunk",
            "audio_base_64": "",
            "commit": true,
            "sample_rate": 16000
        ]
        if let data = try? JSONSerialization.data(withJSONObject: finalPayload),
           let message = String(data: data, encoding: .utf8) {
            try? await task.send(.string(message))
            log("commit sent elapsed=\(elapsed(from: startedAt))s")
        }
    }

    private static func receiveLoop(
        task: URLSessionWebSocketTask,
        collector: ScribeCollector,
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
                if await collector.committedClosed {
                    return
                }
                throw ElevenLabsStreamingError.connectionFailed(error.localizedDescription)
            }

            let payload: Data
            switch message {
            case .string(let text):
                payload = Data(text.utf8)
            case .data(let data):
                payload = data
            @unknown default:
                continue
            }

            guard !payload.isEmpty,
                  let envelope = try? JSONDecoder().decode(ScribeEnvelope.self, from: payload) else {
                continue
            }

            switch envelope.message_type {
            case "session_started":
                log("session_started elapsed=\(elapsed(from: startedAt))s")
            case "partial_transcript":
                if let text = envelope.text, !text.isEmpty {
                    log("partial elapsed=\(elapsed(from: startedAt))s text=\(text)")
                }
            case "committed_transcript":
                if let text = envelope.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                    await collector.appendCommitted(text)
                    if let endMs = envelope.end_time_ms {
                        await collector.recordEndTime(endMs)
                    }
                    log("committed elapsed=\(elapsed(from: startedAt))s text=\(text)")
                }
            case "committed_transcript_with_timestamps":
                // We already captured the committed text on the prior committed_transcript event;
                // this variant is informational. It also indicates the segment fully drained.
                await collector.markCommittedClosed()
                log("committed_with_timestamps elapsed=\(elapsed(from: startedAt))s")
            case "input_error", "error":
                let detail = envelope.message ?? envelope.text ?? "unknown"
                throw ElevenLabsStreamingError.serverError(detail)
            default:
                continue
            }
        }
    }

    private static func log(_ message: String) {
        DictationLogger.shared.log("elevenlabs.realtime", message)
    }

    private static func logText(_ tag: String, _ text: String) {
        DictationLogger.shared.logText(tag, text)
    }

    private static func elapsed(from date: Date) -> String {
        String(format: "%.2f", Date().timeIntervalSince(date))
    }
}

private actor ScribeCollector {
    // Audio is sent as 16 kHz / 16-bit / mono PCM, so byte count maps directly to seconds.
    private static let bytesPerSecond: Double = 16_000 * 2

    private var committedSegments: [String] = []
    private var maxEndTimeMs: Int = 0
    private var bytesSent: Int = 0
    private(set) var committedClosed = false

    func appendCommitted(_ text: String) {
        committedSegments.append(text)
    }

    func recordEndTime(_ ms: Int) {
        maxEndTimeMs = max(maxEndTimeMs, ms)
    }

    func recordSentBytes(_ count: Int) {
        bytesSent += count
    }

    func markCommittedClosed() {
        committedClosed = true
    }

    func assembledText() -> String {
        committedSegments.joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func totalAudioSeconds() -> Double {
        // Prefer the server-reported timestamp, fall back to locally-measured PCM
        // so usage accounting still works if the timestamp event never arrives
        // (e.g. early disconnect).
        let serverSeconds = Double(maxEndTimeMs) / 1000.0
        if serverSeconds > 0 {
            return serverSeconds
        }
        return Double(bytesSent) / Self.bytesPerSecond
    }
}

private struct ScribeEnvelope: Decodable {
    let message_type: String
    let text: String?
    let end_time_ms: Int?
    let message: String?
}
