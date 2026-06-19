/**
 * push-worker.ts
 *
 * Fans out APNs VoIP push (iOS) and FCM data messages (Android) when the
 * licensing backend is notified that an inbound SIP call has arrived for a
 * registered device.
 *
 * Environment variables required at runtime:
 *
 *   APNs (token-based / .p8 auth):
 *     APNS_KEY_ID        – 10-char key ID from Apple Developer portal
 *     APNS_TEAM_ID       – 10-char Apple Team ID
 *     APNS_PRIVATE_KEY   – PEM/p8 content of AuthKey_XXXXXXXXXX.p8
 *     APNS_BUNDLE_ID     – your app's bundle ID (e.g. com.example.softphone)
 *     APNS_PRODUCTION    – "true" for production APNs; default is sandbox
 *
 *   FCM (HTTP v1 API, service-account auth):
 *     FCM_PROJECT_ID            – Firebase project ID
 *     FCM_SERVICE_ACCOUNT_JSON  – full service-account JSON string
 *
 * If these variables are absent the worker logs a warning and is a no-op, so
 * the backend starts cleanly in environments that have not yet configured push.
 */

import http2 from "node:http2";
import { createSign } from "node:crypto";
import { eq } from "drizzle-orm";
import { db } from "@workspace/db";
import { pushTokensTable } from "@workspace/db/schema";

// ─── Types ─────────────────────────────────────────────────────────────────

export interface IncomingCallPayload {
  callId: string;
  remoteUri: string;
  displayName: string;
  accountId?: string;
}

// ─── APNs VoIP push ────────────────────────────────────────────────────────

/**
 * Sends a VoIP push to a single APNs device token using token-based
 * (.p8) authentication.  Maintains one persistent HTTP/2 session per process.
 */
let apnsSession: http2.ClientHttp2Session | null = null;
let apnsJwtCache: string | null = null;
let apnsJwtIssuedAt = 0;

function buildApnsJwt(keyId: string, teamId: string, rawKey: string): string {
  const now = Math.floor(Date.now() / 1000);
  const header  = Buffer.from(JSON.stringify({ alg: "ES256", kid: keyId })).toString("base64url");
  const payload = Buffer.from(JSON.stringify({ iss: teamId, iat: now })).toString("base64url");
  const unsigned = `${header}.${payload}`;

  const sign = createSign("SHA256");
  sign.update(unsigned);
  const sig = sign.sign({ key: rawKey, dsaEncoding: "ieee-p1363" }, "base64url");

  return `${unsigned}.${sig}`;
}

function getApnsJwt(keyId: string, teamId: string, privateKey: string): string {
  const now = Math.floor(Date.now() / 1000);
  if (!apnsJwtCache || now - apnsJwtIssuedAt > 3000) {
    apnsJwtCache = buildApnsJwt(keyId, teamId, privateKey);
    apnsJwtIssuedAt = now;
  }
  return apnsJwtCache;
}

function getApnsSession(production: boolean): http2.ClientHttp2Session {
  const host = production
    ? "https://api.push.apple.com"
    : "https://api.sandbox.push.apple.com";

  if (!apnsSession || apnsSession.destroyed || apnsSession.closed) {
    apnsSession = http2.connect(host);
    apnsSession.on("error", () => { apnsSession = null; });
    apnsSession.on("close", () => { apnsSession = null; });
  }
  return apnsSession;
}

/**
 * Normalise a PEM/p8 key that may be stored in an environment variable
 * with escaped newlines (\\n) or spaces instead of real line breaks.
 * Mirrors the same logic used in lib/jwt.ts for RS256 keys.
 */
function normaliseKey(raw: string): string {
  let key = raw.replace(/\\n/g, "\n").trim();
  if (key.includes("\n")) return key;

  const match = key.match(/-----BEGIN ([^-]+)-----\s*([\s\S]+?)\s*-----END ([^-]+)-----/);
  if (!match) return key;

  const type = match[1]!.trim();
  const body = match[2]!.replace(/\s+/g, "");
  const lines: string[] = [];
  for (let i = 0; i < body.length; i += 64) lines.push(body.slice(i, i + 64));
  return `-----BEGIN ${type}-----\n${lines.join("\n")}\n-----END ${type}-----`;
}

export async function sendApnsPush(
  deviceToken: string,
  payload: IncomingCallPayload,
): Promise<void> {
  const keyId      = process.env["APNS_KEY_ID"];
  const teamId     = process.env["APNS_TEAM_ID"];
  const rawKey     = process.env["APNS_PRIVATE_KEY"];
  const bundleId   = process.env["APNS_BUNDLE_ID"];
  const production = process.env["APNS_PRODUCTION"] === "true";

  if (!keyId || !teamId || !rawKey || !bundleId) {
    console.warn("[push-worker] APNs not configured – skipping VoIP push");
    return;
  }

  const privateKey = normaliseKey(rawKey);

  const body = JSON.stringify({
    aps: {
      alert: { title: "Incoming Call", body: payload.displayName || payload.remoteUri },
    },
    callId:      payload.callId,
    remoteUri:   payload.remoteUri,
    displayName: payload.displayName,
    accountId:   payload.accountId ?? "",
  });

  return new Promise((resolve, reject) => {
    const session = getApnsSession(production);
    const req = session.request({
      ":method":         "POST",
      ":path":           `/3/device/${deviceToken}`,
      "apns-topic":      `${bundleId}.voip`,
      "apns-push-type":  "voip",
      "apns-priority":   "10",
      "apns-expiration": "0",
      authorization:     `bearer ${getApnsJwt(keyId, teamId, privateKey)}`,
      "content-type":    "application/json",
      "content-length":  Buffer.byteLength(body).toString(),
    });

    req.write(body);
    req.end();

    let status = 0;
    let responseBody = "";

    req.on("response", (headers) => { status = headers[":status"] as number; });
    req.on("data", (chunk: Buffer) => { responseBody += chunk.toString(); });
    req.on("end", () => {
      if (status === 200) {
        resolve();
      } else {
        reject(new Error(`APNs responded ${status}: ${responseBody}`));
      }
    });
    req.on("error", reject);
  });
}

// ─── FCM data push ─────────────────────────────────────────────────────────

interface ServiceAccount {
  client_email: string;
  private_key: string;
  token_uri: string;
}

async function getFcmAccessToken(sa: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const claims = {
    iss:   sa.client_email,
    sub:   sa.client_email,
    aud:   sa.token_uri,
    iat:   now,
    exp:   now + 3600,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
  };

  const header  = Buffer.from(JSON.stringify({ alg: "RS256", typ: "JWT" })).toString("base64url");
  const payload = Buffer.from(JSON.stringify(claims)).toString("base64url");
  const unsigned = `${header}.${payload}`;

  const sign = createSign("SHA256");
  sign.update(unsigned);
  const sig = sign.sign(sa.private_key, "base64url");
  const assertion = `${unsigned}.${sig}`;

  const body = new URLSearchParams({
    grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
    assertion,
  });

  const resp = await fetch(sa.token_uri, {
    method:  "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body:    body.toString(),
  });

  if (!resp.ok) {
    throw new Error(`FCM token exchange failed: ${resp.status} ${await resp.text()}`);
  }

  const json = await resp.json() as { access_token: string };
  return json.access_token;
}

export async function sendFcmPush(
  deviceToken: string,
  payload: IncomingCallPayload,
): Promise<void> {
  const projectId      = process.env["FCM_PROJECT_ID"];
  const serviceAccJson = process.env["FCM_SERVICE_ACCOUNT_JSON"];

  if (!projectId || !serviceAccJson) {
    console.warn("[push-worker] FCM not configured – skipping data push");
    return;
  }

  const sa = JSON.parse(serviceAccJson) as ServiceAccount;
  const accessToken = await getFcmAccessToken(sa);

  const message = {
    message: {
      token: deviceToken,
      data: {
        callId:      payload.callId,
        remoteUri:   payload.remoteUri,
        displayName: payload.displayName,
        accountId:   payload.accountId ?? "",
      },
      android: { priority: "high" },
    },
  };

  const resp = await fetch(
    `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
    {
      method:  "POST",
      headers: {
        authorization:  `Bearer ${accessToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify(message),
    },
  );

  if (!resp.ok) {
    throw new Error(`FCM send failed: ${resp.status} ${await resp.text()}`);
  }
}

// ─── Fan-out ───────────────────────────────────────────────────────────────

/**
 * Fan out an inbound-call push to every stored token for a given device DB ID.
 * Errors per token are logged but do not throw; the live SIP socket is the
 * primary delivery path — push is the fallback for cold-start wakeup.
 *
 * @param deviceDbId  UUID primary key from the `devices` table
 * @param payload     call metadata
 */
export async function fanOutCallPush(
  deviceDbId: string,
  payload: IncomingCallPayload,
): Promise<void> {
  const tokens = await db
    .select({ platform: pushTokensTable.platform, token: pushTokensTable.token })
    .from(pushTokensTable)
    .where(eq(pushTokensTable.deviceId, deviceDbId));

  await Promise.allSettled(
    tokens.map(async ({ platform, token }) => {
      try {
        if (platform === "apns") {
          await sendApnsPush(token, payload);
        } else if (platform === "fcm") {
          await sendFcmPush(token, payload);
        }
      } catch (err) {
        console.error(
          `[push-worker] ${platform} push failed for token ${token.slice(0, 10)}…:`,
          err,
        );
      }
    }),
  );
}
