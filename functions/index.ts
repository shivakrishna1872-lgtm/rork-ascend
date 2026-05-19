// functions/index.ts — Ascend backend.
//
// Currently exposes one route:
//   POST /apple/revoke   { authorizationCode } -> { ok: true }
//
// This is the App Store-compliant "Sign in with Apple" token revocation
// flow (Apple Review Guideline 5.1.1(v)): when a user deletes their
// account, the app sends Apple's authorizationCode here, we exchange it
// for a refresh_token, then revoke that token so Apple unlinks the user
// from this app.

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
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type",
};

export default {
  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);

    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: CORS });
    }

    if (url.pathname === "/ping") {
      return Response.json({ ok: true, now: new Date().toISOString() });
    }

    if (url.pathname === "/apple/revoke" && request.method === "POST") {
      return handleAppleRevoke(request);
    }

    return new Response("not found", { status: 404, headers: CORS });
  },
};

async function handleAppleRevoke(request: Request): Promise<Response> {
  try {
    const body = (await request.json()) as { authorizationCode?: string };
    const code = body.authorizationCode?.trim();
    if (!code) {
      return json({ ok: false, error: "missing_authorization_code" }, 400);
    }

    const clientSecret = await makeAppleClientSecret();

    // 1. Exchange the authorization code for a refresh_token.
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
      error_description?: string;
    };
    if (!tokenRes.ok) {
      // Even if the code is already exchanged/expired we still want delete
      // to succeed on-device; surface the error but allow client to continue.
      console.warn("apple token exchange failed", tokenRes.status, tokenJson);
      return json(
        { ok: false, stage: "token", status: tokenRes.status, error: tokenJson.error ?? "token_exchange_failed" },
        200
      );
    }

    const tokenToRevoke = tokenJson.refresh_token ?? tokenJson.access_token;
    const tokenTypeHint = tokenJson.refresh_token ? "refresh_token" : "access_token";
    if (!tokenToRevoke) {
      return json({ ok: false, error: "no_token_returned" }, 200);
    }

    // 2. Revoke the refresh_token.
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

// ---------- Apple client_secret JWT (ES256) ----------

/** Build the signed JWT Apple expects as `client_secret`. Valid ≤ 6 months. */
async function makeAppleClientSecret(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = { alg: "ES256", kid: APPLE_KEY_ID, typ: "JWT" };
  const payload = {
    iss: APPLE_TEAM_ID,
    iat: now,
    exp: now + 60 * 5, // 5 minutes — we mint fresh every call.
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
