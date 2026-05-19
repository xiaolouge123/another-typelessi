import Foundation

enum ElevenLabsClientError: LocalizedError {
    case invalidResponse
    case emptyTranscription
    case apiError(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "ElevenLabs returned an invalid response."
        case .emptyTranscription:
            return "ElevenLabs returned an empty transcription."
        case .apiError(let statusCode, let message):
            return "ElevenLabs API error \(statusCode): \(message)"
        }
    }
}

struct ElevenLabsTranscriptResult {
    let text: String
    let model: String
    let languageCode: String?
}

final class ElevenLabsClient {
    // ElevenLabs Scribe published pay-as-you-go rate ($0.40 per audio hour),
    // used as a rough client-side cost estimate since the API does not echo
    // billing in the response.
    static let pricePerHourUSD = 0.40

    static func estimatedCost(audioSeconds: Double) -> Double {
        guard audioSeconds > 0 else { return 0 }
        return (audioSeconds / 3600.0) * pricePerHourUSD
    }

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Uploads the WAV at audioURL to /v1/speech-to-text and returns the transcript.
    /// `language` is an ISO-639-1/-3 code. Pass nil/empty to let ElevenLabs auto-detect.
    func transcribe(
        audioURL: URL,
        baseURL: URL,
        model: String,
        language: String,
        apiKey: String
    ) async throws -> ElevenLabsTranscriptResult {
        let endpoint = baseURL.appendingPathComponent("v1/speech-to-text")
        let boundary = "Boundary-\(UUID().uuidString)"
        let trimmedLanguage = language.trimmingCharacters(in: .whitespacesAndNewlines)

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let audioData = try Data(contentsOf: audioURL)
        var body = Data()

        body.appendFormField(boundary: boundary, name: "model_id", value: model)
        if !trimmedLanguage.isEmpty {
            body.appendFormField(boundary: boundary, name: "language_code", value: trimmedLanguage)
        }
        body.appendFileField(
            boundary: boundary,
            name: "file",
            filename: audioURL.lastPathComponent,
            contentType: "audio/wav",
            data: audioData
        )
        body.append("--\(boundary)--\r\n")

        request.httpBody = body

        DictationLogger.shared.log(
            "elevenlabs",
            "request endpoint=\(endpoint.absoluteString) model=\(model) language=\(trimmedLanguage.isEmpty ? "auto" : trimmedLanguage) bytes=\(audioData.count)"
        )

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ElevenLabsClientError.invalidResponse
        }

        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "no body"
            DictationLogger.shared.log("elevenlabs", "error status=\(http.statusCode) body=\(message.prefix(500))")
            throw ElevenLabsClientError.apiError(statusCode: http.statusCode, message: message)
        }

        let decoded = try JSONDecoder().decode(TranscriptionResponse.self, from: data)
        let text = decoded.text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty else {
            throw ElevenLabsClientError.emptyTranscription
        }

        DictationLogger.shared.logText("elevenlabs.transcript", text)

        return ElevenLabsTranscriptResult(
            text: text,
            model: model,
            languageCode: decoded.languageCode
        )
    }

    private struct TranscriptionResponse: Decodable {
        let text: String
        let languageCode: String?

        enum CodingKeys: String, CodingKey {
            case text
            case languageCode = "language_code"
        }
    }
}

private extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }

    mutating func appendFormField(boundary: String, name: String, value: String) {
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        append("\(value)\r\n")
    }

    mutating func appendFileField(
        boundary: String,
        name: String,
        filename: String,
        contentType: String,
        data fileData: Data
    ) {
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n")
        append("Content-Type: \(contentType)\r\n\r\n")
        append(fileData)
        append("\r\n")
    }
}
