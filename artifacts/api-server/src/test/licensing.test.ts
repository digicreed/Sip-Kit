import { describe, it, expect, beforeAll } from "vitest";
import { generateKeyPairSync } from "node:crypto";
import jwt from "jsonwebtoken";

const { privateKey, publicKey } = generateKeyPairSync("rsa", {
  modulusLength: 2048,
  publicKeyEncoding: { type: "spki", format: "pem" },
  privateKeyEncoding: { type: "pkcs8", format: "pem" },
});

process.env["JWT_PRIVATE_KEY"] = privateKey;
process.env["JWT_PUBLIC_KEY"] = publicKey;
process.env["ADMIN_API_KEY"] = "test-admin-key";

const { signEntitlement, verifyEntitlement } = await import("../lib/jwt.js");

describe("JWT entitlement signing and verification", () => {
  it("signs and verifies a valid entitlement", () => {
    const token = signEntitlement({
      sub: "provider-123",
      appId: "com.test.app",
      features: ["audio", "video"],
      maxAccounts: 5,
      maxConcurrentCalls: 10,
    });

    const claims = verifyEntitlement(token);
    expect(claims.sub).toBe("provider-123");
    expect(claims.appId).toBe("com.test.app");
    expect(claims.features).toContain("audio");
    expect(claims.features).toContain("video");
    expect(claims.maxAccounts).toBe(5);
    expect(claims.maxConcurrentCalls).toBe(10);
    expect(claims.iss).toBe("sipkit-license");
    expect(claims.jti).toBeDefined();
  });

  it("throws on a tampered/invalid token", () => {
    const token = signEntitlement({
      sub: "provider-123",
      appId: "com.test.app",
      features: ["audio"],
      maxAccounts: 5,
      maxConcurrentCalls: 10,
    });

    const tampered = token.slice(0, -5) + "XXXXX";
    expect(() => verifyEntitlement(tampered)).toThrow();
  });

  it("throws on an expired token", () => {
    const expired = jwt.sign(
      {
        iss: "sipkit-license",
        sub: "provider-123",
        appId: "com.test.app",
        features: ["audio"],
        maxAccounts: 5,
        maxConcurrentCalls: 10,
        jti: "test-jti",
      },
      privateKey,
      { algorithm: "RS256", expiresIn: -1 }
    );

    expect(() => verifyEntitlement(expired)).toThrow();
  });

  it("throws when signed with a different private key", () => {
    const { privateKey: otherKey } = generateKeyPairSync("rsa", {
      modulusLength: 2048,
      publicKeyEncoding: { type: "spki", format: "pem" },
      privateKeyEncoding: { type: "pkcs8", format: "pem" },
    });

    const wrongKeyToken = jwt.sign(
      {
        iss: "sipkit-license",
        sub: "provider-123",
        appId: "com.test.app",
        features: ["audio"],
        maxAccounts: 5,
        maxConcurrentCalls: 10,
        jti: "test-jti",
      },
      otherKey,
      { algorithm: "RS256", expiresIn: "24h" }
    );

    expect(() => verifyEntitlement(wrongKeyToken)).toThrow();
  });
});

describe("Feature gating logic", () => {
  it("entitlement includes requested features", () => {
    const token = signEntitlement({
      sub: "provider-456",
      appId: "com.voip.app",
      features: ["audio", "conference"],
      maxAccounts: 3,
      maxConcurrentCalls: 5,
    });

    const claims = verifyEntitlement(token);
    expect(claims.features).toContain("conference");
    expect(claims.features).not.toContain("video");
  });

  it("entitlement respects maxAccounts limit", () => {
    const token = signEntitlement({
      sub: "provider-789",
      appId: "com.limited.app",
      features: ["audio"],
      maxAccounts: 2,
      maxConcurrentCalls: 5,
    });

    const claims = verifyEntitlement(token);
    expect(claims.maxAccounts).toBe(2);
  });

  it("entitlement without video feature should not contain video", () => {
    const token = signEntitlement({
      sub: "provider-100",
      appId: "com.audio-only.app",
      features: ["audio", "dtmf"],
      maxAccounts: 5,
      maxConcurrentCalls: 20,
    });

    const claims = verifyEntitlement(token);
    expect(claims.features).not.toContain("video");
    expect(claims.features).toContain("dtmf");
  });
});

describe("Admin auth middleware", () => {
  it("accepts valid admin key", async () => {
    const { requireAdminKey } = await import("../middlewares/admin-auth.js");

    const req = {
      headers: { authorization: "Bearer test-admin-key" },
    } as any;
    const res = {
      status: () => res,
      json: () => res,
    } as any;

    let nextCalled = false;
    requireAdminKey(req, res, () => { nextCalled = true; });
    expect(nextCalled).toBe(true);
  });

  it("rejects missing auth header", async () => {
    const { requireAdminKey } = await import("../middlewares/admin-auth.js");

    const req = { headers: {} } as any;
    let statusCode = 0;
    const res = {
      status: (code: number) => { statusCode = code; return res; },
      json: () => res,
    } as any;

    requireAdminKey(req, res, () => {});
    expect(statusCode).toBe(401);
  });

  it("rejects wrong admin key", async () => {
    const { requireAdminKey } = await import("../middlewares/admin-auth.js");

    const req = {
      headers: { authorization: "Bearer wrong-key" },
    } as any;
    let statusCode = 0;
    const res = {
      status: (code: number) => { statusCode = code; return res; },
      json: () => res,
    } as any;

    requireAdminKey(req, res, () => {});
    expect(statusCode).toBe(401);
  });
});

describe("Entitlement auth middleware", () => {
  it("accepts a valid entitlement token", async () => {
    const { requireEntitlement } = await import("../middlewares/entitlement-auth.js");

    const token = signEntitlement({
      sub: "provider-123",
      appId: "com.test.app",
      features: ["audio"],
      maxAccounts: 5,
      maxConcurrentCalls: 10,
    });

    const req = {
      headers: { authorization: `Bearer ${token}` },
    } as any;
    const res = {
      status: () => res,
      json: () => res,
    } as any;

    let nextCalled = false;
    requireEntitlement(req, res, () => { nextCalled = true; });
    expect(nextCalled).toBe(true);
    expect(req.entitlement).toBeDefined();
    expect(req.entitlement.sub).toBe("provider-123");
  });

  it("rejects a missing token", async () => {
    const { requireEntitlement } = await import("../middlewares/entitlement-auth.js");

    const req = { headers: {} } as any;
    let statusCode = 0;
    const res = {
      status: (code: number) => { statusCode = code; return res; },
      json: () => res,
    } as any;

    requireEntitlement(req, res, () => {});
    expect(statusCode).toBe(401);
  });
});
