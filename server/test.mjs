// Scripted checks against a running server: `npm run dev` in one shell, then `npm test`.
const BASE = process.env.BASE || "http://127.0.0.1:8787";
let fails = 0;
const ok = (c, m) => { console.log((c ? "PASS  " : "FAIL  ") + m); if (!c) fails++; };
const rid = (n = 20) => Array.from(crypto.getRandomValues(new Uint8Array(n)), (b) => (b % 36).toString(36)).join("");

async function call(method, path, body, origin = "http://127.0.0.1:5000") {
  const r = await fetch(BASE + path, {
    method,
    headers: { "Content-Type": "application/json", Origin: origin },
    body: body ? JSON.stringify(body) : undefined,
  });
  return { status: r.status, cors: r.headers.get("access-control-allow-origin"), data: await r.json().catch(() => null) };
}

function player(name) {
  return { player_id: rid(24), secret: rid(32), name };
}

async function play(p, run, opts = {}) {
  const s = await call("POST", "/api/run/start", p);
  if (s.status !== 200) return s;
  if (opts.wait) await new Promise((r) => setTimeout(r, opts.wait));
  return call("POST", "/api/run/submit", { ...p, token: s.data.token, version: "2.2", ...run });
}

const tag = rid(6); // keeps repeated runs on separate data
const A = player("Alice" + tag.slice(0, 2)), B = player("Bob"), C = player("小明");
const run = (score, extra = {}) => ({ platform: "pc", mode: "kbm", weapon: "pulse", score, wave: 3, kills: 20, duration: 12, ...extra });

let r = await call("GET", "/api");
ok(r.status === 200 && r.data.ok, "service up");
ok(r.cors === "http://127.0.0.1:5000", "local origin allowed by CORS");
r = await call("GET", "/api", null, "https://evil.example");
ok(r.cors === null, "unknown origin gets no CORS header");
r = await call("GET", "/api", null, "https://mmmax21.github.io");
ok(r.cors === "https://mmmax21.github.io", "game origin allowed");

// Basic flow and ranking
r = await play(A, run(9000), { wait: 0 });
ok(r.status === 200 && !r.data.flagged, "A submits: " + JSON.stringify(r.data));
const aRank = r.data.ranks?.all?.rank;
r = await play(B, run(12000, { kills: 30 }));
ok(r.status === 200 && r.data.ranks.all.rank === aRank, "B outranks A (takes A's old rank)");
r = await play(A, run(5000));
ok(r.data.ranks.all.score === 9000, "a lower run keeps the player's best (9000)");
ok(r.data.ranks.all.gap === 3000, "gap to the player above = 3000: " + JSON.stringify(r.data.ranks.all));

// Board query
r = await call("GET", `/api/board?platform=pc&mode=kbm&period=all&limit=100&player_id=${A.player_id}`);
const names = r.data.entries.map((e) => e.name);
ok(names.includes(A.name) && names.includes("Bob"), "board lists both players");
ok(r.data.entries.filter((e) => e.name === A.name).length === 1, "one row per player (best only)");
ok(r.data.entries.find((e) => e.me)?.name === A.name, "board marks my row");
ok(r.data.me?.score === 9000, "board returns my rank");
ok(!JSON.stringify(r.data).includes(A.player_id), "player ids are not exposed");
r = await call("GET", "/api/board?platform=pc&mode=kbm&period=week");
ok(r.status === 200 && r.data.entries.length > 0, "weekly board");
r = await call("GET", "/api/board?platform=pc&mode=kbm&period=day");
ok(r.status === 200 && r.data.entries.length > 0, "daily board");

// Platforms / modes are separate boards
r = await play(C, run(50000, { platform: "phone", mode: "hybrid", kills: 40 }));
ok(r.status === 200 && !r.data.flagged, "phone hybrid run accepted");
r = await call("GET", "/api/board?platform=pc&mode=kbm");
ok(!r.data.entries.some((e) => e.name === "小明"), "phone run not on PC board");
r = await call("GET", "/api/board?platform=phone&mode=hybrid");
ok(r.data.entries.some((e) => e.name === "小明"), "phone run on phone/hybrid board (Chinese name ok)");
r = await call("GET", "/api/boards");
ok(r.data.boards.some((b) => b.platform === "phone" && b.mode === "hybrid"), "boards list includes phone/hybrid");

// Anti-cheat
let s = await call("POST", "/api/run/start", A);
r = await call("POST", "/api/run/submit", { ...A, token: s.data.token, ...run(100) });
r = await call("POST", "/api/run/submit", { ...A, token: s.data.token, ...run(100) });
ok(r.status === 409, "token can't be reused");
s = await call("POST", "/api/run/start", A);
r = await call("POST", "/api/run/submit", { ...B, token: s.data.token, ...run(100) });
ok(r.status === 403, "someone else's token rejected");
r = await call("POST", "/api/run/submit", { ...A, secret: "x".repeat(32), token: s.data.token, ...run(100) });
ok(r.status === 403, "wrong secret rejected");
r = await play(player("Cheat1"), run(99999999, { kills: 10 }));
ok(r.status === 200 && r.data.flagged, "impossible score is flagged");
r = await play(player("Cheat2"), run(1000, { wave: 30, duration: 20 }));
ok(r.data.flagged, "too many waves for the time is flagged");
r = await play(player("Cheat3"), run(1000, { duration: 600 }));
ok(r.data.flagged, "claims 600 s but the server saw ~0 s: flagged");
r = await call("GET", "/api/board?platform=pc&mode=kbm&limit=100");
ok(!r.data.entries.some((e) => e.name.startsWith("Cheat")), "flagged runs never appear");
r = await play(player("Bad"), run(100, { platform: "console" }));
ok(r.status === 400, "unknown platform rejected");

// Rename
r = await call("POST", "/api/name", { ...A, name: "  New名字123456789  " });
ok(r.status === 200 && r.data.name === "New名字12345678".slice(0, 12), "rename trims and caps at 12: " + r.data.name);
r = await call("GET", `/api/board?platform=pc&mode=kbm&player_id=${A.player_id}&limit=100`);
ok(r.data.entries.find((e) => e.me)?.name === r.data.entries.find((e) => e.me)?.name && r.data.entries.some((e) => e.name.startsWith("New名字")), "new name shows on board");

// Rate limit
const D = player("Spam");
let limited = false;
for (let i = 0; i < 45; i++) {
  const x = await call("POST", "/api/run/start", D);
  if (x.status === 429) { limited = true; break; }
}
ok(limited, "too many starts per hour are rate limited");

// Co-op rooms
function sock(code) {
  const ws = new WebSocket(BASE.replace("http", "ws") + `/api/room/${code}/ws`);
  ws.inbox = [];
  ws.onmessage = (ev) => ws.inbox.push(String(ev.data));
  ws.ready = new Promise((res, rej) => { ws.onopen = res; ws.onerror = rej; });
  return ws;
}
async function waitFor(ws, pred, ms = 3000) {
  const t0 = Date.now();
  while (Date.now() - t0 < ms) {
    const m = ws.inbox.find(pred);
    if (m !== undefined) { ws.inbox.splice(ws.inbox.indexOf(m), 1); return m; }
    await new Promise((r) => setTimeout(r, 20));
  }
  return null;
}
r = await call("POST", "/api/room", {});
ok(r.status === 200 && /^[A-Z0-9]{4}$/.test(r.data.code), "room created: " + r.data?.code);
const code = r.data.code;
const host = sock(code); await host.ready;
ok(await waitFor(host, (m) => m === "#hello 0"), "first socket is host (slot 0)");
const guest = sock(code); await guest.ready;
ok(await waitFor(guest, (m) => m === "#hello 1"), "second socket is guest (slot 1)");
ok(await waitFor(host, (m) => m === "#join 1"), "host told guest joined");
guest.send('{"t":"in","mv":[1,0]}');
ok(await waitFor(host, (m) => m === '1|{"t":"in","mv":[1,0]}'), "guest frame relayed to host with slot");
host.send('{"t":"snap"}');
ok(await waitFor(guest, (m) => m === '{"t":"snap"}'), "host frame broadcast to guest");
host.send('@1|{"t":"offer"}');
ok(await waitFor(guest, (m) => m === '{"t":"offer"}'), "host frame addressed to slot 1");
const third = sock(code); await third.ready;
ok(await waitFor(third, (m) => m === "#full"), "third player refused (2-player rooms)");
const bogus = sock("ZZZZ"); await bogus.ready;
ok(await waitFor(bogus, (m) => m === "#gone"), "unknown room refused");
guest.close();
ok(await waitFor(host, (m) => m === "#leave 1"), "host told guest left");
const guest2 = sock(code); await guest2.ready;
ok(await waitFor(guest2, (m) => m === "#hello 1"), "guest can rejoin the free slot");
host.close();
ok(await waitFor(guest2, (m) => m === "#host_left"), "guest told host left");
const late = sock(code); await late.ready;
ok(await waitFor(late, (m) => m === "#full"), "room closed after host left");
{
  const http = await import("node:http");
  const status = await new Promise((res) => {
    const req = http.request(BASE + `/api/room/${code}/ws`, { headers: {
      Connection: "Upgrade", Upgrade: "websocket", Origin: "https://evil.example",
      "Sec-WebSocket-Version": "13", "Sec-WebSocket-Key": "dGhlIHNhbXBsZSBub25jZQ==" } });
    req.on("response", (resp) => res(resp.statusCode));
    req.on("upgrade", () => res(101));
    req.on("error", () => res(0));
    req.end();
  });
  ok(status === 403, "foreign origin cannot join rooms: " + status);
}

console.log("FAILS:", fails);
process.exit(fails ? 1 : 0);
