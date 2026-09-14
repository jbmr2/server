#!/bin/bash
# Ek baar chalao — Firebase par OTT worker deploy (app band ho tab bhi sync + clip)
set -e
cd "$(dirname "$0")/.."
echo "→ Firebase login check..."
npx -y firebase-tools@latest login:list || npx -y firebase-tools@latest login
echo "→ Deploy functions to ncrplt20-1c022..."
npx -y firebase-tools@latest deploy --only functions --project ncrplt20-1c022
echo "✅ Done! Worker URLs:"
echo "   https://asia-southeast1-ncrplt20-1c022.cloudfunctions.net/ottWorkerStatus"
echo "   https://asia-southeast1-ncrplt20-1c022.cloudfunctions.net/ottLiveSyncNow"
