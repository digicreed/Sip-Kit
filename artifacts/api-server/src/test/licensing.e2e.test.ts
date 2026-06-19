/**
 * End-to-end integration tests for the SipKit licensing flow.
 * These tests run against a real DB (DATABASE_URL) and the actual Express app.
 *
 * Flow tested: activate → refresh → revoke → refresh (must 401)
 */
import { describe, it, expect, beforeAll, afterAll } from "vitest";
import { generateKeyPairSync } from "node:crypto";
import supertest from "supertest";
import { db } from "@workspace/db";
import { sql } from "drizzle-orm";

// Inject test RSA keys BEFORE importing anything that reads them
const { privateKey, publicKey } = generateKeyPairSync("rsa", {
  modulusLength: 2048,
  publicKeyEncoding: { type: "spki", format: "pem" },
  privateKeyEncoding: { type: "pkcs8", format: "pem" },
});
process.env["JWT_PRIVATE_KEY"] = privateKey;
process.env["JWT_PUBLIC_KEY"] = publicKey;
process.env["ADMIN_API_KEY"] = "e2e-test-admin-key";
process.env["ENTITLEMENT_TTL_SECONDS"] = "86400";
process.env["REFRESH_TOKEN_TTL_DAYS"] = "30";
process.env["CORS_ORIGINS"] = "*";

const app = (await import("../app.js")).default;

const request = supertest(app);
const ADMIN = { Authorization: "Bearer e2e-test-admin-key" };

let providerId: string;
let licenseId: string;
let licenseKey: string;

beforeAll(async () => {
  const provRes = await request
    .post("/api/v1/admin/providers")
    .set(ADMIN)
    .send({ name: "E2E Provider", contactEmail: "e2e@test.com" });
  expect(provRes.status).toBe(201);
  providerId = provRes.body.id;

  const licRes = await request
    .post(`/api/v1/admin/providers/${providerId}/licenses`)
    .set(ADMIN)
    .send({ features: ["audio", "video"], maxAccounts: 5, maxConcurrentCalls: 10, maxDevices: 5 });
  expect(licRes.status).toBe(201);
  licenseId = licRes.body.id;
  licenseKey = licRes.body.licenseKey;
});

afterAll(async () => {
  await db.execute(sql`DELETE FROM usage_events WHERE license_id IN (SELECT id FROM licenses WHERE provider_id = ${providerId}::uuid)`);
  await db.execute(sql`DELETE FROM refresh_tokens WHERE license_id IN (SELECT id FROM licenses WHERE provider_id = ${providerId}::uuid)`);
  await db.execute(sql`DELETE FROM devices WHERE license_id IN (SELECT id FROM licenses WHERE provider_id = ${providerId}::uuid)`);
  await db.execute(sql`DELETE FROM licenses WHERE provider_id = ${providerId}::uuid`);
  await db.execute(sql`DELETE FROM providers WHERE id = ${providerId}::uuid`);
});

describe("Full licensing e2e flow", () => {
  let refreshToken: string;
  let entitlementJwt: string;

  it("activates a new device and returns a JWT + refresh token", async () => {
    const res = await request
      .post("/api/v1/activate")
      .send({ licenseKey, appId: "com.e2e.test", deviceId: "e2e-device-1" });

    expect(res.status).toBe(200);
    expect(res.body.entitlement).toBeDefined();
    expect(res.body.refreshToken).toBeDefined();
    expect(res.body.expiresIn).toBeGreaterThan(0);

    entitlementJwt = res.body.entitlement;
    refreshToken = res.body.refreshToken;
  });

  it("re-activating same device returns a fresh JWT (idempotent)", async () => {
    const res = await request
      .post("/api/v1/activate")
      .send({ licenseKey, appId: "com.e2e.test", deviceId: "e2e-device-1" });

    expect(res.status).toBe(200);
    expect(res.body.entitlement).toBeDefined();
  });

  it("records usage via the entitlement JWT (provider/appId ownership check)", async () => {
    const res = await request
      .post("/api/v1/usage")
      .set("Authorization", `Bearer ${entitlementJwt}`)
      .send({ deviceId: "e2e-device-1", callMinutes: 5, registrations: 1, callsPlaced: 2 });

    expect(res.status).toBe(200);
    expect(res.body.ok).toBe(true);
  });

  it("rejects usage for a device that doesn't belong to the JWT's provider", async () => {
    const res = await request
      .post("/api/v1/usage")
      .set("Authorization", `Bearer ${entitlementJwt}`)
      .send({ deviceId: "nonexistent-device-xyz", callMinutes: 1, registrations: 0, callsPlaced: 0 });

    expect(res.status).toBe(403);
  });

  it("refreshes the token and returns new JWT + new refresh token", async () => {
    const res = await request
      .post("/api/v1/refresh")
      .send({ refreshToken });

    expect(res.status).toBe(200);
    expect(res.body.entitlement).toBeDefined();
    expect(res.body.refreshToken).toBeDefined();
    expect(res.body.refreshToken).not.toBe(refreshToken);

    refreshToken = res.body.refreshToken;
  });

  it("rejects reuse of a consumed refresh token (rotation security)", async () => {
    const originalToken = refreshToken;

    const firstUse = await request
      .post("/api/v1/refresh")
      .send({ refreshToken: originalToken });
    expect(firstUse.status).toBe(200);

    const reuse = await request
      .post("/api/v1/refresh")
      .send({ refreshToken: originalToken });
    expect(reuse.status).toBe(401);

    refreshToken = firstUse.body.refreshToken;
  });

  it("revokes the license and all its refresh tokens via admin API", async () => {
    const res = await request
      .post(`/api/v1/admin/licenses/${licenseId}/revoke`)
      .set(ADMIN);

    expect(res.status).toBe(200);
    expect(res.body.ok).toBe(true);
    expect(res.body.revokedAt).toBeDefined();
  });

  it("refresh after revoke returns 401 — revocation propagated", async () => {
    const res = await request
      .post("/api/v1/refresh")
      .send({ refreshToken });

    expect(res.status).toBe(401);
  });

  it("activate with revoked license key returns 401", async () => {
    const res = await request
      .post("/api/v1/activate")
      .send({ licenseKey, appId: "com.e2e.test", deviceId: "e2e-device-2" });

    expect(res.status).toBe(401);
  });

  it("admin revoking an already-revoked license returns 404", async () => {
    const res = await request
      .post(`/api/v1/admin/licenses/${licenseId}/revoke`)
      .set(ADMIN);

    expect(res.status).toBe(404);
  });
});

describe("Invalid inputs", () => {
  it("returns 400 when licenseKey is missing", async () => {
    const res = await request
      .post("/api/v1/activate")
      .send({ appId: "com.test", deviceId: "dev-1" });

    expect(res.status).toBe(400);
  });

  it("returns 401 for a completely invalid license key", async () => {
    const res = await request
      .post("/api/v1/activate")
      .send({ licenseKey: "pk_live_FAKE_KEY_THAT_DOES_NOT_EXIST", appId: "com.test", deviceId: "dev-1" });

    expect(res.status).toBe(401);
  });

  it("returns 401 for a missing refresh token", async () => {
    const res = await request
      .post("/api/v1/refresh")
      .send({});

    expect(res.status).toBe(400);
  });

  it("returns 401 for usage report with no auth token", async () => {
    const res = await request
      .post("/api/v1/usage")
      .send({ deviceId: "dev-1", callMinutes: 1 });

    expect(res.status).toBe(401);
  });

  it("returns 401 for admin route without auth", async () => {
    const res = await request
      .post("/api/v1/admin/providers")
      .send({ name: "No Auth", contactEmail: "x@x.com" });

    expect(res.status).toBe(401);
  });
});

describe("Public key endpoints", () => {
  it("returns PEM public key", async () => {
    const res = await request.get("/api/v1/public-key");

    expect(res.status).toBe(200);
    expect(res.text).toContain("BEGIN PUBLIC KEY");
  });

  it("returns JWKS with at least one key", async () => {
    const res = await request.get("/api/v1/jwks");

    expect(res.status).toBe(200);
    expect(Array.isArray(res.body.keys)).toBe(true);
    expect(res.body.keys.length).toBeGreaterThan(0);
    expect(res.body.keys[0].kty).toBe("RSA");
  });
});
