import { Router } from "express";
import { eq, and, isNull } from "drizzle-orm";
import { db } from "@workspace/db";
import { devicesTable, licensesTable, usageEventsTable } from "@workspace/db/schema";
import { requireEntitlement } from "../../middlewares/entitlement-auth.js";

const router = Router();

router.post("/usage", requireEntitlement, async (req, res) => {
  const { deviceId, callMinutes, registrations, callsPlaced } = req.body as {
    deviceId?: string;
    callMinutes?: number;
    registrations?: number;
    callsPlaced?: number;
  };

  if (!deviceId) {
    res.status(400).json({ error: "deviceId is required" });
    return;
  }

  const { sub: providerId, appId } = req.entitlement!;

  try {
    // Single-query ownership check: device must exist, match the JWT's appId,
    // and belong to a non-revoked license owned by the JWT's provider.
    const [row] = await db
      .select({ deviceDbId: devicesTable.id, licenseId: devicesTable.licenseId })
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

    await db.insert(usageEventsTable).values({
      licenseId: row.licenseId,
      deviceId: row.deviceDbId,
      callMinutes: callMinutes ?? 0,
      registrations: registrations ?? 0,
      callsPlaced: callsPlaced ?? 0,
    });

    res.json({ ok: true });
  } catch (err) {
    req.log.error({ err }, "Usage error");
    res.status(500).json({ error: "Internal server error" });
  }
});

export default router;
