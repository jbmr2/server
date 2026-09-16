function str(v) {
  if (v == null) return "";
  if (typeof v === "string") return v;
  if (typeof v === "number" || typeof v === "boolean") return String(v);
  return "";
}

function objectMap(any) {
  if (any && typeof any === "object" && !Array.isArray(any)) {
    const out = {};
    for (const [k, v] of Object.entries(any)) {
      if (v && typeof v === "object" && !Array.isArray(v)) out[k] = v;
    }
    return out;
  }
  return {};
}

const STREAM_USD_PER_1000_DELIVERED_MIN = 1;
const INR_PER_USD = 88;
const CLIP_SECONDS_DEFAULT = 10;

function usdDelivered(seconds) {
  const minutes = Math.max(0, Number(seconds) || 0) / 60;
  return (minutes / 1000) * STREAM_USD_PER_1000_DELIVERED_MIN;
}

function moneyPair(usd) {
  const n = Number(usd) || 0;
  const inr = n * INR_PER_USD;
  if (n < 0.01) return `$${n.toFixed(6)} · ₹${inr.toFixed(4)}`;
  return `$${n.toFixed(4)} · ₹${inr.toFixed(2)}`;
}

function parseClipQuery(videoUrl) {
  const url = str(videoUrl);
  const time = url.match(/[?&]time=(\d+(?:\.\d+)?)s/i);
  const duration = url.match(/[?&]duration=(\d+(?:\.\d+)?)s/i);
  return {
    startSeconds: time ? Number(time[1]) : 0,
    durationSeconds: duration ? Number(duration[1]) : 0,
  };
}

function isLive(status) {
  const s = str(status).toLowerCase();
  return s === "live" || s === "in progress";
}

function ballLabel(over, ball) {
  const o = Number(over) || 0;
  const b = Number(ball) || 1;
  if (b >= 6) return `${o + 1}.0`;
  return `${o}.${b}`;
}

function formatBytes(n) {
  const v = Number(n) || 0;
  if (v < 1024) return `${v} B`;
  if (v < 1024 * 1024) return `${(v / 1024).toFixed(1)} KB`;
  return `${(v / (1024 * 1024)).toFixed(1)} MB`;
}

function collectUsage(ott) {
  const tournaments = objectMap(ott?.tournaments);
  const matches = [];
  let totalBalls = 0;
  let clippedBalls = 0;
  let totalClipSeconds = 0;
  let totalClipBytes = 0;

  for (const [tournamentId, t] of Object.entries(tournaments)) {
    for (const [matchId, m] of Object.entries(objectMap(t.matches))) {
      const ballsIn = objectMap(m.balls);
      const balls = Object.values(ballsIn)
        .sort((a, b) => (a.sortKey ?? 0) - (b.sortKey ?? 0))
        .map((b) => {
          const parsed = parseClipQuery(b.videoUrl);
          const duration =
            Number(b.clipDurationSeconds) > 0
              ? Number(b.clipDurationSeconds)
              : parsed.durationSeconds || (str(b.videoUrl) ? CLIP_SECONDS_DEFAULT : 0);
          const start =
            Number(b.clipStartSeconds) > 0
              ? Number(b.clipStartSeconds)
              : parsed.startSeconds;
          const hasClip = Boolean(str(b.videoUrl));
          const dur = hasClip ? duration || CLIP_SECONDS_DEFAULT : 0;
          return {
            id: str(b.id),
            innings: b.innings ?? 1,
            over: b.over ?? 0,
            ball: b.ball ?? 1,
            label: ballLabel(b.over, b.ball),
            runs: b.runs ?? 0,
            isWicket: Boolean(b.isWicket),
            hasClip,
            startSeconds: start,
            durationSeconds: dur,
            bytes: Number(b.clipBytes) || 0,
            clipAt: str(b.clipAt),
            createCostUsd: hasClip ? usdDelivered(dur) : 0,
            videoUrl: str(b.videoUrl),
            viaR2: Boolean(str(b.videoPath)),
            steps: {
              scored: true,
              synced: true,
              cutting: !hasClip,
              cut: hasClip,
              ott: hasClip,
            },
          };
        });

      const clipCount = balls.filter((b) => b.hasClip).length;
      const clipSeconds = balls.reduce((s, b) => s + (b.durationSeconds || 0), 0);
      const clipBytes = balls.reduce((s, b) => s + (b.bytes || 0), 0);
      totalBalls += balls.length;
      clippedBalls += clipCount;
      totalClipSeconds += clipSeconds;
      totalClipBytes += clipBytes;

      matches.push({
        tournamentId,
        tournamentName: str(t.name) || tournamentId,
        matchId,
        title:
          str(m.title) ||
          `${str(m.team1?.shortName || m.team1?.name)} vs ${str(
            m.team2?.shortName || m.team2?.name
          )}`,
        status: str(m.status),
        live: isLive(m.status),
        liveUrl: str(m.liveUrl),
        recordingVideoId: str(m.streamRecordingVideoId),
        liveInputId: str(m.streamLiveInputId),
        ballCount: balls.length,
        clipCount,
        clipSeconds,
        clipBytes,
        createCostUsd: usdDelivered(clipSeconds),
        secondsPerBall: CLIP_SECONDS_DEFAULT,
        balls,
      });
    }
  }

  matches.sort((a, b) => Number(b.live) - Number(a.live));

  const oneClipUsd = usdDelivered(CLIP_SECONDS_DEFAULT);
  const createCostUsd = usdDelivered(totalClipSeconds);

  return {
    secondsPerBall: CLIP_SECONDS_DEFAULT,
    pipeline: [
      { id: 1, title: "Scoring", detail: "Scorer over / ball / runs save karta hai (Crick API)." },
      { id: 2, title: "Firebase sync", detail: "Har 2 min ottLiveSync ball Firebase RTDB pe likhta hai." },
      { id: 3, title: "Cut window", detail: "timestamp−5s se timestamp+5s, max 10s. Cost still 10s delivered." },
      { id: 4, title: "Cloudflare clip", detail: "Recording se clip.mp4 download — yahi 10s deliver bill hota hai." },
      { id: 5, title: "OTT", detail: "videoUrl save. App ball pe clip chalati hai, warna live HLS." },
    ],
    pricing: {
      rate: "$1 per 1,000 minutes delivered (Cloudflare Stream)",
      storageNote:
        "Instant clip extra storage nahi. Live recording alag: $5 / 1000 min stored. Live viewers alag bill.",
      inrPerUsd: INR_PER_USD,
      secondsPerClip: CLIP_SECONDS_DEFAULT,
      oneClipCreateUsd: oneClipUsd,
      oneClipWatchUsd: oneClipUsd,
      hundredClipsUsd: oneClipUsd * 100,
      thousandClipsUsd: oneClipUsd * 1000,
    },
    totals: {
      matches: matches.length,
      liveMatches: matches.filter((m) => m.live).length,
      balls: totalBalls,
      clips: clippedBalls,
      pending: Math.max(0, totalBalls - clippedBalls),
      clipSeconds: totalClipSeconds,
      clipMinutes: Math.round((totalClipSeconds / 60) * 10) / 10,
      clipBytes: totalClipBytes,
      secondsPerBall: CLIP_SECONDS_DEFAULT,
      createCostUsd,
      createCostInr: createCostUsd * INR_PER_USD,
    },
    worker: ott?.worker || {},
    matches,
  };
}

function escapeHtml(s) {
  return str(s)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

function stepDots(b) {
  const items = [
    ["1 Score", b.steps.scored],
    ["2 Sync", b.steps.synced],
    ["3 Cut 10s", b.steps.cut],
    ["4 OTT", b.steps.ott],
  ];
  return `<div class="pips">${items
    .map(
      ([label, on]) =>
        `<span class="pip ${on ? "on" : b.steps.cutting && label.startsWith("3") ? "wait" : ""}">${escapeHtml(
          label
        )}</span>`
    )
    .join("")}</div>`;
}

function renderHtml(data) {
  const t = data.totals;
  const p = data.pricing;
  const worker = data.worker || {};
  const logs = Array.isArray(worker.lastLogs)
    ? worker.lastLogs
    : worker.lastLogs && typeof worker.lastLogs === "object"
      ? Object.values(worker.lastLogs)
      : [];
  const pipeline = (data.pipeline || [])
    .map(
      (s) => `<li><b>Step ${s.id} · ${escapeHtml(s.title)}</b><span>${escapeHtml(s.detail)}</span></li>`
    )
    .join("");

  const logRows = logs
    .slice()
    .reverse()
    .map((line) => {
      const text = str(line);
      const cls = /FAIL/i.test(text) ? "fail" : /OK|clip /i.test(text) ? "ok" : "";
      return `<li class="${cls}">${escapeHtml(text)}</li>`;
    })
    .join("");

  const matchBlocks = data.matches
    .map((m) => {
      const rows = m.balls
        .map((b) => {
          const result = b.isWicket ? "W" : String(b.runs);
          const cut = b.hasClip
            ? `cut t=${Math.floor(b.startSeconds)}s → ${Math.floor(b.startSeconds) + b.durationSeconds}s (${b.durationSeconds}s)`
            : "waiting — video yahan cut hoga (timestamp−5s se timestamp+5s)";
          const cost = b.hasClip ? moneyPair(b.createCostUsd) : "—";
          const play = b.videoUrl
            ? `<a href="${escapeHtml(b.videoUrl)}" target="_blank" rel="noreferrer">play clip</a>`
            : "live HLS";
          return `<tr>
            <td>${escapeHtml(b.label)}</td>
            <td>${escapeHtml(result)}</td>
            <td>${stepDots(b)}</td>
            <td>${escapeHtml(cut)}</td>
            <td>${escapeHtml(cost)}</td>
            <td>${play}</td>
          </tr>`;
        })
        .join("");
      return `<article class="match">
        <header>
          <span class="${m.live ? "live" : "done"}">${m.live ? "LIVE" : escapeHtml(m.status || "—")}</span>
          <h2>${escapeHtml(m.title)}</h2>
          <p>${m.clipCount}/${m.ballCount} clips · ${m.clipSeconds}s cut · banana: ${moneyPair(
            m.createCostUsd
          )}</p>
        </header>
        <table>
          <thead>
            <tr>
              <th>Ball</th><th>Runs</th><th>Pipeline</th><th>Video cut</th><th>1 clip cost</th><th>Video</th>
            </tr>
          </thead>
          <tbody>${rows || `<tr><td colspan="6">Abhi koi ball nahi</td></tr>`}</tbody>
        </table>
      </article>`;
    })
    .join("");

  return `<!doctype html>
<html lang="hi">
<head>
  <meta charset="utf-8"/>
  <meta name="viewport" content="width=device-width,initial-scale=1"/>
  <meta http-equiv="refresh" content="20"/>
  <title>JBMR clip pipeline + cost</title>
  <style>
    :root { --ink:#e8f4ff; --muted:#8aa0b8; --bg:#07090d; --card:#10161e; --line:#1c2733; --live:#ff3355; --ok:#3ee08a; --accent:#00b4d8; --wait:#f5c542; }
    * { box-sizing:border-box; }
    body { margin:0; font-family: "IBM Plex Sans", ui-sans-serif, system-ui; background:
      radial-gradient(1200px 500px at 10% -10%, #12324a 0%, transparent 50%), var(--bg); color:var(--ink); }
    main { max-width: 1180px; margin: 0 auto; padding: 28px 18px 80px; }
    h1 { font-size: 28px; letter-spacing: -0.04em; margin: 0 0 6px; }
    .sub { color:var(--muted); margin:0 0 22px; }
    .grid { display:grid; grid-template-columns: repeat(auto-fit,minmax(150px,1fr)); gap:10px; margin-bottom:18px; }
    .stat { background:var(--card); border:1px solid var(--line); border-radius:14px; padding:14px; }
    .stat b { display:block; font-size:20px; color:var(--accent); }
    .stat span { color:var(--muted); font-size:12px; }
    .cost { border-color: #1e4d5c; background: linear-gradient(180deg,#13242c,var(--card)); }
    .cost b { color:#7ef0c3; }
    .how, .logs { background:var(--card); border:1px solid var(--line); border-radius:16px; padding:16px 18px; margin-bottom:18px; }
    .how ol { display:grid; gap:10px; margin:10px 0 0; padding:0; list-style:none; counter-reset:s; }
    .how li { display:flex; flex-direction:column; gap:4px; padding:10px 12px; border:1px solid var(--line); border-radius:12px; background:#0c1218; }
    .how li b { color:var(--accent); }
    .how li span { color:var(--muted); font-size:13px; }
    .logs ul { margin:8px 0 0; padding:0; list-style:none; font-family: ui-monospace, Menlo, monospace; font-size:12px; }
    .logs li { padding:6px 0; border-bottom:1px solid var(--line); color:var(--muted); }
    .logs li.ok { color:var(--ok); }
    .logs li.fail { color:#ff6b6b; }
    .match { background:var(--card); border:1px solid var(--line); border-radius:16px; padding:16px; margin-bottom:16px; }
    .match h2 { margin:8px 0 4px; font-size:18px; }
    .match header p { margin:0; color:var(--muted); font-size:13px; }
    .live { background:var(--live); color:#fff; font-size:10px; font-weight:800; padding:3px 8px; border-radius:999px; }
    .done { background:#243041; color:var(--muted); font-size:10px; font-weight:800; padding:3px 8px; border-radius:999px; }
    table { width:100%; border-collapse:collapse; margin-top:12px; font-size:12px; }
    th { text-align:left; color:var(--muted); font-weight:600; padding:8px 6px; border-bottom:1px solid var(--line); }
    td { padding:9px 6px; border-bottom:1px solid var(--line); vertical-align:top; }
    .pips { display:flex; flex-wrap:wrap; gap:4px; }
    .pip { font-size:10px; font-weight:700; padding:3px 6px; border-radius:999px; background:#243041; color:var(--muted); }
    .pip.on { background:#143d2a; color:var(--ok); }
    .pip.wait { background:#3d3214; color:var(--wait); }
    .foot { color:var(--muted); font-size:12px; margin-top:18px; }
    a { color:var(--accent); }
  </style>
</head>
<body>
  <main>
    <h1>Scoring pipeline + clip cost</h1>
    <p class="sub">Step by step: score → Firebase → 10s cut → OTT. Worker ${escapeHtml(
      worker.lastRunAt || "—"
    )} · last clipped ${escapeHtml(String(worker.lastClippedBalls ?? 0))} · page 20s auto refresh</p>

    <div class="grid">
      <div class="stat cost"><b>${moneyPair(p.oneClipCreateUsd)}</b><span>1 clip banana (10s MP4 download)</span></div>
      <div class="stat cost"><b>${moneyPair(p.oneClipWatchUsd)}</b><span>1 baar user play (same 10s deliver)</span></div>
      <div class="stat cost"><b>${moneyPair(t.createCostUsd)}</b><span>Ab tak clips banane ki Stream cost</span></div>
      <div class="stat"><b>${t.clips}</b><span>Clips ready</span></div>
      <div class="stat"><b>${t.pending}</b><span>Pending (abhi live / cut wait)</span></div>
      <div class="stat"><b>${t.secondsPerBall}s</b><span>Max cut / ball</span></div>
    </div>

    <section class="how">
      <h2 style="margin:0;font-size:16px;">Scoring → video cut (step by step)</h2>
      <ol>${pipeline}</ol>
      <p class="sub" style="margin:12px 0 0">Cloudflare rate: ${escapeHtml(p.rate)}. ${escapeHtml(
        p.storageNote
      )} 100 clips ≈ ${moneyPair(p.hundredClipsUsd)}. 1000 clips ≈ ${moneyPair(p.thousandClipsUsd)}.</p>
    </section>

    <section class="logs">
      <h2 style="margin:0;font-size:16px;">Abhi kya ho raha hai (ottLiveSync logs)</h2>
      <ul>${logRows || "<li>Abhi log nahi — scoring start hone ke baad yahan clip OK / FAIL dikhega.</li>"}</ul>
    </section>

    ${matchBlocks || `<p class="sub">Koi OTT match nahi.</p>`}
    <p class="foot">JSON: <a href="?format=json">?format=json</a> · Live HLS viewers ka bill alag hai. Yeh number sirf <b>clip.mp4 banana + clip play</b> ka Stream delivery hai ($1 / 1000 min).</p>
  </main>
</body>
</html>`;
}

async function buildOttUsage(db) {
  const snap = await db.ref("ott").once("value");
  return collectUsage(snap.val() || {});
}

module.exports = {
  collectUsage,
  parseClipQuery,
  buildOttUsage,
  renderHtml,
  formatBytes,
  usdDelivered,
  moneyPair,
};
