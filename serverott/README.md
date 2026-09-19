# ServerOTT

Deploy-ready Firebase Functions package for JBMR OTT live sync + ball-by-ball clip cutting.

## What this runs

- `ottLiveSync` (scheduled, every 1 minute)
  - Reads live matches
  - Syncs score + balls to Firebase RTDB
  - Cuts per-ball clips (`timestamp-5s` to `timestamp+5s`)
  - Saves clip URL to `ott/tournaments/{tid}/matches/{mid}/balls/{ballId}`
- `ottLiveSyncNow` (manual trigger)
- `ottWorkerStatus` (worker health)
- `ottUsage` (usage and pipeline dashboard)

Code is in the existing `functions/` directory of this repo.

## One-time setup

1. Install Node.js 20 and Firebase CLI:
   - `npm i -g firebase-tools`
2. Login:
   - `firebase login`
3. Select project:
   - `firebase use cloud-storage-eaca9`

## Configure secrets/env

Create `functions/.env` (template in `serverott/.env.example`).

Minimum required:

- `FIREBASE_DATABASE_URL`
- `STREAM_ACCOUNT_ID`
- `STREAM_API_TOKEN`
- `STREAM_CUSTOMER_SUBDOMAIN`
- `R2_ACCOUNT_ID`
- `R2_ACCESS_KEY_ID`
- `R2_SECRET_ACCESS_KEY`
- `R2_BUCKET`
- `R2_PUBLIC_BASE_URL`

Optional:

- `CRICK_API_BASE`

## Deploy

From repo root:

```bash
cd functions
npm install
firebase deploy --only functions --project cloud-storage-eaca9
```

## Verify after deploy

- `https://asia-southeast1-cloud-storage-eaca9.cloudfunctions.net/ottWorkerStatus`
- `https://asia-southeast1-cloud-storage-eaca9.cloudfunctions.net/ottUsage`
- Manual sync trigger:
  - `https://asia-southeast1-cloud-storage-eaca9.cloudfunctions.net/ottLiveSyncNow`

## Important

- Auto clip works even if admin app/PC is OFF (because worker runs on cloud functions).
- Make sure match node has stream fields:
  - `streamLiveInputId`
  - `streamStartedAt`
  - `liveUrl`
