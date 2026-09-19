# ServerOTT on Hostinger (Express)

This package runs your OTT worker on Hostinger Node hosting using Express.

## Framework

- Express (Node.js 20+)
- Firebase Admin (RTDB)
- node-cron (optional in-process sync schedule)

## Endpoints

- `/` -> health page
- `/health` -> health page (or JSON with `?format=json`)
- `/ott/usage` -> usage HTML (or JSON with `?format=json`)
- `/ott/live-sync-now` -> manual sync trigger
- `/ott/worker-status` -> worker status JSON

## Setup

1. Upload `serverott/hostinger` folder to Hostinger app root.
2. Run:
   - `npm install`
3. Create `.env` from `.env.example`.
4. Start app:
   - `npm start`

## Env notes

- You must provide Firebase service account via one of:
  - `FIREBASE_SERVICE_ACCOUNT_JSON`
  - `FIREBASE_SERVICE_ACCOUNT_BASE64`
- Keep `ENABLE_INTERNAL_CRON=false` on shared hosting unless process stays always-on.
  - Better: call `/ott/live-sync-now` every minute from Hostinger Cron URL.

## Hostinger Cron recommendation

Use cron job every 1 minute:

```bash
curl -fsS https://YOUR-DOMAIN/ott/live-sync-now >/dev/null
```

This is more reliable than in-process cron if Hostinger app sleeps.
