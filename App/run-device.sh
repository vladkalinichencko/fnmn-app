#!/bin/zsh
# Builds FNMN for a connected iPhone or iPad and installs it over the old version; the library on the device stays.
#   App/run-device.sh            the first connected physical device
#   App/run-device.sh <UDID>     a specific one
set -e
DEVICE=${1:-$(xcrun devicectl list devices | grep -E 'connected +.*physical' | grep -Eo '[0-9A-F]{8}-[0-9A-F]{16}' | head -1)}
DERIVED=${TMPDIR:-/tmp}/fnmn-device-build
cd "$(dirname "$0")"
xcodebuild -project FNMN.xcodeproj -scheme FNMN -destination "id=$DEVICE" -derivedDataPath "$DERIVED" -allowProvisioningUpdates build | grep -E "error:|BUILD"
xcrun devicectl device install app --device "$DEVICE" "$DERIVED/Build/Products/Debug-iphoneos/FNMN.app"
