const { initializeApp } = require("firebase-admin/app");
const { getDatabase } = require("firebase-admin/database");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { onRequest } = require("firebase-functions/v2/https");
const { setGlobalOptions } = require("firebase-functions/v2");
const { runOttLiveSync } = require("./ott-sync");

initializeApp({
  databaseURL:
    process.env.FIREBASE_DATABASE_URL ||
    "https://ncrplt20-1c022-default-rtdb.asia-southeast1.firebasedatabase.app",
});

setGlobalOptions({
  region: "asia-southeast1",
  maxInstances: 3,
  timeoutSeconds: 300,
  memory: "512MiB",
});

/**
 * Har 1 minute — app band ho tab bhi live sync + auto clip.
 * Firebase Cloud Functions par hosted (24/7).
 */
exports.ottLiveSync = onSchedule(
  {
    schedule: "every 1 minutes",
    timeZone: "Asia/Kolkata",
    retryCount: 1,
  },
  async () => {
    const db = getDatabase();
    const result = await runOttLiveSync(db);
    console.log("ottLiveSync done", result);
    return result;
  }
);

/** Manual trigger / health check */
exports.ottLiveSyncNow = onRequest({ cors: true }, async (req, res) => {
  try {
    const db = getDatabase();
    const result = await runOttLiveSync(db);
    res.json({ ok: true, ...result });
  } catch (err) {
    console.error("ottLiveSyncNow error", err);
    res.status(500).json({ ok: false, error: err.message || String(err) });
  }
});

exports.ottWorkerStatus = onRequest({ cors: true }, async (req, res) => {
  try {
    const db = getDatabase();
    const snap = await db.ref("ott/worker").once("value");
    res.json({
      running: true,
      hostedOn: "Firebase Cloud Functions",
      ...(snap.val() || {}),
    });
  } catch (err) {
    res.status(500).json({ running: false, error: err.message });
  }
});
