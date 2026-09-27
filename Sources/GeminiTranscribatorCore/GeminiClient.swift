import Foundation

public enum GeminiClient {
    public static func transcribe(audio: Data, mimeType: String, settings: GeminiSettings, apiKey: String) async throws -> String {
        var request = URLRequest(
            url: try GeminiTranscription.streamURL(model: settings.model),
            timeoutInterval: GeminiTranscription.requestTimeout
        )
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try GeminiTranscription.requestBody(audio: audio, mimeType: mimeType, settings: settings)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let status = (response as? HTTPURLResponse)?.statusCode else {
            throw URLError(.badServerResponse)
        }
        guard (200..<300).contains(status) else {
            var body: [String] = []
            for try await line in bytes.lines { body.append(line) }
            throw GeminiTranscriptionError.httpStatus(status, body: body.joined(separator: "\n"))
        }

        var accumulator = SSETranscriptAccumulator()
        for try await line in bytes.lines {
            try accumulator.consume(line: line)
        }
        return try accumulator.finish()
    }
}
