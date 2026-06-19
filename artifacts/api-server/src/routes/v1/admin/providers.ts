import { Router } from "express";
import { db } from "@workspace/db";
import { providersTable } from "@workspace/db/schema";
import { requireAdminKey } from "../../../middlewares/admin-auth.js";

const router = Router();

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

export default router;
