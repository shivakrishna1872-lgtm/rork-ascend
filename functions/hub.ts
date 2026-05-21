// functions/hub.ts — Single Durable Object holding all global state for
// Ascend's social layer: users, circles, and rankings. SQLite is per-DO,
// so we keep everything in one instance keyed by "global".
//
// This is small-data (display name, xp, streak, tier, circle membership),
// well under the 1GB DO storage cap. If usage grows we can shard the
// rankings into a separate DO without changing the public API.

import { DurableObject } from "cloudflare:workers";

interface UserRow {
  id: string;
  name: string;
  xp: number;
  streak: number;
  tier: string;
  avatar_seed: string;
  updated_at: number;
}
interface CircleRow {
  id: string;
  name: string;
  accent: string;
  code: string;
  owner_id: string;
  created_at: number;
}

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, DELETE, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, X-Ascend-User",
};

function json(payload: unknown, status = 200): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}

function newId(): string {
  return crypto.randomUUID();
}

function genCode(): string {
  const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  let s = "";
  for (let i = 0; i < 6; i++) {
    s += alphabet[Math.floor(Math.random() * alphabet.length)];
  }
  return s;
}

export class Hub extends DurableObject {
  constructor(ctx: DurableObjectState, env: unknown) {
    super(ctx, env);
    this.ctx.storage.sql.exec(`
      CREATE TABLE IF NOT EXISTS users (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        xp INTEGER NOT NULL DEFAULT 0,
        streak INTEGER NOT NULL DEFAULT 0,
        tier TEXT NOT NULL DEFAULT 'bronze',
        avatar_seed TEXT NOT NULL DEFAULT '',
        updated_at INTEGER NOT NULL
      );
    `);
    this.ctx.storage.sql.exec(
      `CREATE INDEX IF NOT EXISTS users_xp ON users (xp DESC);`
    );
    this.ctx.storage.sql.exec(`
      CREATE TABLE IF NOT EXISTS circles (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        accent TEXT NOT NULL,
        code TEXT NOT NULL UNIQUE,
        owner_id TEXT NOT NULL,
        created_at INTEGER NOT NULL
      );
    `);
    this.ctx.storage.sql.exec(`
      CREATE TABLE IF NOT EXISTS circle_members (
        circle_id TEXT NOT NULL,
        user_id TEXT NOT NULL,
        joined_at INTEGER NOT NULL,
        PRIMARY KEY (circle_id, user_id)
      );
    `);
    this.ctx.storage.sql.exec(
      `CREATE INDEX IF NOT EXISTS cm_user ON circle_members (user_id);`
    );
  }

  override async fetch(request: Request): Promise<Response> {
    try {
      const url = new URL(request.url);
      const path = url.pathname;
      const method = request.method;

      if (method === "OPTIONS") {
        return new Response(null, { status: 204, headers: CORS });
      }

      if (path === "/users/upsert" && method === "POST") {
        return this.upsertUser(await request.json());
      }
      if (path === "/rankings/global" && method === "GET") {
        return this.globalRankings(url.searchParams.get("userId") ?? "");
      }
      if (path === "/circles" && method === "POST") {
        return this.createCircle(await request.json());
      }
      if (path === "/circles" && method === "GET") {
        return this.listCircles(url.searchParams.get("userId") ?? "");
      }
      if (path === "/circles/join" && method === "POST") {
        return this.joinCircle(await request.json());
      }
      const circleMatch = path.match(/^\/circles\/([^/]+)$/);
      if (circleMatch && method === "GET") {
        return this.getCircle(circleMatch[1], url.searchParams.get("userId") ?? "");
      }
      if (circleMatch && method === "DELETE") {
        return this.deleteCircle(circleMatch[1], url.searchParams.get("userId") ?? "");
      }
      const leaveMatch = path.match(/^\/circles\/([^/]+)\/leave$/);
      if (leaveMatch && method === "POST") {
        return this.leaveCircle(leaveMatch[1], (await request.json()) as { userId?: string });
      }

      return json({ ok: false, error: "not_found", path }, 404);
    } catch (err) {
      console.error("Hub error", err);
      return json({ ok: false, error: String(err) }, 500);
    }
  }

  // ----- Users / rankings -----

  private upsertUser(body: unknown): Response {
    const b = body as {
      userId?: string;
      name?: string;
      xp?: number;
      streak?: number;
      tier?: string;
      avatarSeed?: string;
    };
    const userId = (b.userId ?? "").trim();
    if (!userId) return json({ ok: false, error: "missing_userId" }, 400);
    const name = (b.name ?? "Athlete").trim().slice(0, 40) || "Athlete";
    const xp = Math.max(0, Math.floor(Number(b.xp ?? 0)));
    const streak = Math.max(0, Math.floor(Number(b.streak ?? 0)));
    const tier = (b.tier ?? "bronze").slice(0, 16);
    const avatarSeed = (b.avatarSeed ?? "").slice(0, 32);
    const now = Date.now();
    this.ctx.storage.sql.exec(
      `INSERT INTO users (id, name, xp, streak, tier, avatar_seed, updated_at)
       VALUES (?, ?, ?, ?, ?, ?, ?)
       ON CONFLICT(id) DO UPDATE SET
         name = excluded.name,
         xp = excluded.xp,
         streak = excluded.streak,
         tier = excluded.tier,
         avatar_seed = excluded.avatar_seed,
         updated_at = excluded.updated_at`,
      userId, name, xp, streak, tier, avatarSeed, now
    );
    return json({ ok: true, user: { id: userId, name, xp, streak, tier, avatarSeed } });
  }

  private globalRankings(userId: string): Response {
    const top = this.ctx.storage.sql
      .exec<UserRow>(
        `SELECT id, name, xp, streak, tier, avatar_seed, updated_at
         FROM users ORDER BY xp DESC, updated_at ASC LIMIT 100`
      )
      .toArray();
    const total = this.ctx.storage.sql
      .exec<{ c: number }>(`SELECT COUNT(*) AS c FROM users`)
      .toArray()[0]?.c ?? 0;

    let me: { rank: number; user: UserRow } | null = null;
    if (userId) {
      const meRow = this.ctx.storage.sql
        .exec<UserRow>(
          `SELECT id, name, xp, streak, tier, avatar_seed, updated_at
           FROM users WHERE id = ?`,
          userId
        )
        .toArray()[0];
      if (meRow) {
        const above = this.ctx.storage.sql
          .exec<{ c: number }>(
            `SELECT COUNT(*) AS c FROM users WHERE xp > ?
              OR (xp = ? AND updated_at < ?)`,
            meRow.xp, meRow.xp, meRow.updated_at
          )
          .toArray()[0]?.c ?? 0;
        me = { rank: above + 1, user: meRow };
      }
    }

    return json({
      ok: true,
      total,
      top: top.map((u, i) => ({ rank: i + 1, ...serializeUser(u) })),
      me: me ? { rank: me.rank, ...serializeUser(me.user) } : null,
    });
  }

  // ----- Circles -----

  private createCircle(body: unknown): Response {
    const b = body as {
      name?: string;
      accent?: string;
      ownerId?: string;
      ownerName?: string;
    };
    const ownerId = (b.ownerId ?? "").trim();
    if (!ownerId) return json({ ok: false, error: "missing_ownerId" }, 400);
    const name = (b.name ?? "").trim().slice(0, 40);
    if (!name) return json({ ok: false, error: "missing_name" }, 400);
    const accent = (b.accent ?? "steel").slice(0, 16);

    // ensure owner is registered as user (cheap upsert with whatever name)
    const now = Date.now();
    this.ctx.storage.sql.exec(
      `INSERT INTO users (id, name, xp, streak, tier, avatar_seed, updated_at)
       VALUES (?, ?, 0, 0, 'bronze', '', ?)
       ON CONFLICT(id) DO UPDATE SET
         name = CASE WHEN excluded.name <> '' THEN excluded.name ELSE users.name END,
         updated_at = excluded.updated_at`,
      ownerId, (b.ownerName ?? "Athlete").trim().slice(0, 40) || "Athlete", now
    );

    // unique code
    let code = "";
    for (let i = 0; i < 6; i++) {
      const candidate = genCode();
      const exists = this.ctx.storage.sql
        .exec<{ c: number }>(`SELECT COUNT(*) AS c FROM circles WHERE code = ?`, candidate)
        .toArray()[0]?.c ?? 0;
      if (!exists) { code = candidate; break; }
    }
    if (!code) return json({ ok: false, error: "code_collision" }, 500);

    const id = newId();
    this.ctx.storage.sql.exec(
      `INSERT INTO circles (id, name, accent, code, owner_id, created_at) VALUES (?, ?, ?, ?, ?, ?)`,
      id, name, accent, code, ownerId, now
    );
    this.ctx.storage.sql.exec(
      `INSERT INTO circle_members (circle_id, user_id, joined_at) VALUES (?, ?, ?)`,
      id, ownerId, now
    );
    return json({ ok: true, circle: this.buildCircle(id, ownerId) });
  }

  private joinCircle(body: unknown): Response {
    const b = body as { code?: string; userId?: string; userName?: string };
    const userId = (b.userId ?? "").trim();
    const code = (b.code ?? "").trim().toUpperCase();
    if (!userId) return json({ ok: false, error: "missing_userId" }, 400);
    if (code.length !== 6) return json({ ok: false, error: "bad_code" }, 400);

    const c = this.ctx.storage.sql
      .exec<CircleRow>(
        `SELECT id, name, accent, code, owner_id, created_at FROM circles WHERE code = ?`,
        code
      )
      .toArray()[0];
    if (!c) return json({ ok: false, error: "code_not_found" }, 404);

    const now = Date.now();
    // make sure user row exists
    this.ctx.storage.sql.exec(
      `INSERT INTO users (id, name, xp, streak, tier, avatar_seed, updated_at)
       VALUES (?, ?, 0, 0, 'bronze', '', ?)
       ON CONFLICT(id) DO UPDATE SET
         name = CASE WHEN excluded.name <> '' THEN excluded.name ELSE users.name END,
         updated_at = excluded.updated_at`,
      userId, (b.userName ?? "Athlete").trim().slice(0, 40) || "Athlete", now
    );

    this.ctx.storage.sql.exec(
      `INSERT OR IGNORE INTO circle_members (circle_id, user_id, joined_at) VALUES (?, ?, ?)`,
      c.id, userId, now
    );

    return json({ ok: true, circle: this.buildCircle(c.id, userId) });
  }

  private listCircles(userId: string): Response {
    if (!userId) return json({ ok: true, circles: [] });
    const ids = this.ctx.storage.sql
      .exec<{ circle_id: string }>(
        `SELECT circle_id FROM circle_members WHERE user_id = ?`,
        userId
      )
      .toArray().map((r) => r.circle_id);
    const circles = ids.map((id) => this.buildCircle(id, userId));
    return json({ ok: true, circles });
  }

  private getCircle(id: string, userId: string): Response {
    const c = this.ctx.storage.sql
      .exec<CircleRow>(
        `SELECT id, name, accent, code, owner_id, created_at FROM circles WHERE id = ?`,
        id
      )
      .toArray()[0];
    if (!c) return json({ ok: false, error: "not_found" }, 404);
    return json({ ok: true, circle: this.buildCircle(id, userId) });
  }

  private leaveCircle(id: string, body: { userId?: string }): Response {
    const userId = (body.userId ?? "").trim();
    if (!userId) return json({ ok: false, error: "missing_userId" }, 400);
    this.ctx.storage.sql.exec(
      `DELETE FROM circle_members WHERE circle_id = ? AND user_id = ?`,
      id, userId
    );
    // if no one left, drop the circle entirely
    const left = this.ctx.storage.sql
      .exec<{ c: number }>(`SELECT COUNT(*) AS c FROM circle_members WHERE circle_id = ?`, id)
      .toArray()[0]?.c ?? 0;
    if (left === 0) {
      this.ctx.storage.sql.exec(`DELETE FROM circles WHERE id = ?`, id);
    }
    return json({ ok: true });
  }

  private deleteCircle(id: string, userId: string): Response {
    const c = this.ctx.storage.sql
      .exec<CircleRow>(`SELECT owner_id FROM circles WHERE id = ?`, id)
      .toArray()[0];
    if (!c) return json({ ok: false, error: "not_found" }, 404);
    if (c.owner_id !== userId) return json({ ok: false, error: "not_owner" }, 403);
    this.ctx.storage.sql.exec(`DELETE FROM circle_members WHERE circle_id = ?`, id);
    this.ctx.storage.sql.exec(`DELETE FROM circles WHERE id = ?`, id);
    return json({ ok: true });
  }

  // ----- helpers -----

  private buildCircle(id: string, viewerId: string) {
    const c = this.ctx.storage.sql
      .exec<CircleRow>(
        `SELECT id, name, accent, code, owner_id, created_at FROM circles WHERE id = ?`,
        id
      )
      .toArray()[0];
    if (!c) return null;
    const members = this.ctx.storage.sql
      .exec<UserRow & { joined_at: number }>(
        `SELECT u.id, u.name, u.xp, u.streak, u.tier, u.avatar_seed, u.updated_at, m.joined_at
         FROM circle_members m JOIN users u ON u.id = m.user_id
         WHERE m.circle_id = ?
         ORDER BY u.xp DESC, m.joined_at ASC`,
        id
      )
      .toArray();
    return {
      id: c.id,
      name: c.name,
      accent: c.accent,
      code: c.code,
      ownerId: c.owner_id,
      createdAt: c.created_at,
      memberCount: members.length,
      isOwner: c.owner_id === viewerId,
      members: members.map((m, i) => ({
        rank: i + 1,
        id: m.id,
        name: m.name,
        xp: m.xp,
        streak: m.streak,
        tier: m.tier,
        avatarSeed: m.avatar_seed,
        isMe: m.id === viewerId,
        joinedAt: m.joined_at,
      })),
    };
  }
}

function serializeUser(u: UserRow) {
  return {
    id: u.id,
    name: u.name,
    xp: u.xp,
    streak: u.streak,
    tier: u.tier,
    avatarSeed: u.avatar_seed,
  };
}
