import Foundation

struct DeepgramTranscriptResult {
    let text: String
    let model: String
    let audioSeconds: Double
    let cost: Double
}

enum DeepgramStreamingError: LocalizedError {
    case invalidResponse
    case connectionFailed(String)
    case authenticationFailed(String)
    case emptyTranscript
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Deepgram returned an unexpected response."
        case .connectionFailed(let detail):
            return "Could not connect to Deepgram: \(detail)"
        case .authenticationFailed(let detail):
            return "Deepgram rejected the API key: \(detail)"
        case .emptyTranscript:
            return "Deepgram returned an empty transcript."
        case .serverError(let detail):
            return "Deepgram streaming error: \(detail)"
        }
    }
}

final class DeepgramStreamingClient {
    // Deepgram's published Nova-3 multilingual streaming rate, used as a rough
    // client-side estimate since the server does not echo cost in the ws stream.
    private static let pricePerMinuteUSD = 0.0058

    // Cap how long we wait for Deepgram to flush finals after CloseStream.
    // In practice the last final + Metadata arrive within a few hundred ms;
    // anything beyond this window is almost always the peer sitting on the
    // socket instead of closing it, and we already have an interim we can use.
    private static let postCloseTimeoutSeconds: UInt64 = 2_000_000_000

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func runSession(
        pcm: AsyncStream<Data>,
        apiKey: String,
        model: String,
        language: RecognitionLanguage
    ) async throws -> DeepgramTranscriptResult {
        var components = URLComponents(string: "wss://api.deepgram.com/v1/listen")!
        components.queryItems = [
            URLQueryItem(name: "encoding", value: "linear16"),
            URLQueryItem(name: "sample_rate", value: "16000"),
            URLQueryItem(name: "channels", value: "1"),
            URLQueryItem(name: "model", value: model),
            URLQueryItem(name: "smart_format", value: "true"),
            URLQueryItem(name: "interim_results", value: "true"),
            URLQueryItem(name: "endpointing", value: "300"),
            URLQueryItem(name: "language", value: language.deepgramLanguageCode)
        ]

        guard let url = components.url else {
            throw DeepgramStreamingError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")

        let task = session.webSocketTask(with: request)
        task.resume()

        let collector = TranscriptCollector()
        let startedAt = Date()
        Self.log("connect model=\(model) language=\(language.deepgramLanguageCode)")

        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask { [task] in
                    try await Self.sendPCM(pcm: pcm, task: task, startedAt: startedAt)
                }
                group.addTask { [task] in
                    try await Self.receiveLoop(task: task, collector: collector, startedAt: startedAt)
                }

                // Wait for sendPCM to complete first (user released Fn, CloseStream sent).
                // Then give receiveLoop a short grace window to pick up the final frames
                // plus the Metadata envelope, and force-close the socket so it can't
                // hold us hostage.
                try await group.next()

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
        let audioSeconds = await collector.totalDurationSeconds()
        let resolvedModel = await collector.resolvedModel() ?? model
        Self.log("done audioSeconds=\(String(format: "%.2f", audioSeconds)) transcript=\(text.count) chars")
        Self.logText("deepgram.transcript", text)

        guard !text.isEmpty else {
            throw DeepgramStreamingError.emptyTranscript
        }

        let cost = audioSeconds > 0
            ? (audioSeconds / 60.0) * Self.pricePerMinuteUSD
            : 0

        return DeepgramTranscriptResult(
            text: text,
            model: resolvedModel,
            audioSeconds: audioSeconds,
            cost: cost
        )
    }

    private static func sendPCM(
        pcm: AsyncStream<Data>,
        task: URLSessionWebSocketTask,
        startedAt: Date
    ) async throws {
        var bytesSent = 0
        for await chunk in pcm {
            try Task.checkCancellation()
            try await task.send(.data(chunk))
            bytesSent += chunk.count
        }
        log("pcm stream closed elapsed=\(elapsed(from: startedAt))s sent=\(bytesSent) bytes")
        // Deepgram treats a CloseStream control message as "flush buffered audio
        // and send the remaining final transcripts". We send it when the user
        // releases Fn and the PCM AsyncStream finishes.
        let closePayload = "{\"type\":\"CloseStream\"}"
        try? await task.send(.string(closePayload))
        log("CloseStream sent elapsed=\(elapsed(from: startedAt))s")
    }

    private static func receiveLoop(
        task: URLSessionWebSocketTask,
        collector: TranscriptCollector,
        startedAt: Date
    ) async throws {
        while true {
            try Task.checkCancellation()

            let message: URLSessionWebSocketTask.Message
            do {
                message = try await task.receive()
            } catch {
                // The peer closing after a CloseStream surfaces as a receive
                // error; treat it as a clean end of stream.
                let nsError = error as NSError
                log("receive error elapsed=\(elapsed(from: startedAt))s domain=\(nsError.domain) code=\(nsError.code)")
                if nsError.domain == NSURLErrorDomain {
                    return
                }
                if nsError.domain == NSPOSIXErrorDomain,
                   nsError.code == 57 { // ENOTCONN
                    return
                }
                if await collector.hasReceivedClose {
                    return
                }
                throw DeepgramStreamingError.connectionFailed(error.localizedDescription)
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
                  let envelope = try? JSONDecoder().decode(DeepgramEnvelope.self, from: payload) else {
                continue
            }

            switch envelope.type {
            case "Results":
                let transcript = envelope.channel?.alternatives?.first?.transcript ?? ""
                let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    let isFinal = envelope.isFinal ?? false
                    await collector.upsertSegment(
                        text: trimmed,
                        start: envelope.start ?? 0,
                        isFinal: isFinal
                    )
                    let tag = isFinal ? "final  " : "interim"
                    log("result elapsed=\(elapsed(from: startedAt))s start=\(String(format: "%.2f", envelope.start ?? 0)) \(tag) text=\(trimmed)")
                }
            case "Metadata":
                if let duration = envelope.duration {
                    await collector.recordTotalDuration(duration)
                }
                if let model = envelope.model {
                    await collector.recordModel(model)
                }
                log("metadata elapsed=\(elapsed(from: startedAt))s duration=\(envelope.duration ?? 0)")
            case "SpeechStarted", "UtteranceEnd":
                continue
            case "Error":
                throw DeepgramStreamingError.serverError(envelope.description ?? envelope.reason ?? "unknown")
            case "Close":
                await collector.markClosed()
                log("close envelope elapsed=\(elapsed(from: startedAt))s")
                return
            default:
                continue
            }
        }
    }

    private static func log(_ message: String) {
        DictationLogger.shared.log("deepgram", message)
    }

    private static func logText(_ tag: String, _ text: String) {
        DictationLogger.shared.logText(tag, text)
    }

    private static func elapsed(from date: Date) -> String {
        String(format: "%.2f", Date().timeIntervalSince(date))
    }
}

private actor TranscriptCollector {
    // Keyed by the `start` timestamp Deepgram reports for each result envelope.
    // Interim results for the same start keep overwriting until a final
    // arrives; finals are locked in and can't be clobbered by late interims.
    private var segments: [Double: Segment] = [:]
    private var totalDuration: Double = 0
    private var model: String?
    private(set) var hasReceivedClose = false

    private struct Segment {
        let start: Double
        let text: String
        let isFinal: Bool
    }

    func upsertSegment(text: String, start: Double, isFinal: Bool) {
        if let existing = segments[start], existing.isFinal, !isFinal {
            return
        }
        segments[start] = Segment(start: start, text: text, isFinal: isFinal)
    }

    func recordTotalDuration(_ duration: Double) {
        totalDuration = max(totalDuration, duration)
    }

    func recordModel(_ model: String) {
        self.model = model
    }

    func markClosed() {
        hasReceivedClose = true
    }

    func assembledText() -> String {
        segments.values
            .sorted { $0.start < $1.start }
            .map(\.text)
            .joined(separator: " ")
    }

    func totalDurationSeconds() -> Double {
        totalDuration
    }

    func resolvedModel() -> String? {
        model
    }
}

private struct DeepgramEnvelope: Decodable {
    let type: String
    let channel: Channel?
    let isFinal: Bool?
    let start: Double?
    let duration: Double?
    let model: String?
    let description: String?
    let reason: String?

    struct Channel: Decodable {
        let alternatives: [Alternative]?
    }

    struct Alternative: Decodable {
        let transcript: String?
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case channel
        case isFinal = "is_final"
        case start
        case duration
        case model
        case description
        case reason
    }
}
