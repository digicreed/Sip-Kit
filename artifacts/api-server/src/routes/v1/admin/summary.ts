import { Router } from "express";
import { isNull } from "drizzle-orm";
import { db } from "@workspace/db";
import {
  providersTable,
  licensesTable,
  usageEventsTable,
} from "@workspace/db/schema";
import { requireAdminKey } from "../../../middlewares/admin-auth.js";

const router = Router();

router.get("/summary", requireAdminKey, async (req, res) => {
  try {
    const providers = await db.select({ id: providersTable.id }).from(providersTable);
    const licenses = await db.select().from(licensesTable);
    const events = await db.select().from(usageEventsTable);

    const activeLicenses = licenses.filter((l) => l.revokedAt === null).length;
    const revokedLicenses = licenses.filter((l) => l.revokedAt !== null).length;

    const totals = events.reduce(
      (acc, e) => ({
        callMinutes: acc.callMinutes + e.callMinutes,
        registrations: acc.registrations + e.registrations,
        callsPlaced: acc.callsPlaced + e.callsPlaced,
      }),
      { callMinutes: 0, registrations: 0, callsPlaced: 0 }
    );

    res.json({
      totalProviders: providers.length,
      totalLicenses: licenses.length,
      activeLicenses,
      revokedLicenses,
      totalCallMinutes: totals.callMinutes,
      totalRegistrations: totals.registrations,
      totalCallsPlaced: totals.callsPlaced,
    });
  } catch (err) {
    req.log.error({ err }, "Admin summary error");
    res.status(500).json({ error: "Internal server error" });
  }
});

export default router;
