/* eslint-disable no-console */
const path = require("path");
const express = require("express");
const { initializeApp, cert } = require("firebase-admin/app");
const { getDatabase } = require("firebase-admin/database");

require("dotenv").config({ path: path.join(__dirname, ".env") });

const { runOttLiveSync, CRICK_API } = require("../../functions/ott-sync");
const { buildOttUsage, renderHtml } = require("../../functions/ott-usage");

let cron = null;
try {
  cron = require("node-cron");
} catch {
  cron = null;
}

const FIREBASE_DATABASE_URL =
  process.env.FIREBASE_DATABASE_URL ||
  "https://cloud-storage-eaca9-default-rtdb.europe-west1.firebasedatabase.app";

let firebaseAppInitialized = false;

function getServiceAccountFromEnv() {
  const rawJson = process.env.FIREBASE_SERVICE_ACCOUNT_JSON || "";
  const rawBase64 = process.env.FIREBASE_SERVICE_ACCOUNT_BASE64 || "";
  if (rawJson.trim()) {
    return JSON.parse(rawJson);
  }
  if (rawBase64.trim()) {
    const decoded = Buffer.from(rawBase64, "base64").toString("utf8");
    return JSON.parse(decoded);
  }
  return null;
}

function initFirebase() {
  if (firebaseAppInitialized) return;
  const serviceAccount = getServiceAccountFromEnv();
  const config = { databaseURL: FIREBASE_DATABASE_URL };
  if (serviceAccount) {
    config.credential = cert(serviceAccount);
  }
  initializeApp(config);
  firebaseAppInitialized = true;
}

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
      Server: ${healthBadge(report.serverOk)} · Updated: ${report.now} · Framework: Express
    </div>
    <table>
      <thead>
        <tr><th>Check</th><th>Status</th><th>Details</th></tr>
      </thead>
      <tbody>${rows}</tbody>
    </table>
    <div class="footer">JSON: <a href="/health?format=json" style="color:#66b7ff">/health?format=json</a></div>
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
    return { ok: res.ok, status: res.status };
  } finally {
    clearTimeout(timer);
  }
}

async function buildHealthReport() {
  const checks = [];
  const now = new Date().toISOString();

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

  const hasStreamConfig = Boolean(process.env.STREAM_ACCOUNT_ID && process.env.STREAM_API_TOKEN);
  checks.push({
    name: "Cloudflare Stream Config",
    ok: hasStreamConfig,
    detail: hasStreamConfig ? "token/account set" : "Missing STREAM_ACCOUNT_ID or STREAM_API_TOKEN",
  });

  const r2Ready = Boolean(
    process.env.R2_ACCOUNT_ID &&
      process.env.R2_ACCESS_KEY_ID &&
      process.env.R2_SECRET_ACCESS_KEY &&
      process.env.R2_BUCKET
  );
  checks.push({
    name: "Cloudflare R2 Config",
    ok: r2Ready,
    detail: r2Ready ? `bucket=${process.env.R2_BUCKET}` : "R2 env missing",
  });

  return {
    ok: checks.every((c) => c.ok),
    serverOk: true,
    now,
    checks,
  };
}

initFirebase();

const app = express();
app.use(express.json({ limit: "1mb" }));

app.get("/", async (req, res) => {
  const report = await buildHealthReport();
  res.set("Content-Type", "text/html; charset=utf-8");
  res.status(200).send(renderHealthHtml(report));
});

app.get("/health", async (req, res) => {
  const report = await buildHealthReport();
  const wantJson =
    String(req.query.format || "").toLowerCase() === "json" ||
    String(req.headers.accept || "").includes("application/json");
  if (wantJson) return res.json(report);
  res.set("Content-Type", "text/html; charset=utf-8");
  return res.status(200).send(renderHealthHtml(report));
});

app.get("/ott/usage", async (req, res) => {
  try {
    const db = getDatabase();
    const data = await buildOttUsage(db);
    const wantJson =
      String(req.query.format || "").toLowerCase() === "json" ||
      String(req.headers.accept || "").includes("application/json");
    if (wantJson) return res.json(data);
    res.set("Content-Type", "text/html; charset=utf-8");
    res.set("Cache-Control", "no-store");
    return res.status(200).send(renderHtml(data));
  } catch (err) {
    return res.status(500).json({ ok: false, error: err?.message || String(err) });
  }
});

app.all("/ott/live-sync-now", async (req, res) => {
  try {
    const db = getDatabase();
    const result = await runOttLiveSync(db);
    return res.json({ ok: true, ...result });
  } catch (err) {
    return res.status(500).json({ ok: false, error: err?.message || String(err) });
  }
});

app.get("/ott/worker-status", async (req, res) => {
  try {
    const db = getDatabase();
    const snap = await db.ref("ott/worker").once("value");
    return res.json({
      running: true,
      hostedOn: "Hostinger (Express)",
      secondsPerBall: 10,
      clipAfterScoreSeconds: 5,
      clipWindow: "timestamp-5s to timestamp+5s",
      ...(snap.val() || {}),
    });
  } catch (err) {
    return res.status(500).json({ running: false, error: err?.message || String(err) });
  }
});

const enableCron = String(process.env.ENABLE_INTERNAL_CRON || "false").toLowerCase() === "true";
if (enableCron && cron) {
  cron.schedule("* * * * *", async () => {
    try {
      const db = getDatabase();
      const result = await runOttLiveSync(db);
      console.log("ottLiveSync (internal cron) done", result);
    } catch (err) {
      console.error("ottLiveSync (internal cron) failed", err);
    }
  });
} else if (enableCron && !cron) {
  console.warn("ENABLE_INTERNAL_CRON=true but node-cron not installed; skipping internal scheduler");
}

const port = Number(process.env.PORT || 3000);
app.listen(port, () => {
  console.log(`ServerOTT Hostinger running on port ${port}`);
});
