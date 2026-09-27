#!/usr/bin/env bash
# Builds GeminiTranscribator.bundle without Xcode: SwiftPM + swiftc against the
# SDK framework of the installed TypeWhisper.app.
set -euo pipefail
cd "$(dirname "$0")/.."

APP=/Applications/TypeWhisper.app
TAG="v$(defaults read "$APP/Contents/Info.plist" CFBundleShortVersionString)"
SDK_SRC=".build/typewhisper-$TAG"
BUNDLE=.build/GeminiTranscribator.bundle

# The SDK interface must match the host binary exactly (non-resilient Swift ABI),
# so it is compiled from the tag of the installed app, never from main.
if [ ! -d "$SDK_SRC" ]; then
    git clone --quiet --depth 1 --branch "$TAG" --filter=blob:none --sparse \
        https://github.com/TypeWhisper/typewhisper-mac "$SDK_SRC"
    git -C "$SDK_SRC" sparse-checkout set TypeWhisperPluginSDK/Sources/TypeWhisperPluginSDK
fi

mkdir -p .build/sdk
swiftc -emit-module -parse-as-library \
    -module-name TypeWhisperPluginSDK -suppress-warnings \
    -target arm64-apple-macosx14.0 \
    -emit-module-path .build/sdk/TypeWhisperPluginSDK.swiftmodule \
    "$SDK_SRC"/TypeWhisperPluginSDK/Sources/TypeWhisperPluginSDK/*.swift

swift build -c release --arch arm64 --product GeminiTranscribator

rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp Bundle/Info.plist "$BUNDLE/Contents/Info.plist"
cp Bundle/manifest.json "$BUNDLE/Contents/Resources/manifest.json"
cp "$(swift build -c release --arch arm64 --show-bin-path)/libGeminiTranscribator.dylib" \
    "$BUNDLE/Contents/MacOS/GeminiTranscribator"
codesign --force --sign - "$BUNDLE"

echo "Built $BUNDLE against TypeWhisper $TAG"
