import Foundation

final class OpenRouterClient {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func transcribe(
        audioURL: URL,
        language: String,
        baseURL: URL,
        transcriptionModel: String,
        apiKey: String
    ) async throws -> OpenRouterTextResult {
        let audioData = try Data(contentsOf: audioURL)

        // Only include language if it's not empty
        let languageCode = language.trimmingCharacters(in: .whitespacesAndNewlines)

        let requestBody = TranscriptionRequest(
            model: transcriptionModel,
            language: languageCode.isEmpty ? nil : languageCode,
            inputAudio: InputAudio(
                data: audioData.base64EncodedString(),
                format: "wav"
            )
        )

        var request = URLRequest(url: baseURL.appendingPathComponent("audio/transcriptions"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addOpenRouterHeaders(to: &request, apiKey: apiKey)
        request.httpBody = try JSONEncoder.openRouter.encode(requestBody)

        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)

        let decoded = try JSONDecoder().decode(TranscriptionResponse.self, from: data)
        let text = decoded.text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty else {
            throw OpenRouterClientError.emptyTranscription
        }

        return OpenRouterTextResult(
            text: text,
            model: decoded.model ?? transcriptionModel,
            usage: decoded.usage
        )
    }

    func formalize(
        text: String,
        language: RecognitionLanguage,
        baseURL: URL,
        polishModel: String,
        apiKey: String,
        correctionContext: [CorrectionRecord] = []
    ) async throws -> OpenRouterTextResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return OpenRouterTextResult(text: "", model: polishModel, usage: nil)
        }

        // Build correction context if available
        let contextSection: String
        if !correctionContext.isEmpty {
            let examples = correctionContext.suffix(20).map { record in
                "  \"\(record.asrOutput)\" → \"\(record.userCorrected)\""
            }.joined(separator: "\n")

            contextSection = """


            The user has previously corrected these speech recognition errors:
            \(examples)

            Use these corrections as reference to fix similar errors in the current transcript.
            Pay special attention to:
            - Technical terms and proper nouns that were corrected
            - Common homophones and near-sounding words
            - Capitalization and formatting patterns
            """
        } else {
            contextSection = ""
        }

        let requestBody = ChatCompletionRequest(
            model: polishModel,
            temperature: 0.2,
            messages: [
                ChatMessage(
                    role: "system",
                    content: """
                    You are an editor for dictated text that will be inserted directly into the user's active app.
                    Preserve the original meaning, names, numbers, language, and intent.
                    Never translate the text into another language.
                    If the transcript is English, return English. If it is Chinese, return Chinese.
                    If the transcript mixes languages, preserve the same mixed-language structure.
                    Remove speech disfluencies, repair punctuation, and make the writing clear, formal, and useful as written text.

                    Correct likely speech-recognition errors when the surrounding context strongly indicates the intended word or phrase.
                    Examples include homophones, near-sounding words, broken product or API names, obvious word-boundary errors, and punctuation caused by dictation artifacts.
                    Prefer the correction that best fits the local sentence and the transcript's topic.
                    If a term, name, number, or factual claim is ambiguous, preserve the transcript instead of guessing.
                    Do not fact-check the user's claims against outside knowledge, and do not replace a stated fact just because it might be wrong.

                    Spoken dictation can have reversed, interrupted, or scattered word order.
                    You may reorder clauses and sentences to make the writing coherent and natural, as long as the original meaning, emphasis, and intent are preserved.
                    Move context before conclusions when that improves readability, merge fragmented clauses, and remove repeated detours caused by self-correction.
                    Keep the user's level of certainty; do not turn tentative wording into definitive claims.

                    Be proactive about structure when the transcript contains multiple ideas:
                    - Group related points together.
                    - Add numbered lists when the user implies ordered points, steps, reasons, requirements, or options.
                    - Add bullet lists when the user gives parallel items but no explicit order.
                    - Split long text into readable paragraphs.
                    - Use line breaks, indentation, and spacing to make the result easy to scan.
                    - Keep short one-sentence input as one sentence.
                    - Do not add facts, examples, or conclusions the user did not say.

                    Return only the final polished text, with no explanation.
                    """
                ),
                ChatMessage(
                    role: "user",
                    content: """
                    Language mode: \(language.title)
                    Do not translate. Polish in the transcript's original language.
                    Use the full transcript context to fix likely speech-recognition mistakes, but only when the intended wording is strongly implied.
                    Reorder scattered spoken phrasing into clearer written order without changing the user's meaning.
                    If the transcript naturally contains several points, organize them into a cleaner written format.\(contextSection)

                    Transcript:
                    \(trimmed)
                    """
                )
            ]
        )

        var request = URLRequest(url: baseURL.appendingPathComponent("chat/completions"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addOpenRouterHeaders(to: &request, apiKey: apiKey)
        request.httpBody = try JSONEncoder.openRouter.encode(requestBody)

        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)

        let decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)

        guard let content = decoded.choices.first?.message.content?.trimmingCharacters(in: .whitespacesAndNewlines),
              !content.isEmpty else {
            throw OpenRouterClientError.emptyFormalization
        }

        return OpenRouterTextResult(
            text: content,
            model: decoded.model ?? polishModel,
            usage: decoded.usage
        )
    }

    private func addOpenRouterHeaders(to request: inout URLRequest, apiKey: String) {
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(AppMetadata.displayName, forHTTPHeaderField: "X-Title")
        request.setValue(AppMetadata.openRouterReferer, forHTTPHeaderField: "HTTP-Referer")
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenRouterClientError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            if let errorResponse = try? JSONDecoder().decode(OpenRouterErrorResponse.self, from: data),
               let message = errorResponse.error?.message {
                throw OpenRouterClientError.apiError(statusCode: httpResponse.statusCode, message: message)
            }

            let fallback = String(data: data, encoding: .utf8) ?? "No response body"
            throw OpenRouterClientError.apiError(statusCode: httpResponse.statusCode, message: fallback)
        }
    }
}

enum OpenRouterClientError: LocalizedError {
    case invalidResponse
    case emptyTranscription
    case emptyFormalization
    case apiError(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "OpenRouter returned an invalid response."
        case .emptyTranscription:
            return "OpenRouter returned an empty transcription."
        case .emptyFormalization:
            return "OpenRouter returned an empty polished result."
        case .apiError(let statusCode, let message):
            return "OpenRouter API error \(statusCode): \(message)"
        }
    }
}

private struct TranscriptionRequest: Encodable {
    let model: String
    let language: String?
    let inputAudio: InputAudio

    enum CodingKeys: String, CodingKey {
        case model
        case language
        case inputAudio = "input_audio"
    }
}

private struct InputAudio: Encodable {
    let data: String
    let format: String
}

private struct TranscriptionResponse: Decodable {
    let text: String
    let usage: OpenRouterUsage?
    let model: String?
}

private struct ChatCompletionRequest: Encodable {
    let model: String
    let temperature: Double
    let messages: [ChatMessage]
}

private struct ChatMessage: Codable {
    let role: String
    let content: String?
}

private struct ChatCompletionResponse: Decodable {
    let choices: [ChatChoice]
    let usage: OpenRouterUsage?
    let model: String?
}

private struct ChatChoice: Decodable {
    let message: ChatMessage
}

private struct OpenRouterErrorResponse: Decodable {
    let error: OpenRouterError?
}

struct OpenRouterTextResult {
    let text: String
    let model: String
    let usage: OpenRouterUsage?
}

struct OpenRouterUsage: Codable {
    let promptTokens: Int
    let completionTokens: Int
    let totalTokens: Int
    let audioTokens: Int
    let cost: Double

    init(promptTokens: Int, completionTokens: Int, totalTokens: Int, audioTokens: Int, cost: Double) {
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.totalTokens = totalTokens
        self.audioTokens = audioTokens
        self.cost = cost
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let promptTokens = Self.decodeInt(
            from: container,
            keys: [.promptTokens, .inputTokens]
        ) ?? 0
        let completionTokens = Self.decodeInt(
            from: container,
            keys: [.completionTokens, .outputTokens]
        ) ?? 0
        let totalTokens = Self.decodeInt(
            from: container,
            keys: [.totalTokens]
        ) ?? (promptTokens + completionTokens)

        let promptDetails = try? container.decodeIfPresent(TokenDetails.self, forKey: .promptTokensDetails)
        let completionDetails = try? container.decodeIfPresent(TokenDetails.self, forKey: .completionTokensDetails)
        let audioTokens = Self.decodeInt(
            from: container,
            keys: [.audioTokens]
        ) ?? ((promptDetails?.audioTokens ?? 0) + (completionDetails?.audioTokens ?? 0))
        let cost = Self.decodeDouble(from: container, keys: [.cost]) ?? 0

        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.totalTokens = totalTokens
        self.audioTokens = audioTokens
        self.cost = cost
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(promptTokens, forKey: .promptTokens)
        try container.encode(completionTokens, forKey: .completionTokens)
        try container.encode(totalTokens, forKey: .totalTokens)
        try container.encode(audioTokens, forKey: .audioTokens)
        try container.encode(cost, forKey: .cost)
    }

    private static func decodeInt<Key: CodingKey>(from container: KeyedDecodingContainer<Key>, keys: [Key]) -> Int? {
        for key in keys {
            if let value = try? container.decodeIfPresent(Int.self, forKey: key) {
                return value
            }

            if let stringValue = try? container.decodeIfPresent(String.self, forKey: key),
               let value = Int(stringValue) {
                return value
            }
        }

        return nil
    }

    private static func decodeDouble<Key: CodingKey>(from container: KeyedDecodingContainer<Key>, keys: [Key]) -> Double? {
        for key in keys {
            if let value = try? container.decodeIfPresent(Double.self, forKey: key) {
                return value
            }

            if let stringValue = try? container.decodeIfPresent(String.self, forKey: key),
               let value = Double(stringValue) {
                return value
            }
        }

        return nil
    }

    private enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
        case audioTokens = "audio_tokens"
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case promptTokensDetails = "prompt_tokens_details"
        case completionTokensDetails = "completion_tokens_details"
        case cost
    }

    private struct TokenDetails: Decodable {
        let audioTokens: Int

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            audioTokens = OpenRouterUsage.decodeInt(from: container, keys: [.audioTokens]) ?? 0
        }

        private enum CodingKeys: String, CodingKey {
            case audioTokens = "audio_tokens"
        }
    }
}

private struct OpenRouterError: Decodable {
    let message: String?
}

private extension JSONEncoder {
    static var openRouter: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        return encoder
    }
}
