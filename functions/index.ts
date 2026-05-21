// functions/index.ts — Ascend backend.
//
// Routes:
//   POST /apple/revoke   — Sign in with Apple token revocation (5.1.1(v)).
//   /users/upsert, /rankings/global, /circles[/...]   — proxied to Hub DO.
//   GET /.well-known/apple-app-site-association       — Universal Links AASA.
//   GET /join/:code     — friendly landing page (universal link target).

export { Hub } from "./hub";

const APPLE_TEAM_ID = "GN4CT6R6J6";
const APPLE_KEY_ID = "447RG852Y8";
const APPLE_CLIENT_ID = "app.rork.5dm6zbnyue71m6ouijlfh";
const APPLE_P8 = `-----BEGIN PRIVATE KEY-----
MIGTAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBHkwdwIBAQQg9CIkt/m0aeyoqBa5
ucNO2W4WW6S9L5N2rNDZ8X/n9RSgCgYIKoZIzj0DAQehRANCAAQH9Rnh0dZgwY/f
jhZnRL90vZBesT7vhfBtnFnRwmm1n/OPXCJTi8lRNL8gql7vUglCxDiALnZEjcrh
gfC05v5F
-----END PRIVATE KEY-----`;

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, DELETE, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, X-Ascend-User",
};

type Env = { DO: Fetcher };

const HUB_ID = "global";

const HUB_PREFIXES = ["/users/", "/rankings/", "/circles"];

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: CORS });
    }

    if (url.pathname === "/ping") {
      return Response.json({ ok: true, now: new Date().toISOString() });
    }

    if (url.pathname === "/.well-known/apple-app-site-association") {
      return aasa();
    }

    if (url.pathname.startsWith("/join/")) {
      const code = url.pathname.slice("/join/".length).toUpperCase();
      return joinLanding(code);
    }

    if (url.pathname === "/apple/revoke" && request.method === "POST") {
      return handleAppleRevoke(request);
    }

    // Hub DO routes.
    if (
      url.pathname === "/users/upsert" ||
      url.pathname === "/rankings/global" ||
      url.pathname === "/circles" ||
      url.pathname.startsWith("/circles/")
    ) {
      const wrapped = new Request(request.url, request);
      wrapped.headers.set("X-Rork-DO-Class", "Hub");
      wrapped.headers.set("X-Rork-DO-Id", HUB_ID);
      const res = await env.DO.fetch(wrapped);
      // make sure CORS is applied
      const out = new Response(res.body, res);
      for (const [k, v] of Object.entries(CORS)) out.headers.set(k, v);
      return out;
    }

    return new Response("not found", { status: 404, headers: CORS });
  },
};

// ---------- Universal Links ----------

function aasa(): Response {
  // applinks for the join URL pattern + the broader app paths so the system
  // opens the app when tapping invite links.
  const body = {
    applinks: {
      details: [
        {
          appIDs: [`${APPLE_TEAM_ID}.${APPLE_CLIENT_ID}`],
          components: [
            { "/": "/join/*", comment: "Circle invites" },
          ],
        },
      ],
    },
  };
  return new Response(JSON.stringify(body), {
    status: 200,
    headers: {
      ...CORS,
      "Content-Type": "application/json",
      "Cache-Control": "public, max-age=300",
    },
  });
}

function joinLanding(code: string): Response {
  const safe = code.replace(/[^A-Z0-9]/g, "").slice(0, 6);
  const html = `<!doctype html>
<html lang="en"><head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width,initial-scale=1"/>
<title>Join an Ascend circle</title>
<style>
  :root { color-scheme: dark; }
  body{margin:0;font-family:-apple-system,BlinkMacSystemFont,'SF Pro Display',sans-serif;
       background:#0c0c0f;color:#f3f3f6;min-height:100vh;display:flex;
       flex-direction:column;align-items:center;justify-content:center;padding:24px;text-align:center}
  .code{font-family:ui-monospace,Menlo,monospace;letter-spacing:0.45em;
       font-size:34px;font-weight:700;margin:18px 0 28px;color:#fff}
  .hint{color:#9b9ba2;font-size:13px;margin-top:18px;max-width:320px}
  .label{color:#8b8b92;font-size:11px;letter-spacing:0.2em;text-transform:uppercase}
</style></head>
<body>
  <div class="label">Ascend · Circle invite</div>
  <div class="code">${safe}</div>
  <p class="hint">If Ascend is installed, this page would have opened directly into the join flow. Install Ascend from the App Store, then tap this link again — the code <strong>${safe}</strong> will be filled in automatically.</p>
</body></html>`;
  return new Response(html, {
    status: 200,
    headers: {
      ...CORS,
      "Content-Type": "text/html; charset=utf-8",
      "Cache-Control": "no-store",
    },
  });
}

// ---------- Apple Sign-In revoke (unchanged) ----------

async function handleAppleRevoke(request: Request): Promise<Response> {
  try {
    const body = (await request.json()) as { authorizationCode?: string };
    const code = body.authorizationCode?.trim();
    if (!code) {
      return json({ ok: false, error: "missing_authorization_code" }, 400);
    }

    const clientSecret = await makeAppleClientSecret();

    const tokenForm = new URLSearchParams({
      client_id: APPLE_CLIENT_ID,
      client_secret: clientSecret,
      code,
      grant_type: "authorization_code",
    });
    const tokenRes = await fetch("https://appleid.apple.com/auth/token", {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: tokenForm.toString(),
    });
    const tokenJson = (await tokenRes.json()) as {
      refresh_token?: string;
      access_token?: string;
      error?: string;
    };
    if (!tokenRes.ok) {
      console.warn("apple token exchange failed", tokenRes.status, tokenJson);
      return json(
        { ok: false, stage: "token", status: tokenRes.status, error: tokenJson.error ?? "token_exchange_failed" },
        200
      );
    }

    const tokenToRevoke = tokenJson.refresh_token ?? tokenJson.access_token;
    const tokenTypeHint = tokenJson.refresh_token ? "refresh_token" : "access_token";
    if (!tokenToRevoke) return json({ ok: false, error: "no_token_returned" }, 200);

    const revokeForm = new URLSearchParams({
      client_id: APPLE_CLIENT_ID,
      client_secret: clientSecret,
      token: tokenToRevoke,
      token_type_hint: tokenTypeHint,
    });
    const revokeRes = await fetch("https://appleid.apple.com/auth/revoke", {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: revokeForm.toString(),
    });
    if (!revokeRes.ok) {
      const txt = await revokeRes.text();
      console.warn("apple revoke failed", revokeRes.status, txt);
      return json({ ok: false, stage: "revoke", status: revokeRes.status, error: txt }, 200);
    }

    return json({ ok: true });
  } catch (err) {
    console.error("apple revoke handler error", err);
    return json({ ok: false, error: String(err) }, 500);
  }
}

function json(payload: unknown, status = 200): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}

async function makeAppleClientSecret(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = { alg: "ES256", kid: APPLE_KEY_ID, typ: "JWT" };
  const payload = {
    iss: APPLE_TEAM_ID,
    iat: now,
    exp: now + 60 * 5,
    aud: "https://appleid.apple.com",
    sub: APPLE_CLIENT_ID,
  };
  const enc = (obj: object) =>
    base64urlEncode(new TextEncoder().encode(JSON.stringify(obj)));
  const signingInput = `${enc(header)}.${enc(payload)}`;
  const key = await importApplePrivateKey(APPLE_P8);
  const sigBuf = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    new TextEncoder().encode(signingInput)
  );
  const sig = base64urlEncode(new Uint8Array(sigBuf));
  return `${signingInput}.${sig}`;
}

async function importApplePrivateKey(pem: string): Promise<CryptoKey> {
  const b64 = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s+/g, "");
  const der = base64Decode(b64);
  return crypto.subtle.importKey(
    "pkcs8",
    der,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"]
  );
}

function base64Decode(b64: string): ArrayBuffer {
  const bin = atob(b64);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out.buffer;
}

function base64urlEncode(bytes: Uint8Array): string {
  let bin = "";
  for (let i = 0; i < bytes.length; i++) bin += String.fromCharCode(bytes[i]);
  return btoa(bin).replace(/=+$/, "").replace(/\+/g, "-").replace(/\//g, "_");
}
