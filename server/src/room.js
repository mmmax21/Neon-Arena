// One Durable Object per co-op room: a dumb relay between the host (slot 0) and up to
// MAX_GUESTS guests. The host's game is authoritative; this only forwards text frames.
//
// Host -> server: raw frame, broadcast to every guest. A frame starting with "@<slot>|" goes
//                 to that guest only.
// Guest -> server: raw frame, forwarded to the host as "<slot>|<frame>".
// Server -> clients (system lines start with "#"):
//   "#hello <slot>"   your slot after joining (0 = host)
//   "#join <slot>"    to the host: a guest arrived
//   "#leave <slot>"   to the host: a guest left
//   "#host_left"      to guests: the room is over
//   "#full" / "#gone" before closing a socket that can't join

export const ROOM_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";
export const ROOM_CODE_LEN = 4;
const MAX_GUESTS = 1;            // 2-player prototype; the protocol already carries slots
const ROOM_TTL_MS = 3 * 3600 * 1000;
const MAX_FRAME = 64 * 1024;

export class Room {
  constructor(state, env) {
    this.state = state;
    this.env = env;
  }

  async fetch(request) {
    const url = new URL(request.url);
    if (url.pathname === "/create") {
      const created = await this.state.storage.get("created");
      if (created && Date.now() - created < ROOM_TTL_MS) return new Response("taken", { status: 409 });
      await this.state.storage.deleteAll();
      await this.state.storage.put("created", Date.now());
      await this.state.storage.setAlarm(Date.now() + ROOM_TTL_MS);
      return new Response("ok");
    }
    if (url.pathname !== "/join") return new Response("not found", { status: 404 });
    const pair = new WebSocketPair();
    const [client, server] = Object.values(pair);
    const created = await this.state.storage.get("created");
    const sockets = this.state.getWebSockets();
    let slot = -1;
    if (created) {
      const used = new Set(sockets.map((ws) => this.slotOf(ws)));
      const hostGone = (await this.state.storage.get("host_left")) === true;
      if (!used.has(0) && !hostGone && sockets.length === 0) slot = 0;
      else if (used.has(0)) {
        for (let s = 1; s <= MAX_GUESTS; s++) if (!used.has(s)) { slot = s; break; }
      }
    }
    this.state.acceptWebSocket(server, [String(slot)]);
    if (slot < 0) {
      server.send(created ? "#full" : "#gone");
      server.close(4000, created ? "full" : "gone");
    } else {
      server.send(`#hello ${slot}`);
      if (slot > 0) this.send(0, `#join ${slot}`);
    }
    return new Response(null, { status: 101, webSocket: client });
  }

  slotOf(ws) {
    const tags = this.state.getTags(ws);
    return tags.length ? parseInt(tags[0], 10) : -1;
  }

  send(slot, msg) {
    for (const ws of this.state.getWebSockets(String(slot))) {
      try { ws.send(msg); } catch (_) { /* socket closing */ }
    }
  }

  async webSocketMessage(ws, msg) {
    if (typeof msg !== "string" || msg.length > MAX_FRAME) return;
    const slot = this.slotOf(ws);
    if (slot === 0) {
      if (msg.startsWith("@")) {
        const bar = msg.indexOf("|");
        const to = parseInt(msg.slice(1, bar), 10);
        if (to > 0) this.send(to, msg.slice(bar + 1));
        return;
      }
      for (let s = 1; s <= MAX_GUESTS; s++) this.send(s, msg);
    } else if (slot > 0) {
      this.send(0, `${slot}|${msg}`);
    }
  }

  async webSocketClose(ws) {
    await this.left(ws);
  }

  async webSocketError(ws) {
    await this.left(ws);
  }

  async left(ws) {
    const slot = this.slotOf(ws);
    if (slot === 0) {
      await this.state.storage.put("host_left", true);
      for (let s = 1; s <= MAX_GUESTS; s++) {
        this.send(s, "#host_left");
        for (const g of this.state.getWebSockets(String(s))) {
          try { g.close(4001, "host_left"); } catch (_) {}
        }
      }
    } else if (slot > 0) {
      this.send(0, `#leave ${slot}`);
    }
  }

  async alarm() {
    for (const ws of this.state.getWebSockets()) {
      try { ws.close(4002, "expired"); } catch (_) {}
    }
    await this.state.storage.deleteAll();
  }
}
