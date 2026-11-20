// Neon Arena leaderboard API — Cloudflare Worker + D1.
//
// POST /api/run/start   {player_id, secret, name}                -> {token, season}
// POST /api/run/submit  {player_id, secret, token, platform, mode, score, wave, kills,
//                        duration, weapon, version}                -> {ok, flagged, ranks}
// GET  /api/board?platform=&mode=&period=all|week|day&limit=&player_id=
//                                                                   -> {entries, me, total}
// GET  /api/boards                                                  -> {boards: [{platform, mode, players}]}
// POST /api/name        {player_id, secret, name}                  -> {ok, name}
//
// Online co-op (relay through a Durable Object per room, see room.js):
// POST /api/room                                                    -> {code}
// GET  /api/room/<CODE>/ws   (WebSocket upgrade)                    -> relay socket
//
// A browser game can't keep secrets, so this only stops casual tampering: every run needs a
// server-issued token, the claimed run length is checked against the server clock, and scores
// that don't fit the wave / kill / time numbers are stored as flagged and never ranked.

const PLATFORMS = ["pc", "phone", "tablet"];
const MODES = ["kbm", "twin", "hybrid", "auto"];
const WEAPONS = ["pulse", "scatter", "laser"];
const PERIODS = ["all", "week", "day"];
const NAME_MAX = 12;
const TOKEN_TTL_MS = 6 * 3600 * 1000;
const STARTS_PER_HOUR_PLAYER = 40;
const STARTS_PER_HOUR_IP = 200;
const TZ_OFFSET_MS = 8 * 3600 * 1000; // "today" and "this week" follow UTC+8

export { Room } from "./room.js";
import { ROOM_ALPHABET, ROOM_CODE_LEN } from "./room.js";

export default {
  async fetch(request, env) {
    const cors = corsHeaders(request, env);
    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: cors });
    }
    try {
      const url = new URL(request.url);
      const ws = url.pathname.match(/^\/api\/room\/([A-Z0-9]{4,8})\/ws$/);
      if (ws && request.method === "GET") {
        if (request.headers.get("Upgrade") !== "websocket") throw new HttpError(426, "upgrade_required");
        if (!originAllowed(request, env)) throw new HttpError(403, "origin");
        const stub = env.ROOMS.get(env.ROOMS.idFromName(ws[1]));
        return stub.fetch(new Request("https://room/join", request));
      }
      const route = `${request.method} ${url.pathname}`;
      let out;
      switch (route) {
        case "POST /api/run/start":
          out = await startRun(request, env);
          break;
        case "POST /api/run/submit":
          out = await submitRun(request, env);
          break;
        case "GET /api/board":
          out = await getBoard(url, env);
          break;
        case "GET /api/boards":
          out = await listBoards(env);
          break;
        case "POST /api/name":
          out = await rename(request, env);
          break;
        case "POST /api/room":
          out = await createRoom(request, env);
          break;
        case "GET /":
        case "GET /api":
          out = { ok: true, service: "neon-arena-leaderboard", season: season(env) };
          break;
        default:
          throw new HttpError(404, "not_found");
      }
      return json(out, 200, cors);
    } catch (e) {
      if (e instanceof HttpError) return json({ error: e.code }, e.status, cors);
      console.error(e);
      return json({ error: "server_error" }, 500, cors);
    }
  },
};

class HttpError extends Error {
  constructor(status, code) {
    super(code);
    this.status = status;
    this.code = code;
  }
}

// ---------------------------------------------------------------- routes

const ROOMS_PER_HOUR_IP = 30;

async function createRoom(request, env) {
  if (!originAllowed(request, env)) throw new HttpError(403, "origin");
  const ip = request.headers.get("CF-Connecting-IP") || "local";
  // Light flood guard, reusing the run-start rate table.
  const since = Date.now() - 3600 * 1000;
  const n = await env.DB.prepare("SELECT COUNT(*) AS n FROM room_creates WHERE ip = ? AND created_at > ?")
    .bind(ip, since).first("n").catch(() => 0);
  if (n >= ROOMS_PER_HOUR_IP) throw new HttpError(429, "rate_limited");
  await env.DB.prepare("INSERT INTO room_creates (ip, created_at) VALUES (?, ?)").bind(ip, Date.now()).run().catch(() => {});
  for (let tries = 0; tries < 6; tries++) {
    let code = "";
    const bytes = crypto.getRandomValues(new Uint8Array(ROOM_CODE_LEN));
    for (const b of bytes) code += ROOM_ALPHABET[b % ROOM_ALPHABET.length];
    const stub = env.ROOMS.get(env.ROOMS.idFromName(code));
    const r = await stub.fetch("https://room/create", { method: "POST" });
    if (r.ok) return { code };
  }
  throw new HttpError(503, "no_room");
}

async function startRun(request, env) {
  const body = await readJson(request);
  const player = await authPlayer(env, body, true);
  const now = Date.now();
  const ipHash = await sha256(request.headers.get("CF-Connecting-IP") || "local");
  const hourAgo = now - 3600 * 1000;
  const counts = await env.DB.prepare(
    `SELECT
       (SELECT COUNT(*) FROM run_tokens WHERE player_id = ?1 AND started_at > ?3) AS by_player,
       (SELECT COUNT(*) FROM run_tokens WHERE ip_hash = ?2 AND started_at > ?3) AS by_ip`
  ).bind(player.id, ipHash, hourAgo).first();
  if (counts.by_player >= STARTS_PER_HOUR_PLAYER || counts.by_ip >= STARTS_PER_HOUR_IP) {
    throw new HttpError(429, "rate_limited");
  }
  const token = randomId(24);
  await env.DB.batch([
    env.DB.prepare("INSERT INTO run_tokens (token, player_id, ip_hash, started_at) VALUES (?1, ?2, ?3, ?4)")
      .bind(token, player.id, ipHash, now),
    // Housekeeping: drop tokens older than a day.
    env.DB.prepare("DELETE FROM run_tokens WHERE started_at < ?1").bind(now - 24 * 3600 * 1000),
  ]);
  return { token, season: season(env), name: player.name };
}

async function submitRun(request, env) {
  const body = await readJson(request);
  const player = await authPlayer(env, body, false);
  const tok = await env.DB.prepare("SELECT * FROM run_tokens WHERE token = ?1")
    .bind(str(body.token, 64)).first();
  if (!tok || tok.player_id !== player.id) throw new HttpError(403, "bad_token");
  if (tok.used) throw new HttpError(409, "token_used");
  const now = Date.now();
  if (now - tok.started_at > TOKEN_TTL_MS) throw new HttpError(410, "token_expired");

  const run = {
    platform: oneOf(body.platform, PLATFORMS),
    mode: oneOf(body.mode, MODES),
    weapon: oneOf(body.weapon, WEAPONS),
    score: int(body.score, 0, 1e9),
    wave: int(body.wave, 1, 9999),
    kills: int(body.kills, 0, 1e6),
    duration: int(body.duration, 0, 24 * 3600),
    version: str(body.version, 16) || "?",
  };
  const elapsed = (now - tok.started_at) / 1000;
  const flagged = implausible(run, elapsed) ? 1 : 0;
  const { day, week } = periodKeys(now);
  const s = season(env);

  const stmts = [
    env.DB.prepare("UPDATE run_tokens SET used = 1 WHERE token = ?1").bind(tok.token),
    env.DB.prepare(
      `INSERT INTO runs (season, player_id, platform, mode, score, wave, kills, duration, weapon,
                         version, day, week, created_at, flagged)
       VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14)`
    ).bind(s, player.id, run.platform, run.mode, run.score, run.wave, run.kills, run.duration,
      run.weapon, run.version, day, week, now, flagged),
  ];
  if (!flagged) {
    for (const [period, key] of [["all", "all"], ["week", week], ["day", day]]) {
      stmts.push(env.DB.prepare(
        `INSERT INTO bests (season, platform, mode, period, period_key, player_id, score, wave, weapon, duration, created_at)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11)
         ON CONFLICT (season, platform, mode, period, period_key, player_id) DO UPDATE SET
           score = excluded.score, wave = excluded.wave, weapon = excluded.weapon,
           duration = excluded.duration, created_at = excluded.created_at
         WHERE excluded.score > bests.score`
      ).bind(s, run.platform, run.mode, period, key, player.id, run.score, run.wave, run.weapon, run.duration, now));
    }
  }
  await env.DB.batch(stmts);

  const ranks = {};
  if (!flagged) {
    for (const period of PERIODS) {
      ranks[period] = await rankOf(env, s, run.platform, run.mode, period, player.id, now);
    }
  }
  return { ok: true, flagged: !!flagged, ranks };
}

async function getBoard(url, env) {
  const q = url.searchParams;
  const platform = oneOf(q.get("platform"), PLATFORMS);
  const mode = oneOf(q.get("mode"), MODES);
  const period = oneOf(q.get("period") || "all", PERIODS);
  const limit = int(q.get("limit") || 20, 1, 100);
  const playerId = q.get("player_id") || "";
  const s = season(env);
  const now = Date.now();
  const key = boardKey(period, now);
  const rows = await env.DB.prepare(
    `SELECT b.score, b.wave, b.weapon, b.duration, b.player_id, p.name FROM bests b
       JOIN players p ON p.id = b.player_id
      WHERE b.season = ?1 AND b.platform = ?2 AND b.mode = ?3 AND b.period = ?4 AND b.period_key = ?5
      ORDER BY b.score DESC, b.created_at ASC LIMIT ?6`
  ).bind(s, platform, mode, period, key, limit).all();
  // Standard competition ranking: ties share a rank.
  const entries = [];
  rows.results.forEach((e, i) => {
    const prev = entries[i - 1];
    const rank = prev && prev.score === e.score ? prev.rank : i + 1;
    entries.push({ rank, name: e.name, score: e.score, wave: e.wave, weapon: e.weapon,
      duration: e.duration, me: e.player_id === playerId });
  });
  const total = (await env.DB.prepare(
    `SELECT COUNT(*) AS n FROM bests WHERE season = ?1 AND platform = ?2 AND mode = ?3 AND period = ?4 AND period_key = ?5`
  ).bind(s, platform, mode, period, key).first()).n;
  const me = playerId ? await rankOf(env, s, platform, mode, period, playerId, now) : null;
  return { season: s, platform, mode, period, total, entries, me };
}

async function listBoards(env) {
  const rows = await env.DB.prepare(
    `SELECT platform, mode, COUNT(*) AS players FROM bests
      WHERE season = ?1 AND period = 'all' GROUP BY platform, mode`
  ).bind(season(env)).all();
  return { season: season(env), boards: rows.results };
}

async function rename(request, env) {
  const body = await readJson(request);
  const player = await authPlayer(env, body, false);
  const name = cleanName(body.name);
  if (!name) throw new HttpError(400, "bad_name");
  await env.DB.prepare("UPDATE players SET name = ?1 WHERE id = ?2").bind(name, player.id).run();
  return { ok: true, name };
}

// ---------------------------------------------------------------- ranking

function boardKey(period, now) {
  if (period === "all") return "all";
  const { day, week } = periodKeys(now);
  return period === "week" ? week : day;
}

// {rank, score, total, gap}: gap is how many points the next player up is ahead.
// Reads only the rows above the player plus the board count.
async function rankOf(env, s, platform, mode, period, playerId, now) {
  const key = boardKey(period, now);
  const where = "season = ?1 AND platform = ?2 AND mode = ?3 AND period = ?4 AND period_key = ?5";
  const mine = await env.DB.prepare(`SELECT score FROM bests WHERE ${where} AND player_id = ?6`)
    .bind(s, platform, mode, period, key, playerId).first();
  if (!mine) return null;
  const row = await env.DB.prepare(
    `SELECT (SELECT COUNT(*) FROM bests WHERE ${where} AND score > ?6) AS above_n,
            (SELECT MIN(score) FROM bests WHERE ${where} AND score > ?6) AS above,
            (SELECT COUNT(*) FROM bests WHERE ${where}) AS total`
  ).bind(s, platform, mode, period, key, mine.score).first();
  return { rank: row.above_n + 1, score: mine.score, total: row.total,
    gap: row.above === null ? 0 : row.above - mine.score };
}

// ---------------------------------------------------------------- checks

// Generous upper bounds from the game's scoring rules (see the design doc, section 9):
// kills are worth at most 3000 (snake 500 × elite 2 × combo 3), plus wave-clear bonuses,
// jackpot cards and bosses (4000 × combo 3).
function implausible(r, elapsedSec) {
  const w = r.wave;
  const maxScore = r.kills * 3000 + 50 * w * (w + 1) + 500 * w * Math.floor(w / 3) + 12000 * Math.floor(w / 5);
  if (r.score > maxScore) return true;
  if (r.duration < (w - 1) * 4) return true;          // waves can't be cleared faster than this
  if (r.kills > r.duration * 15 + 20) return true;
  if (r.duration > elapsedSec + 15) return true;      // claims a longer run than the server saw
  return false;
}

async function authPlayer(env, body, create) {
  const id = str(body.player_id, 64);
  const secret = str(body.secret, 128);
  if (!/^[A-Za-z0-9_-]{16,64}$/.test(id) || secret.length < 16) throw new HttpError(400, "bad_player");
  const hash = await sha256(secret);
  const row = await env.DB.prepare("SELECT * FROM players WHERE id = ?1").bind(id).first();
  if (row) {
    if (row.secret_hash !== hash) throw new HttpError(403, "bad_secret");
    return row;
  }
  if (!create) throw new HttpError(403, "unknown_player");
  const name = cleanName(body.name) || `Pilot-${id.slice(0, 4)}`;
  await env.DB.prepare("INSERT INTO players (id, secret_hash, name, created_at) VALUES (?1, ?2, ?3, ?4)")
    .bind(id, hash, name, Date.now()).run();
  return { id, name };
}

// ---------------------------------------------------------------- helpers

function season(env) {
  return parseInt(env.SEASON || "1", 10);
}

function periodKeys(ms) {
  const local = new Date(ms + TZ_OFFSET_MS);
  const day = local.toISOString().slice(0, 10);
  const dow = (local.getUTCDay() + 6) % 7; // Monday = 0
  const monday = new Date(local.getTime() - dow * 86400000).toISOString().slice(0, 10);
  return { day, week: monday };
}

function cleanName(v) {
  // No word filter (by design); just strip control characters and cap the length.
  const s = String(v ?? "").replace(/[\u0000-\u001f\u007f]/g, "").trim();
  return Array.from(s).slice(0, NAME_MAX).join("");
}

function originAllowed(request, env) {
  const origin = request.headers.get("Origin") || "";
  if (!origin) return true; // non-browser clients (tests); browsers always send Origin
  if (/^http:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/.test(origin)) return true;
  return (env.ALLOWED_ORIGINS || "").split(",").map((s) => s.trim()).includes(origin);
}

function corsHeaders(request, env) {
  const origin = request.headers.get("Origin") || "";
  const allowed = (env.ALLOWED_ORIGINS || "").split(",").map((s) => s.trim()).filter(Boolean);
  const local = /^http:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/.test(origin);
  const h = {
    "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type",
    "Access-Control-Max-Age": "86400",
    Vary: "Origin",
  };
  if (origin && (local || allowed.includes(origin))) h["Access-Control-Allow-Origin"] = origin;
  return h;
}

function json(obj, status, headers) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { ...headers, "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store" },
  });
}

async function readJson(request) {
  try {
    return await request.json();
  } catch {
    throw new HttpError(400, "bad_json");
  }
}

function str(v, max) {
  return typeof v === "string" ? v.slice(0, max) : "";
}

function int(v, min, max) {
  const n = Number(v);
  if (!Number.isFinite(n) || n < min || n > max) throw new HttpError(400, "bad_number");
  return Math.floor(n);
}

function oneOf(v, list) {
  if (!list.includes(v)) throw new HttpError(400, "bad_value");
  return v;
}

function randomId(bytes) {
  const a = new Uint8Array(bytes);
  crypto.getRandomValues(a);
  return Array.from(a, (b) => b.toString(16).padStart(2, "0")).join("");
}

async function sha256(text) {
  const d = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return Array.from(new Uint8Array(d), (b) => b.toString(16).padStart(2, "0")).join("");
}
