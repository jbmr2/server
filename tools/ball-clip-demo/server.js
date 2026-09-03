#!/usr/bin/env node
/**
 * JBMR Sports — Live Auto Ball Clipping DEMO
 * Polls CrickDB → sync engine → Firebase videoUrl (demo clips)
 */
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

const CRICKDB = 'https://crickdbmodule-api-144271912366.asia-south1.run.app';
const FIREBASE = 'https://ncrplt20-1c022-default-rtdb.asia-southeast1.firebasedatabase.app';
const MATCH_ID = process.env.DEMO_MATCH_ID || 'b3692be0-3d33-46b9-92a2-42f67689d663';
const POLL_MS = Number(process.env.POLL_MS || 5000);
const PRE_ROLL = 8;
const POST_ROLL = 12;
const SEARCH_WINDOW = 10;
const PORT = Number(process.env.PORT || 8790);

// Demo playback until Cloudflare Stream UID is configured
const DEMO_MP4 = 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerBlazes.mp4';
const DEMO_STREAM_UID = process.env.STREAM_VIDEO_UID || 'DEMO_VIDEO_UID';

const state = {
  match: null,
  processedBallIds: new Set(),
  balls: [],
  offsetSeconds: 0,
  lastPollAt: null,
  pollCount: 0,
  errors: [],
  firebaseWrites: 0,
  tournamentId: null,
};

const sseClients = new Set();

function broadcast(event, data) {
  const msg = `event: ${event}\ndata: ${JSON.stringify(data)}\n\n`;
  for (const res of sseClients) res.write(msg);
}

async function fetchJson(url) {
  const res = await fetch(url, { signal: AbortSignal.timeout(20000) });
  if (!res.ok) throw new Error(`HTTP ${res.status} ${url}`);
  return res.json();
}

async function firebasePut(path, value) {
  const url = `${FIREBASE}/${path}.json`;
  const res = await fetch(url, {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(value),
  });
  if (!res.ok) throw new Error(`Firebase PUT ${path} → ${res.status}`);
  state.firebaseWrites++;
}

function ballLabel(b) {
  return `${b.innings}.${b.overNumber}.${b.ballNumber}`;
}

function resultLabel(b) {
  if (b.wicket) return 'WICKET';
  const runs = (b.batRuns || 0) + (b.extraRuns || 0);
  if (runs === 4) return 'FOUR';
  if (runs === 6) return 'SIX';
  if (b.extraType) return `${b.extraType.toUpperCase()} +${runs}`;
  return runs === 0 ? 'DOT' : `${runs} run${runs > 1 ? 's' : ''}`;
}

function parseUtc(iso) {
  return new Date(iso).getTime();
}

function estimateStreamSeconds(ball, matchStartedAt, prevBall) {
  const eventMs = parseUtc(ball.createdAt);
  const startMs = parseUtc(matchStartedAt);
  let base = (eventMs - startMs) / 1000 + state.offsetSeconds;

  if (prevBall?.createdAt) {
    const gapScoring = (eventMs - parseUtc(prevBall.createdAt)) / 1000;
    // Late batch entry: scorer entered multiple balls quickly
    if (gapScoring < 8 && prevBall._clipStartSeconds != null) {
      base = prevBall._clipStartSeconds + 35;
    }
  }

  return Math.max(0, base);
}

function buildClipUrl(startSeconds, durationSeconds) {
  if (DEMO_STREAM_UID !== 'DEMO_VIDEO_UID') {
    const t = Math.floor(startSeconds);
    const d = Math.floor(durationSeconds);
    return `https://customer-XXXX.cloudflarestream.com/${DEMO_STREAM_UID}/manifest/clip.m3u8?time=${t}s&duration=${d}s`;
  }
  return `${DEMO_MP4}#t=${Math.floor(startSeconds)},${Math.floor(startSeconds + durationSeconds)}`;
}

async function ensureMatchOnFirebase(complete) {
  const mi = complete.matchInfo;
  const tid = mi.tournament?.id || 'demo-tournament';
  state.tournamentId = tid;

  const matchBase = `ott/tournaments/${tid}/matches/${mi.id}`;
  const existing = await fetchJson(`${FIREBASE}/${matchBase}.json`).catch(() => null);

  const matchRow = {
    matchId: mi.id,
    matchSeq: mi.matchSeq ?? 1,
    stage: 'League',
    venue: mi.venue || '',
    scheduledAt: mi.scheduledAt,
    status: mi.status || 'live',
    title: `${mi.team1?.shortName || 'T1'} vs ${mi.team2?.shortName || 'T2'}`,
    liveUrl: existing?.liveUrl || '',
    highlightUrl: existing?.highlightUrl || '',
    showOnOtt: true,
    clipDemo: true,
    streamVideoUid: DEMO_STREAM_UID,
    team1: {
      name: mi.team1?.name,
      shortName: mi.team1?.shortName,
      logoUrl: mi.team1?.logoUrl,
      themeColor: mi.team1?.themeColor,
    },
    team2: {
      name: mi.team2?.name,
      shortName: mi.team2?.shortName,
      logoUrl: mi.team2?.logoUrl,
      themeColor: mi.team2?.themeColor,
    },
    innings: (complete.innings || []).map((inn) => ({
      inningsNumber: inn.number,
      teamName: inn.battingTeamName,
      teamShortName: inn.battingTeamShortName,
      runs: inn.runs,
      wickets: inn.wickets,
      overs: inn.overs,
    })),
  };

  await firebasePut(`ott/tournaments/${tid}/showOnOtt`, true);
  await firebasePut(`ott/tournaments/${tid}/name`, mi.tournament?.name || 'Demo Tournament');
  await firebasePut(`ott/tournaments/${tid}/tournamentId`, tid);
  await firebasePut(matchBase, matchRow);
  await firebasePut('ott/meta', {
    source: 'ball-clip-demo',
    updatedAt: new Date().toISOString(),
    note: 'Auto clipping live demo',
  });

  return { tid, matchBase };
}

async function processBall(ball, matchStartedAt, prevBall, matchBase) {
  const deliverySec = estimateStreamSeconds(ball, matchStartedAt, prevBall);
  const clipStart = Math.max(0, deliverySec - PRE_ROLL);
  const clipDuration = PRE_ROLL + POST_ROLL;
  const videoUrl = buildClipUrl(clipStart, clipDuration);

  const ballKey = ball.id || `i${ball.innings}-o${ball.overNumber}-b${ball.ballNumber}`;
  const runs = (ball.batRuns || 0) + (ball.extraRuns || 0);
  const sortKey = (ball.innings || 1) * 10000 + (ball.overNumber || 0) * 10 + (ball.ballNumber || 0);

  const row = {
    id: ballKey,
    innings: ball.innings,
    over: ball.overNumber,
    ball: ball.ballNumber,
    runs,
    isWicket: !!ball.wicket,
    note: resultLabel(ball),
    videoUrl,
    clipStatus: 'ready',
    clipStartSeconds: Math.round(clipStart),
    clipDurationSeconds: clipDuration,
    clipSource: 'auto-demo',
    scoringEventAt: ball.createdAt,
    searchWindowSeconds: SEARCH_WINDOW,
    sortKey,
  };

  await firebasePut(`${matchBase}/balls/${ballKey}`, row);

  const entry = {
    ...row,
    ballLabel: ballLabel(ball),
    result: resultLabel(ball),
    striker: ball.striker?.name,
    bowler: ball.bowler?.name,
    _clipStartSeconds: clipStart,
    processedAt: new Date().toISOString(),
  };

  state.balls.push(entry);
  state.processedBallIds.add(ball.id);
  broadcast('ball', entry);
  return entry;
}

async function poll() {
  state.pollCount++;
  state.lastPollAt = new Date().toISOString();

  try {
    const complete = await fetchJson(
      `${CRICKDB}/api/matches/complete-public?matchId=${MATCH_ID}`
    );
    const mi = complete.matchInfo;
    state.match = {
      id: mi.id,
      title: `${mi.team1?.shortName} vs ${mi.team2?.shortName}`,
      status: mi.status,
      startedAt: mi.startedAt,
      tournament: mi.tournament?.name,
    };

    const { matchBase } = await ensureMatchOnFirebase(complete);
    const bbb = complete.ballByBall || [];

    let prev = state.balls.length ? state.balls[state.balls.length - 1] : null;
    const newBalls = [];

    for (const ball of bbb) {
      if (state.processedBallIds.has(ball.id)) continue;
      const prevApi = bbb.find(
        (b) =>
          b.id !== ball.id &&
          state.processedBallIds.has(b.id) &&
          (parseUtc(b.createdAt) < parseUtc(ball.createdAt))
      );
      const entry = await processBall(ball, mi.startedAt, prevApi || prev, matchBase);
      newBalls.push(entry);
      prev = entry;
    }

    broadcast('poll', {
      at: state.lastPollAt,
      totalBalls: bbb.length,
      newBalls: newBalls.length,
      match: state.match,
      offsetSeconds: state.offsetSeconds,
    });
  } catch (err) {
    const msg = err?.message || String(err);
    state.errors.unshift({ at: new Date().toISOString(), msg });
    state.errors = state.errors.slice(0, 20);
    broadcast('error', { msg });
  }
}

const server = http.createServer((req, res) => {
  const url = new URL(req.url, `http://localhost:${PORT}`);

  if (url.pathname === '/events') {
    res.writeHead(200, {
      'Content-Type': 'text/event-stream',
      'Cache-Control': 'no-cache',
      Connection: 'keep-alive',
    });
    res.write(`event: hello\ndata: ${JSON.stringify({ matchId: MATCH_ID })}\n\n`);
    sseClients.add(res);
    req.on('close', () => sseClients.delete(res));
    return;
  }

  if (url.pathname === '/api/state') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({
      ...state,
      processedBallIds: [...state.processedBallIds],
    }));
    return;
  }

  if (url.pathname === '/api/offset' && req.method === 'POST') {
    let body = '';
    req.on('data', (c) => (body += c));
    req.on('end', () => {
      try {
        const { offset } = JSON.parse(body);
        state.offsetSeconds = Number(offset) || 0;
        broadcast('offset', { offsetSeconds: state.offsetSeconds });
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ ok: true, offsetSeconds: state.offsetSeconds }));
      } catch {
        res.writeHead(400).end('bad json');
      }
    });
    return;
  }

  let file = url.pathname === '/' ? '/index.html' : url.pathname;
  const fp = path.join(__dirname, 'public', file);
  if (!fp.startsWith(path.join(__dirname, 'public'))) {
    res.writeHead(403).end();
    return;
  }
  if (!fs.existsSync(fp)) {
    res.writeHead(404).end('not found');
    return;
  }
  const ext = path.extname(fp);
  const types = { '.html': 'text/html', '.css': 'text/css', '.js': 'text/javascript' };
  res.writeHead(200, { 'Content-Type': types[ext] || 'application/octet-stream' });
  fs.createReadStream(fp).pipe(res);
});

server.listen(PORT, async () => {
  console.log(`\n🏏 JBMR Auto Ball Clip DEMO`);
  console.log(`   Dashboard: http://localhost:${PORT}`);
  console.log(`   Match:     ${MATCH_ID}`);
  console.log(`   Poll:      every ${POLL_MS / 1000}s\n`);

  await poll();
  setInterval(poll, POLL_MS);
});
