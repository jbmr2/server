#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEVICE="${1:-CD5BE737-5AA4-5607-9DD4-C99ADE91BD33}"
cd "$ROOT"
xcodebuild -scheme JBMRSports -destination 'platform=iOS,id=00008120-001C153A3CF1A01E' -configuration Debug -allowProvisioningUpdates build
APP="$HOME/Library/Developer/Xcode/DerivedData/JBMRSports-aekxrhxcuplmmmckxhskbkkefoia/Build/Products/Debug-iphoneos/JBMRSports.app"
xcrun devicectl device install app --device "$DEVICE" "$APP"
xcrun devicectl device process launch --device "$DEVICE" in.jbmrsports.ott
echo "Installed + launched on device $DEVICE"
