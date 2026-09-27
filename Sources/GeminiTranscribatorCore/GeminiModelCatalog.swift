import Foundation

public struct GeminiModel: Equatable, Sendable {
    public let id: String
    public let displayName: String

    public init(id: String, displayName: String) {
        self.id = id
        self.displayName = displayName
    }
}

public enum GeminiModelCatalog {
    static let listURL = URL(string: "https://generativelanguage.googleapis.com/v1beta/models")!
    static let requestTimeout: TimeInterval = 20

    /// Text-producing Gemini models callable via generateContent. The API exposes
    /// no modality metadata, so TTS and image models are excluded by id.
    public static func transcriptionModels(fromPage data: Data) throws -> (models: [GeminiModel], nextPageToken: String?) {
        let page = try JSONDecoder().decode(ModelsPage.self, from: data)
        let models = (page.models ?? []).compactMap { model -> GeminiModel? in
            let id = model.name.hasPrefix("models/") ? String(model.name.dropFirst("models/".count)) : model.name
            guard model.supportedGenerationMethods?.contains("generateContent") == true,
                  id.hasPrefix("gemini-"),
                  !id.contains("-tts"),
                  !id.contains("-image")
            else { return nil }
            return GeminiModel(id: id, displayName: model.displayName ?? id)
        }
        let token = page.nextPageToken.flatMap { $0.isEmpty ? nil : $0 }
        return (models, token)
    }

    /// Catalog sorted by id, plus the selected model when the catalog lacks it,
    /// so the current setting is always visible.
    public static func choices(catalog: [GeminiModel], selected: String) -> [GeminiModel] {
        let sorted = catalog.sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
        guard !selected.isEmpty, !sorted.contains(where: { $0.id == selected }) else { return sorted }
        return sorted + [GeminiModel(id: selected, displayName: "\(selected) (not in catalog)")]
    }

    public static func fetch(apiKey: String) async throws -> [GeminiModel] {
        var models: [GeminiModel] = []
        var pageToken: String?
        repeat {
            var components = URLComponents(url: listURL, resolvingAgainstBaseURL: false)!
            components.queryItems = [URLQueryItem(name: "pageSize", value: "1000")]
                + (pageToken.map { [URLQueryItem(name: "pageToken", value: $0)] } ?? [])
            var request = URLRequest(url: components.url!, timeoutInterval: requestTimeout)
            request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")

            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(status) else {
                throw GeminiTranscriptionError.httpStatus(status, body: String(decoding: data, as: UTF8.self))
            }
            let page = try transcriptionModels(fromPage: data)
            models += page.models
            pageToken = page.nextPageToken
        } while pageToken != nil
        return models
    }
}

private struct ModelsPage: Decodable {
    let models: [Model]?
    let nextPageToken: String?

    struct Model: Decodable {
        let name: String
        let displayName: String?
        let supportedGenerationMethods: [String]?
    }
}
