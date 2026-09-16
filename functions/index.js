const crypto = require("crypto");
const { initializeApp } = require("firebase-admin/app");
const { getDatabase } = require("firebase-admin/database");
const { getFirestore } = require("firebase-admin/firestore");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { onRequest } = require("firebase-functions/v2/https");
const { setGlobalOptions } = require("firebase-functions/v2");
const { runOttLiveSync } = require("./ott-sync");
const { buildOttUsage, renderHtml } = require("./ott-usage");

const SYNC_POLICY = "idle-skip-v2";

initializeApp({
  databaseURL:
    process.env.FIREBASE_DATABASE_URL ||
    "https://ncrplt20-1c022-default-rtdb.asia-southeast1.firebasedatabase.app",
});

setGlobalOptions({
  region: "asia-southeast1",
  maxInstances: 1,
  timeoutSeconds: 240,
  memory: "512MiB",
});

/**
 * Har 2 minute. Live match na ho to Crick API skip — Blaze bill kam.
 */
exports.ottLiveSync = onSchedule(
  {
    schedule: "every 2 minutes",
    timeZone: "Asia/Kolkata",
    retryCount: 0,
  },
  async () => {
    const db = getDatabase();
    const result = await runOttLiveSync(db);
    console.log("ottLiveSync done", SYNC_POLICY, result);
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
      secondsPerBall: 10,
      clipAfterScoreSeconds: 5,
      clipWindow: "timestamp-5s to timestamp+5s",
      ...(snap.val() || {}),
    });
  } catch (err) {
    res.status(500).json({ running: false, error: err.message });
  }
});

/** Browser page: per-ball clip utilization */
exports.ottUsage = onRequest({ cors: true }, async (req, res) => {
  try {
    const db = getDatabase();
    const data = await buildOttUsage(db);
    const wantJson =
      String(req.query.format || "").toLowerCase() === "json" ||
      String(req.headers.accept || "").includes("application/json");
    if (wantJson) {
      res.json(data);
      return;
    }
    res.set("Content-Type", "text/html; charset=utf-8");
    res.set("Cache-Control", "no-store");
    res.status(200).send(renderHtml(data));
  } catch (err) {
    res.status(500).json({ ok: false, error: err.message || String(err) });
  }
});

function hashPin(uid, pin) {
  return crypto.createHash("sha256").update(`jbmr-pin-v1|${uid}|${pin}`).digest("hex");
}

function nationalPhone(raw) {
  const digits = String(raw || "").replace(/\D/g, "");
  return digits.length > 10 ? digits.slice(-10) : digits;
}

/** Fresh-install PIN login: phone + PIN without OTP when PIN already exists. */
exports.verifyPinLogin = onRequest(
  { cors: true, maxInstances: 20, timeoutSeconds: 20, memory: "256MiB" },
  async (req, res) => {
    if (req.method === "OPTIONS") {
      res.status(204).send("");
      return;
    }
    if (req.method !== "POST") {
      res.status(405).json({ ok: false, error: "POST required" });
      return;
    }
    const phone = nationalPhone(req.body?.phone);
    const pin = String(req.body?.pin || "").replace(/\D/g, "");
    if (phone.length !== 10 || pin.length !== 4) {
      res.status(400).json({ ok: false, error: "Enter a 10-digit number and 4-digit PIN" });
      return;
    }
    try {
      const db = getFirestore();
      const attemptRef = db.collection("pinAttempts").doc(phone);
      const attemptSnap = await attemptRef.get();
      const attempt = attemptSnap.data() || {};
      const now = Date.now();
      const windowMs = 15 * 60 * 1000;
      const count = attempt.at && now - attempt.at < windowMs ? attempt.count || 0 : 0;
      if (count >= 8) {
        res.status(429).json({ ok: false, error: "Too many attempts — try again later" });
        return;
      }

      const pinDoc = await db.collection("phonePins").doc(phone).get();
      const candidates = [];
      if (pinDoc.exists) {
        candidates.push({ uid: pinDoc.get("uid"), hash: pinDoc.get("pinHash") });
      }
      const byNational = await db.collection("users").where("phoneNational", "==", phone).limit(8).get();
      const byPinPhone = await db.collection("users").where("pinPhone", "==", phone).limit(8).get();
      for (const snap of [byNational, byPinPhone]) {
        snap.forEach((doc) => {
          candidates.push({ uid: doc.id, hash: doc.get("pinHash") });
        });
      }

      for (const row of candidates) {
        if (!row.uid || !row.hash) continue;
        if (row.hash === hashPin(row.uid, pin)) {
          await db.collection("phonePins").doc(phone).set(
            { uid: row.uid, pinHash: row.hash, updatedAt: new Date() },
            { merge: true }
          );
          await attemptRef.delete().catch(() => {});
          res.json({ ok: true, uid: row.uid, phone });
          return;
        }
      }

      await attemptRef.set({ count: count + 1, at: now });
      res.status(401).json({
        ok: false,
        error: "Incorrect PIN, or no PIN for this number. Use OTP to create one.",
      });
    } catch (err) {
      console.error("verifyPinLogin", err);
      res.status(500).json({ ok: false, error: err.message || String(err) });
    }
  }
);
