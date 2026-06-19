import { Router } from "express";
import bcrypt from "bcryptjs";
import { eq, and, gte, isNull } from "drizzle-orm";
import { db } from "@workspace/db";
import {
  licensesTable,
  devicesTable,
  usageEventsTable,
  refreshTokensTable,
} from "@workspace/db/schema";
import { requireAdminKey } from "../../../middlewares/admin-auth.js";

const router = Router();

const VALID_FEATURES = ["audio", "video", "conference", "transfer", "dtmf"];
const KEY_ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";

function generateLicenseKey(): string {
  const { randomBytes } = require("crypto") as typeof import("crypto");
  const bytes = randomBytes(32);
  let key = "pk_live_";
  for (const byte of bytes) {
    key += KEY_ALPHABET[byte % KEY_ALPHABET.length];
  }
  return key;
}

router.post("/providers/:providerId/licenses", requireAdminKey, async (req, res) => {
  const { providerId } = req.params;
  const {
    features = ["audio"],
    maxAccounts = 5,
    maxConcurrentCalls = 10,
    maxDevices = 10,
    expiresAt,
  } = req.body as {
    features?: string[];
    maxAccounts?: number;
    maxConcurrentCalls?: number;
    maxDevices?: number;
    expiresAt?: string;
  };

  if (!providerId) {
    res.status(400).json({ error: "providerId is required" });
    return;
  }

  const invalidFeatures = features.filter((f) => !VALID_FEATURES.includes(f));
  if (invalidFeatures.length > 0) {
    res.status(400).json({ error: `Invalid features: ${invalidFeatures.join(", ")}. Valid: ${VALID_FEATURES.join(", ")}` });
    return;
  }

  try {
    const plainKey = generateLicenseKey();
    const keyHash = await bcrypt.hash(plainKey, 12);

    const [license] = await db
      .insert(licensesTable)
      .values({
        providerId: providerId as string,
        keyHash,
        features: features as string[],
        maxAccounts,
        maxConcurrentCalls,
        maxDevices,
        expiresAt: expiresAt ? new Date(expiresAt) : null,
      })
      .returning();

    res.status(201).json({
      id: license!.id,
      providerId: license!.providerId,
      licenseKey: plainKey,
      features: license!.features,
      maxAccounts: license!.maxAccounts,
      maxConcurrentCalls: license!.maxConcurrentCalls,
      maxDevices: license!.maxDevices,
      expiresAt: license!.expiresAt,
      createdAt: license!.createdAt,
      _warning: "Store this licenseKey securely — it will not be shown again.",
    });
  } catch (err) {
    req.log.error({ err }, "Issue license error");
    res.status(500).json({ error: "Internal server error" });
  }
});

router.post("/licenses/:licenseId/revoke", requireAdminKey, async (req, res) => {
  const licenseId = req.params["licenseId"] as string;

  try {
    const now = new Date();

    const [updated] = await db
      .update(licensesTable)
      .set({ revokedAt: now })
      .where(and(eq(licensesTable.id, licenseId), isNull(licensesTable.revokedAt)))
      .returning();

    if (!updated) {
      res.status(404).json({ error: "License not found or already revoked" });
      return;
    }

    await db
      .update(refreshTokensTable)
      .set({ revokedAt: now })
      .where(and(eq(refreshTokensTable.licenseId, licenseId), isNull(refreshTokensTable.revokedAt)));

    res.json({ ok: true, revokedAt: now });
  } catch (err) {
    req.log.error({ err }, "Revoke license error");
    res.status(500).json({ error: "Internal server error" });
  }
});

router.get("/usage", requireAdminKey, async (req, res) => {
  const { providerId } = req.query as { providerId?: string };

  try {
    let licenseIds: string[] = [];

    if (providerId) {
      const licenses = await db
        .select({ id: licensesTable.id })
        .from(licensesTable)
        .where(eq(licensesTable.providerId, providerId));
      licenseIds = licenses.map((l) => l.id);

      if (licenseIds.length === 0) {
        res.json({ events: [], total: { callMinutes: 0, registrations: 0, callsPlaced: 0 } });
        return;
      }
    }

    const allLicenses = await db.select().from(licensesTable);
    const allDevices = await db.select().from(devicesTable);
    const allEvents = await db.select().from(usageEventsTable);

    const filteredEvents = providerId
      ? allEvents.filter((e) => licenseIds.includes(e.licenseId))
      : allEvents;

    const total = filteredEvents.reduce(
      (acc, e) => ({
        callMinutes: acc.callMinutes + e.callMinutes,
        registrations: acc.registrations + e.registrations,
        callsPlaced: acc.callsPlaced + e.callsPlaced,
      }),
      { callMinutes: 0, registrations: 0, callsPlaced: 0 }
    );

    res.json({ events: filteredEvents, total });
  } catch (err) {
    req.log.error({ err }, "Usage query error");
    res.status(500).json({ error: "Internal server error" });
  }
});

export default router;
