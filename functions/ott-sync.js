const CRICK_API =
  process.env.CRICK_API_BASE ||
  "https://crickdbmodule-api-144271912366.asia-south1.run.app";

const STREAM = {
  accountId: process.env.STREAM_ACCOUNT_ID || "",
  apiToken: process.env.STREAM_API_TOKEN || "",
  subdomain: process.env.STREAM_CUSTOMER_SUBDOMAIN || "febottgr27fxjy24",
};

const R2 = {
  accountId: process.env.R2_ACCOUNT_ID || "",
  accessKeyId: process.env.R2_ACCESS_KEY_ID || "",
  secretAccessKey: process.env.R2_SECRET_ACCESS_KEY || "",
  bucket: process.env.R2_BUCKET || "cricket-videos",
  publicBase: (process.env.R2_PUBLIC_BASE_URL || "").replace(/\/$/, ""),
};

/** [timestamp − 5s, timestamp + 5s]. Max 10s. Score ke 5s baad cut so shot/boundary complete. */
const CLIP_DURATION_SECONDS = 10;
const CLIP_AFTER_SCORE_SECONDS = 5;
/** end = elapsed − endLag → −5 means end at timestamp + 5s. */
const CLIP_END_LAG_SECONDS = -CLIP_AFTER_SCORE_SECONDS;

function str(v) {
  if (v == null) return "";
  if (typeof v === "string") return v;
  if (typeof v === "number" || typeof v === "boolean") return String(v);
  return "";
}

function isLive(status) {
  const s = str(status).toLowerCase();
  return s === "live" || s === "in progress";
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

function normalizeOvers(value) {
  const v = Number(value) || 0;
  let overs = Math.floor(v);
  let balls = Math.round((v - overs) * 10);
  while (balls >= 6) {
    overs += 1;
    balls -= 6;
  }
  return overs + Math.max(0, balls) / 10;
}

function parseCompleteBalls(matchId, root) {
  const arr = root?.ballByBall;
  if (!Array.isArray(arr)) return [];
  return arr
    .map((bd) => {
      let id = str(bd.id);
      if (!id) {
        id = `i${bd.innings ?? 1}-o${bd.overNumber ?? bd.over ?? 0}-b${bd.ballNumber ?? bd.ball ?? 1}`;
      }
      return {
        id,
        matchId,
        innings: bd.innings ?? 1,
        over: bd.overNumber ?? bd.over ?? 0,
        ball: bd.ballNumber ?? bd.ball ?? 1,
        runs: bd.batRuns ?? bd.runs ?? 0,
        isWicket: Boolean(bd.wicket ?? bd.isWicket),
        note: str(bd.note) || str(bd.shotName),
        videoUrl: str(bd.videoUrl),
        videoPath: str(bd.videoPath),
      };
    })
    .sort((a, b) => {
      const ak = a.innings * 10000 + a.over * 10 + a.ball;
      const bk = b.innings * 10000 + b.over * 10 + b.ball;
      return ak - bk;
    });
}

function buildFirebaseMatch(md, existingM, complete) {
  const mid = str(md.matchId);
  const ballsFromAPI = parseCompleteBalls(mid, complete ?? {});
  const existingBalls = objectMap(existingM.balls);
  const ballsOut = {};

  for (const ball of ballsFromAPI) {
    const old =
      existingBalls[ball.id] ||
      Object.values(existingBalls).find(
        (row) =>
          row.innings === ball.innings &&
          row.over === ball.over &&
          row.ball === ball.ball
      );
    ballsOut[ball.id] = {
      id: ball.id,
      innings: ball.innings,
      over: ball.over,
      ball: ball.ball,
      runs: ball.runs,
      isWicket: ball.isWicket,
      note: ball.note,
      videoUrl: str(old?.videoUrl) || ball.videoUrl,
      videoPath: str(old?.videoPath) || ball.videoPath,
      sortKey: ball.innings * 10000 + ball.over * 10 + ball.ball,
    };
    if (old?.clipStartSeconds != null) ballsOut[ball.id].clipStartSeconds = old.clipStartSeconds;
    if (old?.clipDurationSeconds != null) ballsOut[ball.id].clipDurationSeconds = old.clipDurationSeconds;
    if (old?.clipBytes != null) ballsOut[ball.id].clipBytes = old.clipBytes;
    if (old?.clipAt) ballsOut[ball.id].clipAt = old.clipAt;
    if (old?.clipAfterScoreSeconds != null) {
      ballsOut[ball.id].clipAfterScoreSeconds = old.clipAfterScoreSeconds;
    }
  }

  const team1 = md.team1 ?? {};
  const team2 = md.team2 ?? {};
  const result = md.result ?? {};
  const matchRow = {
    matchId: mid,
    matchSeq: md.matchSeq ?? 0,
    stage: str(md.stage),
    venue: str(md.venue),
    scheduledAt: str(md.scheduledAt),
    thumbnailUrl: str(md.thumbnailUrl),
    title: str(md.title),
    liveUrl: str(existingM.liveUrl) || str(md.liveUrl),
    highlightUrl: str(existingM.highlightUrl) || str(md.highlightUrl),
    team1: {
      name: str(team1.name) || "Team A",
      shortName: str(team1.shortName),
      logoUrl: str(team1.logoUrl),
    },
    team2: {
      name: str(team2.name) || "Team B",
      shortName: str(team2.shortName),
      logoUrl: str(team2.logoUrl),
    },
    result: {
      summaryText: str(result.summaryText),
      winnerShortName: str(result.winnerShortName),
    },
    innings: (complete?.innings ?? md.innings ?? []).map((inn) => ({
      inningsNumber: inn.inningsNumber ?? inn.number ?? 0,
      teamName: str(inn.teamName) || str(inn.battingTeamName),
      teamShortName: str(inn.teamShortName) || str(inn.battingTeamShortName),
      runs: inn.runs ?? 0,
      wickets: inn.wickets ?? 0,
      overs: normalizeOvers(inn.overs ?? 0),
    })),
    balls: ballsOut,
    status: str(complete?.matchInfo?.status) || str(md.status) || "scheduled",
  };

  if (isLive(existingM.status) && str(existingM.liveUrl)) matchRow.status = "live";
  if (isLive(matchRow.status)) matchRow.status = "live";

  for (const key of [
    "streamLiveInputId",
    "streamRtmpUrl",
    "streamRtmpKey",
    "streamSrtUrl",
    "streamSrtKey",
    "streamCustomerSubdomain",
    "streamStartedAt",
    "streamRecordingVideoId",
    "streamRecordingStartedAt",
  ]) {
    const v = str(existingM[key]);
    if (v) matchRow[key] = v;
  }

  return { matchRow, complete };
}

function clipUsesLiveInputId(videoUrl, liveInputId) {
  const url = str(videoUrl);
  const inputId = str(liveInputId);
  return Boolean(url && inputId && url.includes(`/${inputId}/clip.mp4`));
}

function clipDurationFromUrl(videoUrl) {
  const m = str(videoUrl).match(/[?&]duration=(\d+(?:\.\d+)?)s/i);
  return m ? Number(m[1]) : 0;
}

function ballNeedsClip(ball, liveInputId) {
  const url = str(ball?.videoUrl);
  if (!url) return true;
  // Instant clips must use the recording UID, not the live input id.
  if (clipUsesLiveInputId(url, liveInputId)) return true;
  const saved = Number(ball?.clipDurationSeconds) || 0;
  const fromUrl = clipDurationFromUrl(url);
  const duration = saved > 0 ? saved : fromUrl;
  if (duration !== CLIP_DURATION_SECONDS) return true;
  const after = Number(ball?.clipAfterScoreSeconds);
  if (after !== CLIP_AFTER_SCORE_SECONDS) return true;
  return false;
}

function pendingClipBalls(matchRow, liveInputId, limit = 4) {
  const balls = objectMap(matchRow.balls);
  return Object.values(balls)
    .filter((b) => ballNeedsClip(b, liveInputId))
    .sort((a, b) => (a.sortKey ?? 0) - (b.sortKey ?? 0))
    .slice(0, Math.max(1, limit));
}

async function fetchJSON(url) {
  const res = await fetch(url, {
    headers: { Accept: "application/json" },
    signal: AbortSignal.timeout(25000),
  });
  if (!res.ok) throw new Error(`HTTP ${res.status} ${url}`);
  return res.json();
}

async function fetchTournamentList() {
  return fetchJSON(
    `${CRICK_API}/api/tournaments/list-public?activeOnly=false&_t=${Date.now()}`
  );
}

async function fetchCompleteMatch(matchId) {
  return fetchJSON(
    `${CRICK_API}/api/matches/complete-public?matchId=${encodeURIComponent(matchId)}&_t=${Date.now()}`
  );
}

// --- Cloudflare clip + R2 ---

const { S3Client, PutObjectCommand, GetObjectCommand } = require("@aws-sdk/client-s3");
const { getSignedUrl } = require("@aws-sdk/s3-request-presigner");

function clipHost() {
  return `customer-${STREAM.subdomain}.cloudflarestream.com`;
}

async function cfJSON(path) {
  const res = await fetch(`https://api.cloudflare.com/client/v4/${path}`, {
    headers: { Authorization: `Bearer ${STREAM.apiToken}` },
  });
  const data = await res.json();
  if (!data.success) {
    throw new Error((data.errors || []).map((e) => e.message).join("; "));
  }
  return data.result;
}

async function fetchPreviewHeaders(id, previewSeconds = 30) {
  const url = `https://${clipHost()}/${id}/manifest/video.m3u8?duration=${previewSeconds}s`;
  const res = await fetch(url, {
    method: "HEAD",
    redirect: "follow",
    signal: AbortSignal.timeout(15000),
  });
  const mediaId = str(res.headers.get("stream-media-id"));
  const previewStart = parseFloat(res.headers.get("preview-start-seconds") || "");
  return {
    ok: res.ok,
    mediaId,
    previewStartSeconds: Number.isFinite(previewStart) ? previewStart : NaN,
    previewSeconds,
    durationSeconds: Number.isFinite(previewStart)
      ? previewStart + previewSeconds
      : NaN,
  };
}

function pickLiveRecording(videos) {
  if (!Array.isArray(videos) || !videos.length) return null;
  const live = videos.find((v) => {
    const state = str(v?.status?.state || v?.status).toLowerCase();
    return state.includes("live");
  });
  return live || videos[videos.length - 1];
}

async function resolveRecordingMeta(liveInputId, recordingVideoId) {
  const inputId = str(liveInputId);
  let videoId = str(recordingVideoId);
  // Live input id is not a recording UID — clipping it uses encoder-start
  // offsets while we were measuring from input-created time (wrong over).
  if (!videoId || videoId === inputId) {
    videoId = "";
    if (STREAM.accountId && STREAM.apiToken && inputId) {
      try {
        const list = await cfJSON(
          `accounts/${STREAM.accountId}/stream/live_inputs/${inputId}/videos`
        );
        const picked = pickLiveRecording(Array.isArray(list) ? list : []);
        if (picked?.uid) videoId = String(picked.uid);
      } catch {
        /* fall through to HLS headers */
      }
    }
    if (!videoId && inputId) {
      const preview = await fetchPreviewHeaders(inputId, 30);
      if (preview.mediaId && preview.mediaId !== inputId) videoId = preview.mediaId;
    }
  }
  if (!videoId) throw new Error("Recording video ID nahi mila (encoder/DVR not ready)");

  let recordingStartedAt = NaN;
  let durationSeconds = NaN;

  if (STREAM.accountId && STREAM.apiToken) {
    try {
      const detail = await cfJSON(`accounts/${STREAM.accountId}/stream/${videoId}`);
      if (detail?.created) recordingStartedAt = new Date(detail.created).getTime();
      const d = Number(detail?.duration);
      if (Number.isFinite(d) && d > 0) durationSeconds = d;
    } catch {
      /* live-inprogress videos sometimes 404 until ready */
    }
  }

  const preview = await fetchPreviewHeaders(videoId, 30);
  if (Number.isFinite(preview.durationSeconds)) {
    durationSeconds = preview.durationSeconds;
    if (Number.isNaN(recordingStartedAt)) {
      recordingStartedAt = Date.now() - preview.durationSeconds * 1000;
    }
  }

  return { videoId, recordingStartedAt, durationSeconds };
}

function ballScoredAtFromComplete(complete, ballId, ballRow) {
  const arr = complete?.ballByBall;
  if (!Array.isArray(arr)) return "";
  let hit = arr.find((b) => str(b.id) === ballId);
  if (!hit && ballRow) {
    hit = arr.find(
      (b) =>
        (b.innings ?? 1) === ballRow.innings &&
        (b.overNumber ?? b.over ?? 0) === ballRow.over &&
        (b.ballNumber ?? b.ball ?? 1) === ballRow.ball
    );
  }
  return str(hit?.createdAt) || str(hit?.updatedAt) || str(hit?.timestamp) || "";
}

function computeClipWindow({
  ballScoredAt,
  recordingStartedAt,
  streamStartedAt,
  recordingDurationSeconds = NaN,
  durationSeconds = CLIP_DURATION_SECONDS,
  endLagSeconds = CLIP_END_LAG_SECONDS,
  liveEdgeBufferSeconds = 2,
}) {
  let recStart = recordingStartedAt;
  if (!recStart || Number.isNaN(recStart)) {
    recStart = new Date(streamStartedAt).getTime();
  }
  if (Number.isNaN(recStart)) throw new Error("Invalid recording start time");

  if (!ballScoredAt) {
    throw new Error("ball createdAt missing — skip clip (no Date.now fallback)");
  }
  const endAnchorMs = new Date(ballScoredAt).getTime();
  if (Number.isNaN(endAnchorMs)) throw new Error("Invalid ballScoredAt");

  const elapsed = (endAnchorMs - recStart) / 1000;
  if (elapsed < 1) {
    throw new Error(
      `ball scored ${elapsed.toFixed(1)}s after encoder start — wait/skip`
    );
  }

  // Clip = [timestamp − 5s, timestamp + 5s]. endLag −5 → end at score + 5s.
  const end = Math.max(0, elapsed - endLagSeconds);
  const start = Math.max(0, end - durationSeconds);

  if (Number.isFinite(recordingDurationSeconds) && recordingDurationSeconds > 0) {
    const clipEnd = start + durationSeconds;
    if (clipEnd > recordingDurationSeconds - 1) {
      throw new Error(
        `need DVR past ${Math.floor(clipEnd)}s (boundary), have ${Math.floor(recordingDurationSeconds)}s — wait`
      );
    }
    const maxStart = recordingDurationSeconds - liveEdgeBufferSeconds - durationSeconds;
    if (start > recordingDurationSeconds - 3) {
      throw new Error(
        `clip time ${Math.floor(start)}s beyond recording ${Math.floor(recordingDurationSeconds)}s (live edge / DVR not ready)`
      );
    }
    if (start > maxStart && maxStart >= 0) {
      throw new Error(
        `clip time ${Math.floor(start)}s too close to live edge (${Math.floor(recordingDurationSeconds)}s recorded)`
      );
    }
  }

  return { startSeconds: start, durationSeconds, elapsedSeconds: elapsed };
}

async function downloadClip(videoId, startSeconds, durationSeconds, filename) {
  const time = Math.max(0, Math.floor(startSeconds));
  const duration = Math.min(60, Math.max(3, Math.floor(durationSeconds)));
  const url = `https://${clipHost()}/${videoId}/clip.mp4?time=${time}s&duration=${duration}s&filename=${encodeURIComponent(filename || "ball")}.mp4`;
  const res = await fetch(url, { signal: AbortSignal.timeout(120000) });
  if (!res.ok) {
    const hint = (await res.text().catch(() => "")).slice(0, 160).replace(/\s+/g, " ");
    throw new Error(
      `Clip download ${res.status} time=${time}s duration=${duration}s vid=${videoId}${hint ? ` ${hint}` : ""}`
    );
  }
  const buf = Buffer.from(await res.arrayBuffer());
  if (buf.length < 1024) throw new Error("Clip too small");
  return buf;
}

async function clipBall({
  liveInputId,
  recordingVideoId,
  streamStartedAt,
  ballScoredAt,
  objectKey,
  ballId,
}) {
  const { videoId, recordingStartedAt, durationSeconds: recordingDurationSeconds } =
    await resolveRecordingMeta(liveInputId, recordingVideoId);
  const { startSeconds, durationSeconds } = computeClipWindow({
    ballScoredAt,
    recordingStartedAt,
    streamStartedAt,
    recordingDurationSeconds,
  });
  const mp4 = await downloadClip(videoId, startSeconds, durationSeconds, ballId);
  const bytes = mp4.length;

  let videoUrl;
  let videoPath = objectKey;
  try {
    const client = new S3Client({
      region: "auto",
      endpoint: `https://${R2.accountId}.r2.cloudflarestorage.com`,
      credentials: {
        accessKeyId: R2.accessKeyId,
        secretAccessKey: R2.secretAccessKey,
      },
    });
    await client.send(
      new PutObjectCommand({
        Bucket: R2.bucket,
        Key: objectKey,
        Body: mp4,
        ContentType: "video/mp4",
      })
    );
    videoUrl = R2.publicBase
      ? `${R2.publicBase}/${objectKey}`
      : await getSignedUrl(client, new GetObjectCommand({ Bucket: R2.bucket, Key: objectKey }), {
          expiresIn: 604800,
        });
  } catch {
    const time = Math.max(0, Math.floor(startSeconds));
    const duration = Math.min(60, Math.max(3, Math.floor(durationSeconds)));
    videoUrl = `https://${clipHost()}/${videoId}/clip.mp4?time=${time}s&duration=${duration}s&filename=${ballId || "ball"}.mp4`;
    videoPath = "";
  }

  return {
    videoUrl,
    videoPath,
    recordingVideoId: videoId,
    recordingStartedAt,
    startSeconds,
    durationSeconds,
    bytes,
  };
}

function liveOttMatchIds(firebaseTournaments) {
  const out = [];
  for (const [tournamentId, t] of Object.entries(firebaseTournaments || {})) {
    if (t?.showOnOtt !== true) continue;
    for (const [matchId, m] of Object.entries(objectMap(t.matches))) {
      if (isLive(m?.status)) out.push({ tournamentId, matchId });
    }
  }
  return out;
}

async function runOttLiveSync(db) {
  const ottSnap = await db.ref("ott").once("value");
  const ott = ottSnap.val() || {};
  const firebaseTournaments = ott.tournaments || {};
  const worker = ott.worker || {};
  const liveNow = liveOttMatchIds(firebaseTournaments);

  if (liveNow.length === 0) {
    const lastDiscovery = Date.parse(str(worker.lastDiscoveryAt)) || 0;
    const idleMs = Date.now() - lastDiscovery;
    if (idleMs < 5 * 60 * 1000) {
      await db.ref("ott/worker").update({
        lastRunAt: new Date().toISOString(),
        lastSyncedMatches: 0,
        lastClippedBalls: 0,
        idle: true,
        running: true,
        lastLogs: ["idle — koi live match nahi, API skip"],
      });
      return { synced: 0, clipped: 0, logs: ["idle skip"], idle: true };
    }
  }

  const listRoot = await fetchTournamentList();
  const tournaments = listRoot.tournaments || [];
  await db.ref("ott/worker/lastDiscoveryAt").set(new Date().toISOString());

  let synced = 0;
  let clipped = 0;
  const logs = [];

  for (const td of tournaments) {
    const tournamentId = str(td.tournamentId);
    if (!tournamentId) continue;
    const fbT = firebaseTournaments[tournamentId];
    if (fbT?.showOnOtt !== true) continue;

    const liveMatches = (td.matches || []).filter((m) => isLive(m.status));
    const existingMatches = objectMap(fbT.matches);

    for (const md of liveMatches) {
      const matchId = str(md.matchId);
      if (!matchId) continue;
      const existingM = existingMatches[matchId] || {};

      const complete = await fetchCompleteMatch(matchId);
      const { matchRow } = buildFirebaseMatch(md, existingM, complete);

      await db.ref(`ott/tournaments/${tournamentId}/matches/${matchId}`).set(matchRow);

      if (complete) {
        const payload = { ...complete };
        if (Array.isArray(payload.ballByBall)) {
          payload.ballByBall = payload.ballByBall.map((ev) => {
            const bid = str(ev.id);
            const from =
              matchRow.balls[bid] ||
              Object.values(matchRow.balls).find(
                (b) =>
                  b.innings === ev.innings &&
                  b.over === (ev.overNumber ?? ev.over) &&
                  b.ball === (ev.ballNumber ?? ev.ball)
              );
            if (from?.videoUrl) return { ...ev, videoUrl: from.videoUrl };
            return ev;
          });
        }
        await db.ref(`ott/matchDetails/${matchId}`).set(payload);
      }

      synced += 1;
      logs.push(`synced ${matchId} · ${Object.keys(matchRow.balls || {}).length} balls`);

      const streamId = str(matchRow.streamLiveInputId);
      const toClip = streamId ? pendingClipBalls(matchRow, streamId, 4) : [];
      for (const ball of toClip) {
        try {
          const ballScoredAt = ballScoredAtFromComplete(complete, ball.id, ball);
          const objectKey = `ballVideos/${tournamentId}/${matchId}/${ball.id}.mp4`;
          const result = await clipBall({
            liveInputId: streamId,
            recordingVideoId: str(matchRow.streamRecordingVideoId),
            streamStartedAt: str(matchRow.streamStartedAt),
            ballScoredAt,
            objectKey,
            ballId: ball.id,
          });
          const sortKey = (ball.innings ?? 1) * 10000 + (ball.over ?? 0) * 10 + (ball.ball ?? 1);
          await db.ref(`ott/tournaments/${tournamentId}/matches/${matchId}/balls/${ball.id}`).set({
            id: ball.id,
            innings: ball.innings,
            over: ball.over,
            ball: ball.ball,
            runs: ball.runs,
            isWicket: ball.isWicket ?? false,
            note: ball.note ?? "",
            videoUrl: result.videoUrl,
            videoPath: result.videoPath,
            clipStartSeconds: Math.floor(result.startSeconds),
            clipDurationSeconds: Math.floor(result.durationSeconds),
            clipAfterScoreSeconds: CLIP_AFTER_SCORE_SECONDS,
            clipBytes: result.bytes || 0,
            clipAt: new Date().toISOString(),
            sortKey,
          });
          if (result.recordingVideoId && result.recordingVideoId !== streamId) {
            matchRow.streamRecordingVideoId = result.recordingVideoId;
            await db
              .ref(`ott/tournaments/${tournamentId}/matches/${matchId}/streamRecordingVideoId`)
              .set(result.recordingVideoId);
          }
          if (result.recordingStartedAt && !Number.isNaN(result.recordingStartedAt)) {
            await db
              .ref(`ott/tournaments/${tournamentId}/matches/${matchId}/streamRecordingStartedAt`)
              .set(new Date(result.recordingStartedAt).toISOString());
          }
          clipped += 1;
          logs.push(
            `clip ${ball.id} OK t=${Math.floor(result.startSeconds)}s d=${Math.floor(result.durationSeconds)}s vid=${result.recordingVideoId}`
          );
        } catch (err) {
          logs.push(`clip ${ball.id} FAIL: ${err.message}`);
          break;
        }
      }
    }
  }

  if (synced > 0) {
    await db.ref("ott/meta").update({
      source: "Firebase-Cloud-Function",
      updatedAt: new Date().toISOString(),
      note: `Auto sync · ${synced} match(es) · ${clipped} clip(s)`,
    });
  }

  await db.ref("ott/worker").update({
    lastRunAt: new Date().toISOString(),
    lastSyncedMatches: synced,
    lastClippedBalls: clipped,
    lastLogs: logs.slice(-20),
    running: true,
    idle: synced === 0,
  });

  return { synced, clipped, logs };
}

module.exports = {
  runOttLiveSync,
  CRICK_API,
};
