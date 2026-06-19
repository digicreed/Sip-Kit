import { Router } from "express";
import rateLimit from "express-rate-limit";
import bcrypt from "bcryptjs";
import { v4 as uuidv4 } from "uuid";
import { eq, and, isNull } from "drizzle-orm";
import { db } from "@workspace/db";
import {
  licensesTable,
  devicesTable,
  refreshTokensTable,
} from "@workspace/db/schema";
import { signEntitlement } from "../../lib/jwt.js";

const router = Router();

const REFRESH_TOKEN_TTL_DAYS = parseInt(process.env["REFRESH_TOKEN_TTL_DAYS"] ?? "30");

const ipLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 20,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: "Too many activation attempts, please try again later" },
});

const perKeyLimiter = rateLimit({
  windowMs: 60 * 60 * 1000,
  max: 50,
  keyGenerator: (req) => {
    const { licenseKey } = (req as { body?: { licenseKey?: string } }).body ?? {};
    return licenseKey ? `key:${licenseKey.slice(-16)}` : (req.ip ?? "unknown");
  },
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: "Too many activations for this license key, please try again later" },
});

router.post("/activate", ipLimiter, perKeyLimiter, async (req, res) => {
  const { licenseKey, appId, deviceId } = req.body as {
    licenseKey?: string;
    appId?: string;
    deviceId?: string;
  };

  if (!licenseKey || !appId || !deviceId) {
    res.status(400).json({ error: "licenseKey, appId, and deviceId are required" });
    return;
  }

  try {
    const licenses = await db
      .select()
      .from(licensesTable)
      .where(isNull(licensesTable.revokedAt))
      .limit(200);

    let matchedLicense = null;
    for (const license of licenses) {
      const match = await bcrypt.compare(licenseKey, license.keyHash);
      if (match) {
        matchedLicense = license;
        break;
      }
    }

    if (!matchedLicense) {
      res.status(401).json({ error: "Unauthorized" });
      return;
    }

    if (matchedLicense.expiresAt && matchedLicense.expiresAt < new Date()) {
      res.status(401).json({ error: "Unauthorized" });
      return;
    }

    const existingDevices = await db
      .select()
      .from(devicesTable)
      .where(eq(devicesTable.licenseId, matchedLicense.id));

    const isExistingDevice = existingDevices.some((d) => d.deviceId === deviceId && d.appId === appId);

    if (!isExistingDevice && existingDevices.length >= matchedLicense.maxDevices) {
      res.status(401).json({ error: "Unauthorized" });
      return;
    }

    let device;
    if (isExistingDevice) {
      const existing = existingDevices.find((d) => d.deviceId === deviceId && d.appId === appId)!;
      await db
        .update(devicesTable)
        .set({ lastSeen: new Date() })
        .where(eq(devicesTable.id, existing.id));
      device = existing;
    } else {
      const [newDevice] = await db
        .insert(devicesTable)
        .values({ licenseId: matchedLicense.id, deviceId, appId })
        .returning();
      device = newDevice;
    }

    const rawRefreshToken = uuidv4() + "-" + uuidv4();
    const refreshTokenHash = await bcrypt.hash(rawRefreshToken, 10);
    const refreshExpiry = new Date();
    refreshExpiry.setDate(refreshExpiry.getDate() + REFRESH_TOKEN_TTL_DAYS);

    await db.insert(refreshTokensTable).values({
      licenseId: matchedLicense.id,
      deviceId: device!.id,
      tokenHash: refreshTokenHash,
      expiresAt: refreshExpiry,
    });

    const entitlementTtl = parseInt(process.env["ENTITLEMENT_TTL_SECONDS"] ?? "86400");
    const entitlementJwt = signEntitlement({
      sub: matchedLicense.providerId,
      appId,
      features: matchedLicense.features as string[],
      maxAccounts: matchedLicense.maxAccounts,
      maxConcurrentCalls: matchedLicense.maxConcurrentCalls,
    });

    res.json({
      entitlement: entitlementJwt,
      refreshToken: rawRefreshToken,
      expiresIn: entitlementTtl,
    });
  } catch (err) {
    req.log.error({ err }, "Activation error");
    res.status(500).json({ error: "Internal server error" });
  }
});

export default router;
