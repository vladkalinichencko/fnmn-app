#!/bin/zsh
# Builds FNMN for a connected iPhone or iPad, installs it over the old version and opens it; the library on the device stays.
#   App/run-device.sh            the first connected physical device
#   App/run-device.sh <UDID>     a specific one
set -e -o pipefail
DEVICE=${1:-$(xcrun devicectl list devices | grep -E '(connected|available).*physical' | grep -Eo '[0-9A-F]{8}-[0-9A-F]{16}' | head -1)}
if [[ -z $DEVICE ]]; then
  echo "No iPhone or iPad is connected. Plug it in by cable, unlock it and trust this Mac; 'xcrun devicectl list devices' should show it as connected." >&2
  xcrun devicectl list devices | grep physical >&2
  exit 1
fi
DERIVED=${TMPDIR:-/tmp}/fnmn-device-build
cd "$(dirname "$0")"
xcodebuild -project FNMN.xcodeproj -scheme FNMN -destination "generic/platform=iOS" -derivedDataPath "$DERIVED" -allowProvisioningUpdates build | grep -E "error:|BUILD"
xcrun devicectl device install app --device "$DEVICE" "$DERIVED/Build/Products/Debug-iphoneos/FNMN.app"
xcrun devicectl device process launch --terminate-existing --device "$DEVICE" local.fnmn.reader
