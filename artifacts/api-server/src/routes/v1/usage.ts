import { Router } from "express";
import { eq } from "drizzle-orm";
import { db } from "@workspace/db";
import { devicesTable, usageEventsTable } from "@workspace/db/schema";
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

  try {
    const [device] = await db
      .select()
      .from(devicesTable)
      .where(eq(devicesTable.deviceId, deviceId))
      .limit(1);

    if (!device) {
      res.status(404).json({ error: "Device not found" });
      return;
    }

    await db.insert(usageEventsTable).values({
      licenseId: device.licenseId,
      deviceId: device.id,
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
