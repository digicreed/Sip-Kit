import { Router } from "express";
import { eq, and, isNull } from "drizzle-orm";
import { db } from "@workspace/db";
import { devicesTable, licensesTable, pushTokensTable } from "@workspace/db/schema";
import { requireEntitlement } from "../../middlewares/entitlement-auth.js";

const router = Router();

/**
 * POST /api/v1/push-token
 *
 * Registers or refreshes a device push token (APNs VoIP or FCM data).
 * The device must already be activated under the requesting provider's license.
 *
 * Body:
 *   deviceId  – the app-level device identifier used at activation time
 *   platform  – "apns" | "fcm"
 *   token     – the push token string returned by the OS
 *
 * One token is stored per device; submitting a new token replaces the old one.
 */
router.post("/push-token", requireEntitlement, async (req, res) => {
  const { deviceId, platform, token } = req.body as {
    deviceId?: string;
    platform?: string;
    token?: string;
  };

  if (!deviceId || !platform || !token) {
    res.status(400).json({ error: "deviceId, platform, and token are required" });
    return;
  }

  if (platform !== "apns" && platform !== "fcm") {
    res.status(400).json({ error: "platform must be 'apns' or 'fcm'" });
    return;
  }

  const { sub: providerId, appId } = req.entitlement!;

  try {
    const [row] = await db
      .select({ deviceDbId: devicesTable.id })
      .from(devicesTable)
      .innerJoin(
        licensesTable,
        and(
          eq(licensesTable.id, devicesTable.licenseId),
          eq(licensesTable.providerId, providerId),
          isNull(licensesTable.revokedAt),
        ),
      )
      .where(
        and(
          eq(devicesTable.deviceId, deviceId),
          eq(devicesTable.appId, appId),
        ),
      )
      .limit(1);

    if (!row) {
      res.status(403).json({ error: "Forbidden" });
      return;
    }

    await db
      .insert(pushTokensTable)
      .values({
        deviceId: row.deviceDbId,
        platform,
        token,
        updatedAt: new Date(),
      })
      .onConflictDoUpdate({
        target: pushTokensTable.deviceId,
        set: { platform, token, updatedAt: new Date() },
      });

    res.json({ ok: true });
  } catch (err) {
    req.log.error({ err }, "Push-token error");
    res.status(500).json({ error: "Internal server error" });
  }
});

export default router;
