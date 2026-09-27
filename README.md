# Gemini Transcribator for TypeWhisper

A [TypeWhisper](https://github.com/TypeWhisper/typewhisper-mac) transcription engine plugin that sends your dictation to Google Gemini in a single request.

- **Model picker** backed by Google's live model list (`GET v1beta/models`: Gemini models that support `generateContent`, excluding TTS/image models). The same list shows up in TypeWhisper's own model selector.
- **Reasoning level**: `minimal` (default) / `low` / `medium` / `high`.
- **Editable prompt**. The default prompt is in Russian and asks for a verbatim transcript split into short paragraphs; replace it with your own in the settings.
- **Compact upload**: audio is encoded to M4A/AAC 24 kbps and sent inline (base64) in one `streamGenerateContent` call — no Files API round-trips. Inline requests are limited to 20 MB (~80 min of audio).
- **Fails loudly**: HTTP errors, safety blocks, truncated or empty responses surface as errors instead of partial text.

Measured on real dictations through a VPN: 2.4–4 s from key release to text with `gemini-3-flash-preview` + `minimal`, versus a constant ~12 s with the marketplace Gemini plugin, which uploads via the Files API (4 sequential requests).

## Requirements

- TypeWhisper 1.6.x on macOS 14+, Apple Silicon.
- A Gemini API key from [Google AI Studio](https://aistudio.google.com/apikey).

## Install

```bash
curl -fL -o /tmp/GeminiTranscribator.zip \
  https://github.com/toolittlecakes/typewhisper-gemini-transcribator/releases/latest/download/GeminiTranscribator.zip
mkdir -p ~/Library/Application\ Support/TypeWhisper/Plugins
ditto -x -k /tmp/GeminiTranscribator.zip ~/Library/Application\ Support/TypeWhisper/Plugins/
```

If you downloaded the zip with a browser instead, remove the quarantine flag after unpacking:

```bash
xattr -dr com.apple.quarantine ~/Library/Application\ Support/TypeWhisper/Plugins/GeminiTranscribator.bundle
```

Then:

1. Restart TypeWhisper.
2. Settings → Integrations → **Gemini Transcribator** → enable it and open its settings.
3. Paste your API key → **Save** (stored in the macOS Keychain). The model list loads automatically; **Refresh** reloads it.
4. Select **Gemini Transcribator** as the transcription engine.

## Compatibility

The plugin is built against the TypeWhisper plugin SDK (`sdkCompatibilityVersion: v1`) shipped with TypeWhisper 1.6.1 and links the SDK framework inside `TypeWhisper.app`. If a future TypeWhisper update stops loading it, grab a newer release or build from source against your installed version.

## Build from source

Needs the Swift toolchain (Xcode or Command Line Tools); no Xcode project is involved.

```bash
scripts/build.sh      # compiles the SDK interface from the tag matching /Applications/TypeWhisper.app → .build/GeminiTranscribator.bundle
scripts/install.sh    # build + copy into TypeWhisper's Plugins folder + enable + restart TypeWhisper
swift test            # unit tests (run scripts/build.sh first)
GEMINI_API_KEY=... GEMINI_TEST_M4A=/path/audio.m4a swift test --filter Live   # real API call
```

Layout: `Sources/GeminiTranscribatorCore` holds the pure request/response logic and HTTP client, `Sources/GeminiTranscribatorPlugin` the TypeWhisper adapter and settings UI, `Bundle/` the bundle `Info.plist` and `manifest.json`.

## License

GPL-3.0, matching the TypeWhisper SDK it links against.
