import Foundation

public enum ThinkingLevel: String, CaseIterable, Sendable {
    case minimal, low, medium, high
}

public struct GeminiSettings: Equatable, Sendable {
    public var model: String
    public var prompt: String
    public var thinkingLevel: ThinkingLevel

    public init(model: String, prompt: String, thinkingLevel: ThinkingLevel) {
        self.model = model
        self.prompt = prompt
        self.thinkingLevel = thinkingLevel
    }

    public static let defaults = GeminiSettings(
        model: "gemini-3-flash-preview",
        prompt: """
            Транскрибируй дословно.
            Верни только транскрипцию.
            Первый символ ответа должен быть первым символом транскрипции.
            Не добавляй вводные слова, пояснения, комментарии, заголовки, подписи или markdown.
            Разбей текст на короткие смысловые абзацы.
            Между абзацами ставь одну пустую строку.
            Не добавляй таймстемпы.
            Не добавляй лайблы спикеров.
            """,
        thinkingLevel: .minimal
    )
}

public enum GeminiTranscription {
    public static let requestTimeout: TimeInterval = 180

    static let inlineRequestMaxBytes = 20_000_000
    static let maxOutputTokens = 65_535
    static let temperature = 1.0

    public static func streamURL(model: String) throws -> URL {
        let model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty,
              let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):streamGenerateContent?alt=sse")
        else {
            throw GeminiTranscriptionError.invalidSetting("model", model)
        }
        return url
    }

    public static func requestBody(audio: Data, mimeType: String, settings: GeminiSettings) throws -> Data {
        let prompt = settings.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else {
            throw GeminiTranscriptionError.invalidSetting("prompt", "")
        }
        let request = GenerateContentRequest(
            contents: [
                RequestContent(
                    role: "user",
                    parts: [
                        RequestPart(text: prompt),
                        RequestPart(inlineData: InlineData(mimeType: mimeType, data: audio.base64EncodedString())),
                    ]
                ),
            ],
            generationConfig: GenerationConfig(
                responseMimeType: "text/plain",
                temperature: temperature,
                maxOutputTokens: maxOutputTokens,
                thinkingConfig: ThinkingConfig(includeThoughts: false, thinkingLevel: settings.thinkingLevel.rawValue)
            )
        )
        let body = try JSONEncoder().encode(request)
        guard body.count < inlineRequestMaxBytes else {
            throw GeminiTranscriptionError.requestTooLarge(bytes: body.count, limit: inlineRequestMaxBytes)
        }
        return body
    }
}

public enum GeminiTranscriptionError: LocalizedError, Equatable {
    case invalidSetting(String, String)
    case requestTooLarge(bytes: Int, limit: Int)
    case httpStatus(Int, body: String)
    case noCandidates
    case finishReason(String)
    case missingFinishReason
    case emptyTranscription

    public var errorDescription: String? {
        switch self {
        case let .invalidSetting(name, value):
            "Gemini Transcribator setting '\(name)' is invalid: '\(value)'"
        case let .requestTooLarge(bytes, limit):
            "Gemini inline request is \(bytes) bytes; it must be smaller than \(limit) bytes"
        case let .httpStatus(status, body):
            "Gemini transcription failed with status \(status): \(body)"
        case .noCandidates:
            "Gemini returned no candidates"
        case let .finishReason(reason):
            "Gemini transcription stopped with finish reason \(reason)"
        case .missingFinishReason:
            "Gemini stream ended without a terminal finish reason"
        case .emptyTranscription:
            "Gemini returned an empty transcription"
        }
    }
}

/// Collects `streamGenerateContent?alt=sse` lines and accepts the text only
/// when the stream ended with `STOP`.
public struct SSETranscriptAccumulator {
    private var chunks: [String] = []
    private var sawCandidate = false
    private var finishReason: String?

    public init() {}

    public mutating func consume(line: String) throws {
        guard line.hasPrefix("data:") else { return }
        let data = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
        guard !data.isEmpty, data != "[DONE]" else { return }

        let response = try JSONDecoder().decode(StreamResponse.self, from: Data(data.utf8))
        guard let candidate = response.candidates?.first else { return }
        sawCandidate = true
        if let reason = candidate.finishReason {
            finishReason = reason
        }
        chunks.append(contentsOf: candidate.content?.parts?.compactMap(\.text) ?? [])
    }

    public func finish() throws -> String {
        guard sawCandidate else { throw GeminiTranscriptionError.noCandidates }
        switch finishReason {
        case "STOP":
            break
        case let reason?:
            throw GeminiTranscriptionError.finishReason(reason)
        case nil:
            throw GeminiTranscriptionError.missingFinishReason
        }
        let transcription = chunks.joined().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcription.isEmpty else { throw GeminiTranscriptionError.emptyTranscription }
        return transcription
    }
}

private struct GenerateContentRequest: Encodable {
    let contents: [RequestContent]
    let generationConfig: GenerationConfig
}

private struct RequestContent: Encodable {
    let role: String
    let parts: [RequestPart]
}

private struct RequestPart: Encodable {
    var text: String?
    var inlineData: InlineData?
}

private struct InlineData: Encodable {
    let mimeType: String
    let data: String
}

private struct GenerationConfig: Encodable {
    let responseMimeType: String
    let temperature: Double
    let maxOutputTokens: Int
    let thinkingConfig: ThinkingConfig
}

private struct ThinkingConfig: Encodable {
    let includeThoughts: Bool
    let thinkingLevel: String
}

private struct StreamResponse: Decodable {
    let candidates: [Candidate]?

    struct Candidate: Decodable {
        let content: Content?
        let finishReason: String?
    }

    struct Content: Decodable {
        let parts: [Part]?
    }

    struct Part: Decodable {
        let text: String?
    }
}
