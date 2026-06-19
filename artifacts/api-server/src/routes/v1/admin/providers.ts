import { Router } from "express";
import { eq, inArray } from "drizzle-orm";
import { db } from "@workspace/db";
import {
  providersTable,
  licensesTable,
  devicesTable,
  refreshTokensTable,
  usageEventsTable,
} from "@workspace/db/schema";
import { requireAdminKey } from "../../../middlewares/admin-auth.js";

const router = Router();

router.get("/providers", requireAdminKey, async (req, res) => {
  try {
    const providers = await db.select().from(providersTable).orderBy(providersTable.createdAt);
    res.json(providers);
  } catch (err) {
    req.log.error({ err }, "List providers error");
    res.status(500).json({ error: "Internal server error" });
  }
});

router.post("/providers", requireAdminKey, async (req, res) => {
  const { name, contactEmail } = req.body as { name?: string; contactEmail?: string };

  if (!name || !contactEmail) {
    res.status(400).json({ error: "name and contactEmail are required" });
    return;
  }

  try {
    const [provider] = await db
      .insert(providersTable)
      .values({ name, contactEmail })
      .returning();

    res.status(201).json(provider);
  } catch (err) {
    req.log.error({ err }, "Create provider error");
    res.status(500).json({ error: "Internal server error" });
  }
});

router.delete("/providers/:providerId", requireAdminKey, async (req, res) => {
  const { providerId } = req.params;

  try {
    // Verify provider exists first
    const [provider] = await db
      .select({ id: providersTable.id })
      .from(providersTable)
      .where(eq(providersTable.id, providerId as string));

    if (!provider) {
      res.status(404).json({ error: "Provider not found" });
      return;
    }

    // Collect all license IDs for this provider
    const licenses = await db
      .select({ id: licensesTable.id })
      .from(licensesTable)
      .where(eq(licensesTable.providerId, providerId as string));

    const licenseIds = licenses.map((l) => l.id);

    if (licenseIds.length > 0) {
      // Collect device IDs under those licenses
      const devices = await db
        .select({ id: devicesTable.id })
        .from(devicesTable)
        .where(inArray(devicesTable.licenseId, licenseIds));

      const deviceIds = devices.map((d) => d.id);

      if (deviceIds.length > 0) {
        // Delete usage events (refs licenseId + deviceId)
        await db
          .delete(usageEventsTable)
          .where(inArray(usageEventsTable.deviceId, deviceIds));

        // Delete refresh tokens (refs licenseId + deviceId)
        await db
          .delete(refreshTokensTable)
          .where(inArray(refreshTokensTable.deviceId, deviceIds));

        // Delete devices
        await db
          .delete(devicesTable)
          .where(inArray(devicesTable.id, deviceIds));
      }

      // Delete licenses
      await db
        .delete(licensesTable)
        .where(inArray(licensesTable.id, licenseIds));
    }

    // Delete the provider
    await db
      .delete(providersTable)
      .where(eq(providersTable.id, providerId as string));

    res.json({ ok: true });
  } catch (err) {
    req.log.error({ err }, "Delete provider error");
    res.status(500).json({ error: "Internal server error" });
  }
});

export default router;
