#!/usr/bin/env bash
# Builds, installs into TypeWhisper's external plugins dir, enables and restarts the app.
set -euo pipefail
cd "$(dirname "$0")/.."

scripts/build.sh

PLUGINS="$HOME/Library/Application Support/TypeWhisper/Plugins"
mkdir -p "$PLUGINS"
rm -rf "$PLUGINS/GeminiTranscribator.bundle"
ditto .build/GeminiTranscribator.bundle "$PLUGINS/GeminiTranscribator.bundle"
defaults write com.typewhisper.mac plugin.com.sne.gemini-transcribator.enabled -bool true

osascript -e 'quit app "TypeWhisper"' || true
while pgrep -x TypeWhisper >/dev/null; do sleep 0.2; done
open -a TypeWhisper

echo "Installed to $PLUGINS and restarted TypeWhisper"
