const crypto = require("crypto");
const { initializeApp } = require("firebase-admin/app");
const { getDatabase } = require("firebase-admin/database");
const { getFirestore } = require("firebase-admin/firestore");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { onRequest } = require("firebase-functions/v2/https");
const { setGlobalOptions } = require("firebase-functions/v2");
const { runOttLiveSync } = require("./ott-sync");
const { buildOttUsage, renderHtml } = require("./ott-usage");
const { handleSendOtp, handleVerifyOtp } = require("./otp-2factor");

const SYNC_POLICY = "idle-skip-v2";

initializeApp({
  databaseURL:
    process.env.FIREBASE_DATABASE_URL ||
    "https://cloud-storage-eaca9-default-rtdb.europe-west1.firebasedatabase.app",
});

setGlobalOptions({
  region: "asia-southeast1",
  maxInstances: 1,
  timeoutSeconds: 240,
  memory: "512MiB",
});

/**
 * Har 1 minute. Live state jaldi reflect ho aur idle guard se cost control rahe.
 */
exports.ottLiveSync = onSchedule(
  {
    schedule: "every 1 minutes",
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

function healthBadge(ok) {
  return ok
    ? '<span style="color:#29d17d;font-weight:700">OK</span>'
    : '<span style="color:#ff5d73;font-weight:700">ISSUE</span>';
}

function renderHealthHtml(report) {
  const rows = report.checks
    .map(
      (c) => `
      <tr>
        <td>${c.name}</td>
        <td>${healthBadge(c.ok)}</td>
        <td>${c.detail || "-"}</td>
      </tr>`
    )
    .join("");
  return `<!doctype html>
<html>
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width,initial-scale=1" />
  <title>ServerOTT Health</title>
  <style>
    body{font-family:Inter,system-ui,Segoe UI,Arial,sans-serif;background:#090c12;color:#e7edf5;margin:0;padding:24px}
    .card{max-width:980px;margin:0 auto;background:#121826;border:1px solid #22324a;border-radius:14px;padding:18px}
    h1{margin:0 0 8px;font-size:24px}
    .meta{color:#9fb0c6;font-size:13px;margin-bottom:14px}
    table{width:100%;border-collapse:collapse}
    th,td{text-align:left;padding:10px;border-bottom:1px solid #26344b;font-size:14px;vertical-align:top}
    th{color:#9fb0c6;font-weight:600}
    .footer{margin-top:12px;color:#91a6bf;font-size:12px}
  </style>
</head>
<body>
  <div class="card">
    <h1>ServerOTT Health</h1>
    <div class="meta">
      Server: ${healthBadge(report.serverOk)} · Updated: ${report.now} · Region: asia-southeast1
    </div>
    <table>
      <thead>
        <tr><th>Check</th><th>Status</th><th>Details</th></tr>
      </thead>
      <tbody>${rows}</tbody>
    </table>
    <div class="footer">
      JSON version: <a href="?format=json" style="color:#66b7ff">?format=json</a>
    </div>
  </div>
</body>
</html>`;
}

async function checkUrlJSON(url, timeoutMs = 8000) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const res = await fetch(url, {
      headers: { Accept: "application/json" },
      signal: controller.signal,
    });
    return {
      ok: res.ok,
      status: res.status,
    };
  } finally {
    clearTimeout(timer);
  }
}

exports.serverOttHealth = onRequest({ cors: true, timeoutSeconds: 30 }, async (req, res) => {
  const checks = [];
  const now = new Date().toISOString();

  // 1) Firebase RTDB connectivity
  try {
    const db = getDatabase();
    const snap = await db.ref("ott/meta/updatedAt").once("value");
    checks.push({
      name: "Firebase RTDB",
      ok: true,
      detail: `connected · ott/meta/updatedAt=${snap.val() || "n/a"}`,
    });
  } catch (err) {
    checks.push({
      name: "Firebase RTDB",
      ok: false,
      detail: err?.message || String(err),
    });
  }

  // 2) Public scoring API reachability
  try {
    const apiUrl = `${CRICK_API}/api/tournaments/list-public?activeOnly=true`;
    const result = await checkUrlJSON(apiUrl, 10000);
    checks.push({
      name: "Scoring API",
      ok: result.ok,
      detail: `${apiUrl} -> HTTP ${result.status}`,
    });
  } catch (err) {
    checks.push({
      name: "Scoring API",
      ok: false,
      detail: err?.message || String(err),
    });
  }

  // 3) Cloudflare Stream auth/config
  const hasStreamConfig = Boolean(process.env.STREAM_ACCOUNT_ID && process.env.STREAM_API_TOKEN);
  if (!hasStreamConfig) {
    checks.push({
      name: "Cloudflare Stream",
      ok: false,
      detail: "Missing STREAM_ACCOUNT_ID or STREAM_API_TOKEN",
    });
  } else {
    try {
      const url = `https://api.cloudflare.com/client/v4/accounts/${process.env.STREAM_ACCOUNT_ID}/stream`;
      const result = await checkUrlJSON(url, 10000);
      checks.push({
        name: "Cloudflare Stream",
        ok: result.ok,
        detail: `auth test -> HTTP ${result.status}`,
      });
    } catch (err) {
      checks.push({
        name: "Cloudflare Stream",
        ok: false,
        detail: err?.message || String(err),
      });
    }
  }

  // 4) R2 config presence
  const r2Ready = Boolean(
    process.env.R2_ACCOUNT_ID &&
      process.env.R2_ACCESS_KEY_ID &&
      process.env.R2_SECRET_ACCESS_KEY &&
      process.env.R2_BUCKET
  );
  checks.push({
    name: "Cloudflare R2",
    ok: r2Ready,
    detail: r2Ready ? `bucket=${process.env.R2_BUCKET}` : "R2 env missing",
  });

  const report = {
    ok: checks.every((c) => c.ok),
    serverOk: true,
    now,
    checks,
  };
  const wantJson =
    String(req.query.format || "").toLowerCase() === "json" ||
    String(req.headers.accept || "").includes("application/json");
  if (wantJson) {
    res.json(report);
    return;
  }
  res.set("Content-Type", "text/html; charset=utf-8");
  res.set("Cache-Control", "no-store");
  res.status(200).send(renderHealthHtml(report));
});

function hashPin(uid, pin) {
  return crypto.createHash("sha256").update(`jbmr-pin-v1|${uid}|${pin}`).digest("hex");
}

function nationalPhone(raw) {
  const digits = String(raw || "").replace(/\D/g, "");
  return digits.length > 10 ? digits.slice(-10) : digits;
}

exports.sendOtp = onRequest(
  { cors: true, maxInstances: 20, timeoutSeconds: 30, memory: "256MiB" },
  handleSendOtp
);

exports.verifyOtp = onRequest(
  { cors: true, maxInstances: 20, timeoutSeconds: 30, memory: "256MiB" },
  handleVerifyOtp
);

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

/** Admin: delete all Firebase OTT match data (not user/PIN accounts). */
exports.clearOttMatchData = onRequest(
  { cors: true, maxInstances: 1, timeoutSeconds: 120, memory: "256MiB" },
  async (req, res) => {
    if (req.method === "OPTIONS") {
      res.status(204).send("");
      return;
    }
    if (req.method !== "POST") {
      res.status(405).json({ ok: false, error: "POST required" });
      return;
    }
    const auth = String(req.get("Authorization") || "");
    if (!auth.startsWith("Bearer ") || auth.length < 40) {
      res.status(401).json({ ok: false, error: "Admin login required" });
      return;
    }
    const confirm = String(req.body?.confirm || "").trim();
    if (confirm !== "CLEAR MATCHES") {
      res.status(400).json({ ok: false, error: "Type CLEAR MATCHES to confirm" });
      return;
    }

    try {
      const db = getDatabase();
      const tournamentsSnap = await db.ref("ott/tournaments").once("value");
      const tournaments = tournamentsSnap.val() || {};
      let matchCount = 0;
      const updates = {};

      for (const [tid, t] of Object.entries(tournaments)) {
        const matches = (t && t.matches) || {};
        matchCount += Object.keys(matches).length;
        updates[`ott/tournaments/${tid}/matches`] = null;
      }

      updates["ott/matchDetails"] = null;
      updates["ott/highlights"] = null;
      updates["ott/meta/updatedAt"] = new Date().toISOString();
      updates["ott/meta/lastMatchClearAt"] = new Date().toISOString();
      updates["ott/worker/lastClearAt"] = new Date().toISOString();
      updates["ott/worker/lastLogs"] = [`cleared ${matchCount} matches from Firebase`];

      await db.ref().update(updates);
      res.json({
        ok: true,
        deletedMatches: matchCount,
        deletedTournaments: Object.keys(tournaments).length,
        note: "User accounts / PINs were not deleted. Live sync can refill live matches in a few minutes.",
      });
    } catch (err) {
      console.error("clearOttMatchData", err);
      res.status(500).json({ ok: false, error: err.message || String(err) });
    }
  }
);
