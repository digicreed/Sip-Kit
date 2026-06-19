import { Router } from "express";
import bcrypt from "bcryptjs";
import { v4 as uuidv4 } from "uuid";
import { eq, and, isNull, gt } from "drizzle-orm";
import { db } from "@workspace/db";
import {
  licensesTable,
  devicesTable,
  refreshTokensTable,
} from "@workspace/db/schema";
import { signEntitlement } from "../../lib/jwt.js";

const router = Router();

const REFRESH_TOKEN_TTL_DAYS = parseInt(process.env["REFRESH_TOKEN_TTL_DAYS"] ?? "30");

router.post("/refresh", async (req, res) => {
  const { refreshToken } = req.body as { refreshToken?: string };

  if (!refreshToken) {
    res.status(400).json({ error: "refreshToken is required" });
    return;
  }

  try {
    const now = new Date();

    const activeTokens = await db
      .select()
      .from(refreshTokensTable)
      .where(
        and(
          isNull(refreshTokensTable.revokedAt),
          gt(refreshTokensTable.expiresAt, now)
        )
      );

    let matchedToken = null;
    for (const t of activeTokens) {
      const match = await bcrypt.compare(refreshToken, t.tokenHash);
      if (match) {
        matchedToken = t;
        break;
      }
    }

    if (!matchedToken) {
      res.status(401).json({ error: "Unauthorized" });
      return;
    }

    const [license] = await db
      .select()
      .from(licensesTable)
      .where(eq(licensesTable.id, matchedToken.licenseId))
      .limit(1);

    if (!license || license.revokedAt || (license.expiresAt && license.expiresAt < now)) {
      await db
        .update(refreshTokensTable)
        .set({ revokedAt: now })
        .where(eq(refreshTokensTable.id, matchedToken.id));
      res.status(401).json({ error: "Unauthorized" });
      return;
    }

    const [device] = await db
      .select()
      .from(devicesTable)
      .where(eq(devicesTable.id, matchedToken.deviceId))
      .limit(1);

    await db
      .update(refreshTokensTable)
      .set({ revokedAt: now })
      .where(eq(refreshTokensTable.id, matchedToken.id));

    const newRawToken = uuidv4() + "-" + uuidv4();
    const newTokenHash = await bcrypt.hash(newRawToken, 10);
    const newExpiry = new Date();
    newExpiry.setDate(newExpiry.getDate() + REFRESH_TOKEN_TTL_DAYS);

    await db.insert(refreshTokensTable).values({
      licenseId: license.id,
      deviceId: matchedToken.deviceId,
      tokenHash: newTokenHash,
      expiresAt: newExpiry,
    });

    await db
      .update(devicesTable)
      .set({ lastSeen: now })
      .where(eq(devicesTable.id, matchedToken.deviceId));

    const entitlementTtl = parseInt(process.env["ENTITLEMENT_TTL_SECONDS"] ?? "86400");
    const entitlementJwt = signEntitlement({
      sub: license.providerId,
      appId: device?.appId ?? "unknown",
      features: license.features as string[],
      maxAccounts: license.maxAccounts,
      maxConcurrentCalls: license.maxConcurrentCalls,
    });

    res.json({
      entitlement: entitlementJwt,
      refreshToken: newRawToken,
      expiresIn: entitlementTtl,
    });
  } catch (err) {
    req.log.error({ err }, "Refresh error");
    res.status(500).json({ error: "Internal server error" });
  }
});

export default router;
