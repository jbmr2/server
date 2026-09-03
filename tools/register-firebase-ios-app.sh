#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_ID="ncrplt20-1c022"
BUNDLE_ID="in.jbmrsports.ott"
APP_NAME="JBMR Sports OTT"
PLIST_PATH="$ROOT/JBMRSports/GoogleService-Info.plist"

echo "JBMR Sports OTT — Firebase iOS setup ($BUNDLE_ID)"
echo
echo "Apple Developer par bundle register mat karo — com.jbmrsports.ott pehle se team par hai."
echo
echo "Firebase Console steps:"
echo "  1. https://console.firebase.google.com/project/$PROJECT_ID/settings/general"
echo "  2. Add app → iOS"
echo "  3. Bundle ID: $BUNDLE_ID"
echo "  4. GoogleService-Info.plist download karke yahan copy karo:"
echo "     $PLIST_PATH"
echo "  5. Authentication → Sign-in method → Phone → Enable"
echo "  6. Firestore database create karo (agar nahi hai)"
echo

if ! firebase login:list >/dev/null 2>&1; then
  echo "CLI: pehle run karo → firebase login --reauth"
  exit 0
fi

cd "$ROOT"
if firebase use "$PROJECT_ID" >/dev/null 2>&1; then
  echo "CLI: Firebase project selected."
  if firebase apps:sdkconfig IOS "$BUNDLE_ID" --project "$PROJECT_ID" -o "$PLIST_PATH" 2>/dev/null; then
    echo "CLI: Downloaded GoogleService-Info.plist"
  else
    echo "CLI: Creating iOS app..."
    firebase apps:create IOS "$APP_NAME" --bundle-id="$BUNDLE_ID" --project "$PROJECT_ID"
    firebase apps:sdkconfig IOS "$BUNDLE_ID" --project "$PROJECT_ID" -o "$PLIST_PATH"
    echo "CLI: App created + plist saved."
  fi
  echo "Optional: firebase deploy --only firestore:rules --project $PROJECT_ID"
else
  echo "CLI: project access nahi mila — upar wale Console steps follow karo."
fi
