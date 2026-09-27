import Foundation
import XCTest
@testable import GeminiTranscribatorCore

final class GeminiModelCatalogTests: XCTestCase {
    func testKeepsTextGeminiModelsCallableViaGenerateContent() throws {
        let page = Data("""
            {"models": [
              {"name": "models/gemini-3-flash-preview", "displayName": "Gemini 3 Flash Preview", "supportedGenerationMethods": ["generateContent", "countTokens"]},
              {"name": "models/gemini-3.8-flash-tts", "displayName": "TTS", "supportedGenerationMethods": ["generateContent"]},
              {"name": "models/gemini-3.1-flash-image", "displayName": "Nano Banana 2", "supportedGenerationMethods": ["generateContent"]},
              {"name": "models/gemini-3.5-transcribe-live", "displayName": "Live", "supportedGenerationMethods": ["bidiGenerateContent"]},
              {"name": "models/gemini-embedding-2", "displayName": "Embedding", "supportedGenerationMethods": ["embedContent"]},
              {"name": "models/lyria-3.5", "displayName": "Lyria", "supportedGenerationMethods": ["generateContent"]},
              {"name": "models/gemini-3.5-transcribe", "supportedGenerationMethods": ["generateContent"]}
            ], "nextPageToken": "next"}
            """.utf8)

        let result = try GeminiModelCatalog.transcriptionModels(fromPage: page)

        XCTAssertEqual(result.models, [
            GeminiModel(id: "gemini-3-flash-preview", displayName: "Gemini 3 Flash Preview"),
            GeminiModel(id: "gemini-3.5-transcribe", displayName: "gemini-3.5-transcribe"),
        ])
        XCTAssertEqual(result.nextPageToken, "next")
    }

    func testTreatsEmptyPageTokenAsLastPage() throws {
        let result = try GeminiModelCatalog.transcriptionModels(fromPage: Data(#"{"models": [], "nextPageToken": ""}"#.utf8))
        XCTAssertNil(result.nextPageToken)
    }

    func testSortsChoicesNumericallyAndKeepsSelectedModelVisible() {
        let catalog = [
            GeminiModel(id: "gemini-3.10-flash", displayName: "10"),
            GeminiModel(id: "gemini-3.8-flash", displayName: "8"),
        ]

        XCTAssertEqual(GeminiModelCatalog.choices(catalog: catalog, selected: "gemini-3.8-flash").map(\.id), [
            "gemini-3.8-flash", "gemini-3.10-flash",
        ])
        XCTAssertEqual(
            GeminiModelCatalog.choices(catalog: catalog, selected: "gemini-old").last,
            GeminiModel(id: "gemini-old", displayName: "gemini-old (not in catalog)")
        )
    }
}
