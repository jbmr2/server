#!/usr/bin/env bash
# Firebase Phone OTP (bina captcha) ke liye APNs .p8 key zaroori hai.
set -euo pipefail

cat <<'EOF'
========================================
JBMR Sports — APNs Key Firebase Setup
========================================

YE ERROR ISLIYE AA RAHA HAI:
"Firebase APNs setup pending" / missingAppCredential

Bina APNs key ke real OTP SMS NAHI chalega (captcha bhi band hai).

----------------------------------------
STEP 1 — Apple Developer (2 min)
----------------------------------------
1. https://developer.apple.com/account/resources/authkeys/list
2. "+" → Name: "JBMR APNs Key"
3. Check: "Apple Push Notifications service (APNs)"
4. Continue → Register → DOWNLOAD .p8 file (sirf ek baar milti hai!)
5. Note karo:
   - Key ID (10 chars, e.g. ABC1234XYZ)
   - Team ID: SJ536RSC6J (LOKESH LOKESH)

----------------------------------------
STEP 2 — Firebase Console (1 min)
----------------------------------------
1. https://console.firebase.google.com/project/ncrplt20-1c022/settings/cloudmessaging
2. Apple apps → "in.jbmrsports.ott"
3. "Upload" under APNs Authentication Key
4. .p8 file + Key ID + Team ID SJ536RSC6J
5. Save

----------------------------------------
STEP 3 — Phone Auth ON
----------------------------------------
https://console.firebase.google.com/project/ncrplt20-1c022/authentication/providers
→ Phone → Enable

----------------------------------------
STEP 4 — App reinstall
----------------------------------------
Xcode se dubara run karo ya: tools/install-device.sh

----------------------------------------
ABHI TEST (bina APNs, free):
----------------------------------------
Firebase → Authentication → Sign-in method → Phone
→ "Phone numbers for testing"
→ +91 9876543210 / OTP: 123456

========================================
EOF
