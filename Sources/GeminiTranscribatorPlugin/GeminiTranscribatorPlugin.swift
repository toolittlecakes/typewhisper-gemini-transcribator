import Foundation
import GeminiTranscribatorCore
import os
import SwiftUI
import TypeWhisperPluginSDK

private let logger = Logger(subsystem: "com.sne.gemini-transcribator", category: "Plugin")

@objc(GeminiTranscribatorPlugin)
final class GeminiTranscribatorPlugin: NSObject, TranscriptionEnginePlugin, @unchecked Sendable {
    static let pluginId = "com.sne.gemini-transcribator"
    static let pluginName = "Gemini Transcribator"

    private var host: HostServices?

    override required init() {
        super.init()
    }

    func activate(host: HostServices) {
        self.host = host
        guard loadAPIKey(host: host) != nil else { return }
        Task {
            do {
                _ = try await refreshModelCatalog(host: host)
            } catch {
                logger.error("Model catalog refresh failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func deactivate() {
        host = nil
    }

    @MainActor
    var settingsView: AnyView? {
        guard let host else { return nil }
        return AnyView(GeminiTranscribatorSettingsView(store: SettingsStore(host: host)))
    }

    var providerId: String { "gemini-transcribator" }
    var providerDisplayName: String { "Gemini Transcribator" }
    var isConfigured: Bool { host.flatMap(loadAPIKey(host:)) != nil }
    var transcriptionModels: [PluginModelInfo] {
        guard let host else { return [] }
        return GeminiModelCatalog.choices(catalog: loadModelCatalog(host: host), selected: GeminiSettings.load(from: host).model)
            .map { PluginModelInfo(id: $0.id, displayName: $0.displayName) }
    }
    var selectedModelId: String? { host.map { GeminiSettings.load(from: $0).model } }
    var supportsTranslation: Bool { false }

    func selectModel(_ modelId: String) {
        guard let host else { return }
        var settings = GeminiSettings.load(from: host)
        settings.model = modelId
        settings.save(to: host)
        host.notifyCapabilitiesChanged()
    }

    func transcribe(audio: AudioData, language: String?, translate: Bool, prompt: String?) async throws -> PluginTranscriptionResult {
        guard !translate else {
            throw PluginTranscriptionError.apiError("Gemini Transcribator does not support translation.")
        }
        guard let host, let apiKey = loadAPIKey(host: host) else { throw PluginTranscriptionError.notConfigured }
        let upload = try PluginAudioUploadEncoder.compressedM4AUpload(
            from: PluginAudioUploadEncoder.normalizedAudioForUpload(audio)
        )
        let text = try await GeminiClient.transcribe(
            audio: upload.data,
            mimeType: upload.contentType,
            settings: GeminiSettings.load(from: host),
            apiKey: apiKey
        )
        return PluginTranscriptionResult(text: text)
    }
}

private enum SettingsKey {
    static let model = "model"
    static let prompt = "prompt"
    static let thinkingLevel = "thinkingLevel"
    static let modelCatalog = "modelCatalog"
    static let apiKeySecret = "apiKey"
}

private func loadAPIKey(host: HostServices) -> String? {
    guard let key = host.loadSecret(key: SettingsKey.apiKeySecret), !key.isEmpty else { return nil }
    return key
}

extension GeminiSettings {
    static func load(from host: HostServices) -> GeminiSettings {
        GeminiSettings(
            model: host.userDefault(forKey: SettingsKey.model) as? String ?? defaults.model,
            prompt: host.userDefault(forKey: SettingsKey.prompt) as? String ?? defaults.prompt,
            thinkingLevel: (host.userDefault(forKey: SettingsKey.thinkingLevel) as? String)
                .flatMap(ThinkingLevel.init(rawValue:)) ?? defaults.thinkingLevel
        )
    }

    func save(to host: HostServices) {
        host.setUserDefault(model, forKey: SettingsKey.model)
        host.setUserDefault(prompt, forKey: SettingsKey.prompt)
        host.setUserDefault(thinkingLevel.rawValue, forKey: SettingsKey.thinkingLevel)
    }
}

/// Last fetched catalog, cached so the pickers work offline and at startup.
private func loadModelCatalog(host: HostServices) -> [GeminiModel] {
    let stored = host.userDefault(forKey: SettingsKey.modelCatalog) as? [[String: String]] ?? []
    return stored.compactMap { entry in
        guard let id = entry["id"], let name = entry["name"] else { return nil }
        return GeminiModel(id: id, displayName: name)
    }
}

private func refreshModelCatalog(host: HostServices) async throws -> [GeminiModel] {
    guard let apiKey = loadAPIKey(host: host) else { throw PluginTranscriptionError.notConfigured }
    let models = try await GeminiModelCatalog.fetch(apiKey: apiKey)
    host.setUserDefault(models.map { ["id": $0.id, "name": $0.displayName] }, forKey: SettingsKey.modelCatalog)
    host.notifyCapabilitiesChanged()
    return models
}

@MainActor
private final class SettingsStore: ObservableObject {
    private let host: HostServices

    @Published var settings: GeminiSettings {
        didSet {
            settings.save(to: host)
            if settings.model != oldValue.model {
                host.notifyCapabilitiesChanged()
            }
        }
    }
    @Published var apiKeyInput = ""
    @Published private(set) var hasAPIKey: Bool
    @Published private(set) var apiKeyError: String?
    @Published private(set) var catalog: [GeminiModel]
    @Published private(set) var isRefreshing = false
    @Published private(set) var refreshError: String?

    var modelChoices: [GeminiModel] {
        GeminiModelCatalog.choices(catalog: catalog, selected: settings.model)
    }

    init(host: HostServices) {
        self.host = host
        settings = GeminiSettings.load(from: host)
        catalog = loadModelCatalog(host: host)
        hasAPIKey = loadAPIKey(host: host) != nil
    }

    func saveAPIKey() async {
        let key = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try host.storeSecret(key: SettingsKey.apiKeySecret, value: key)
        } catch {
            apiKeyError = error.localizedDescription
            return
        }
        apiKeyInput = ""
        apiKeyError = nil
        hasAPIKey = !key.isEmpty
        host.notifyCapabilitiesChanged()
        if hasAPIKey {
            await refreshCatalog()
        }
    }

    func refreshCatalog() async {
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            catalog = try await refreshModelCatalog(host: host)
            refreshError = nil
        } catch {
            refreshError = error.localizedDescription
        }
    }
}

private struct GeminiTranscribatorSettingsView: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SecureField(store.hasAPIKey ? "API key saved in Keychain — paste to replace" : "Gemini API key", text: $store.apiKeyInput)
                Button("Save") {
                    Task { await store.saveAPIKey() }
                }
            }
            if let error = store.apiKeyError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }

            HStack {
                Picker("Model", selection: $store.settings.model) {
                    ForEach(store.modelChoices, id: \.id) { model in
                        Text("\(model.displayName) · \(model.id)").tag(model.id)
                    }
                }
                Button(store.isRefreshing ? "Refreshing…" : "Refresh") {
                    Task { await store.refreshCatalog() }
                }
                .disabled(store.isRefreshing)
            }
            if let error = store.refreshError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }

            Picker("Reasoning", selection: $store.settings.thinkingLevel) {
                ForEach(ThinkingLevel.allCases, id: \.self) { level in
                    Text(level.rawValue).tag(level)
                }
            }
            .pickerStyle(.segmented)

            Text("Prompt")
                .font(.headline)
            TextEditor(text: $store.settings.prompt)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 180)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(.separator, lineWidth: 1)
                )

            HStack {
                Text("Get a key at aistudio.google.com/apikey. Audio is sent inline as M4A.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Reset Defaults") {
                    store.settings = .defaults
                }
            }
        }
        .padding()
        .frame(minWidth: 520, minHeight: 420)
        .task {
            if store.catalog.isEmpty, store.hasAPIKey {
                await store.refreshCatalog()
            }
        }
    }
}
