#!/bin/bash
set -euo pipefail

# Optional helper for an already-built, signed app. Xcode Command-R is the
# recommended setup path. Obtain your device identifier with:
# xcrun devicectl list devices
DEVICE_UDID="${1:?Usage: bash install_to_iphone.sh DEVICE_IDENTIFIER BUILT_APP_PATH}"
APP_PATH="${2:?Provide the path to your built and signed NeuroPulse.app}"

if [[ ! -d "$APP_PATH" ]]; then
    echo "App bundle not found: $APP_PATH" >&2
    exit 1
fi
xcrun devicectl device install app --device "$DEVICE_UDID" "$APP_PATH"
echo "Installed. Open Pupil Check on your iPhone."
