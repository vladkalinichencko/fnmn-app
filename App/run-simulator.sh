#!/bin/zsh
# Builds FNMN for a booted simulator, reinstalls it and launches it; the library in the simulator stays.
#   App/run-simulator.sh            the first booted simulator
#   App/run-simulator.sh <UDID>     a specific one
set -e
DEVICE=${1:-$(xcrun simctl list devices booted | grep -Eo '[0-9A-F-]{36}' | head -1)}
DERIVED=${TMPDIR:-/tmp}/fnmn-simulator-build
cd "$(dirname "$0")"
xcodebuild -project FNMN.xcodeproj -scheme FNMN -destination "id=$DEVICE" -derivedDataPath "$DERIVED" build | grep -E "error:|BUILD"
xcrun simctl terminate "$DEVICE" local.fnmn.reader 2>/dev/null || true
xcrun simctl install "$DEVICE" "$DERIVED/Build/Products/Debug-iphonesimulator/FNMN.app"
xcrun simctl launch "$DEVICE" local.fnmn.reader
