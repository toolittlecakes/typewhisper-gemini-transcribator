import Foundation
import XCTest
@testable import GeminiTranscribatorCore

final class GeminiTranscriptionTests: XCTestCase {
    func testSerializesSettingsAndInlineAudio() throws {
        let settings = GeminiSettings(model: "m", prompt: " p\n", thinkingLevel: .low)
        let body = try GeminiTranscription.requestBody(audio: Data([1, 2, 3]), mimeType: "audio/mp4", settings: settings)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let config = try XCTUnwrap(json["generationConfig"] as? [String: Any])
        let thinking = try XCTUnwrap(config["thinkingConfig"] as? [String: Any])
        let parts = try XCTUnwrap((json["contents"] as? [[String: Any]])?.first?["parts"] as? [[String: Any]])
        let inline = try XCTUnwrap(parts[1]["inlineData"] as? [String: Any])

        XCTAssertEqual(thinking["thinkingLevel"] as? String, "low")
        XCTAssertEqual(thinking["includeThoughts"] as? Bool, false)
        XCTAssertEqual(config["maxOutputTokens"] as? Int, 65_535)
        XCTAssertEqual(config["temperature"] as? Double, 1.0)
        XCTAssertEqual(config["responseMimeType"] as? String, "text/plain")
        XCTAssertEqual(parts[0].keys.sorted(), ["text"])
        XCTAssertEqual(parts[0]["text"] as? String, "p")
        XCTAssertEqual(inline["mimeType"] as? String, "audio/mp4")
        XCTAssertEqual(inline["data"] as? String, "AQID")
    }

    func testDefaultsUseMinimalReasoningOnFlash() {
        XCTAssertEqual(GeminiSettings.defaults.model, "gemini-3-flash-preview")
        XCTAssertEqual(GeminiSettings.defaults.thinkingLevel, .minimal)
    }

    func testBuildsStreamURLForConfiguredModel() throws {
        XCTAssertEqual(
            try GeminiTranscription.streamURL(model: " gemini-x ").absoluteString,
            "https://generativelanguage.googleapis.com/v1beta/models/gemini-x:streamGenerateContent?alt=sse"
        )
    }

    func testRejectsBlankModelAndPrompt() {
        XCTAssertThrowsError(try GeminiTranscription.streamURL(model: "  ")) { error in
            XCTAssertEqual(error as? GeminiTranscriptionError, .invalidSetting("model", ""))
        }
        var settings = GeminiSettings.defaults
        settings.prompt = " \n"
        XCTAssertThrowsError(try GeminiTranscription.requestBody(audio: Data(), mimeType: "audio/mp4", settings: settings)) { error in
            XCTAssertEqual(error as? GeminiTranscriptionError, .invalidSetting("prompt", ""))
        }
    }

    func testEnforcesInlineLimitOnFinalBodySize() throws {
        func body(promptLength: Int) throws -> Data {
            var settings = GeminiSettings.defaults
            settings.prompt = String(repeating: "x", count: promptLength)
            return try GeminiTranscription.requestBody(audio: Data(), mimeType: "audio/mp4", settings: settings)
        }
        let overhead = try body(promptLength: 1).count - 1
        let limit = GeminiTranscription.inlineRequestMaxBytes

        XCTAssertEqual(try body(promptLength: limit - 1 - overhead).count, limit - 1)
        XCTAssertThrowsError(try body(promptLength: limit - overhead)) { error in
            XCTAssertEqual(error as? GeminiTranscriptionError, .requestTooLarge(bytes: limit, limit: limit))
        }
    }

    func testJoinsSSETextChunks() throws {
        let text = try accumulate([
            #"data: {"candidates":[{"content":{"parts":[{"text":"Привет"}]}}]}"#,
            #"data: {"candidates":[{"content":{"parts":[{"text":", мир"}]},"finishReason":"STOP"}]}"#,
        ])
        XCTAssertEqual(text, "Привет, мир")
    }

    func testRejectsFilteredResponse() {
        assertAccumulateFails([#"data: {"candidates":[{"finishReason":"SAFETY"}]}"#], with: .finishReason("SAFETY"))
    }

    func testRejectsPartialTextWithoutSuccessfulFinishReason() {
        assertAccumulateFails(
            [
                #"data: {"candidates":[{"content":{"parts":[{"text":"partial"}]}}]}"#,
                #"data: {"candidates":[{"finishReason":"MAX_TOKENS"}]}"#,
            ],
            with: .finishReason("MAX_TOKENS")
        )
    }

    func testRejectsTruncatedStream() {
        assertAccumulateFails(
            [#"data: {"candidates":[{"content":{"parts":[{"text":"partial"}]}}]}"#],
            with: .missingFinishReason
        )
    }

    func testRejectsStreamWithoutCandidates() {
        assertAccumulateFails([#"data: {"usageMetadata":{}}"#], with: .noCandidates)
    }

    func testRejectsBlankTranscription() {
        assertAccumulateFails(
            [#"data: {"candidates":[{"content":{"parts":[{"text":"  \n"}]},"finishReason":"STOP"}]}"#],
            with: .emptyTranscription
        )
    }

    /// Hits the real API: `GEMINI_API_KEY=... GEMINI_TEST_M4A=/path/to.m4a swift test --filter Live`.
    func testLiveTranscribesRealM4A() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["GEMINI_TEST_M4A"], let apiKey = environment["GEMINI_API_KEY"] else {
            throw XCTSkip("GEMINI_TEST_M4A and GEMINI_API_KEY are required")
        }
        let text = try await GeminiClient.transcribe(
            audio: try Data(contentsOf: URL(fileURLWithPath: path)),
            mimeType: "audio/mp4",
            settings: .defaults,
            apiKey: apiKey
        )
        print("live transcription: \(text.count) chars")
        XCTAssertFalse(text.isEmpty)
    }

    private func accumulate(_ lines: [String]) throws -> String {
        var accumulator = SSETranscriptAccumulator()
        for line in lines {
            try accumulator.consume(line: line)
        }
        return try accumulator.finish()
    }

    private func assertAccumulateFails(_ lines: [String], with expected: GeminiTranscriptionError) {
        XCTAssertThrowsError(try accumulate(lines)) { error in
            XCTAssertEqual(error as? GeminiTranscriptionError, expected)
        }
    }
}
