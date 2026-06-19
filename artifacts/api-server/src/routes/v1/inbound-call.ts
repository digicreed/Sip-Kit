import { Router } from "express";
import { eq, and, isNull } from "drizzle-orm";
import { db } from "@workspace/db";
import { devicesTable, licensesTable } from "@workspace/db/schema";
import { requireAdminKey } from "../../middlewares/admin-auth.js";
import { fanOutCallPush } from "../../lib/push-worker.js";

const router = Router();

/**
 * POST /api/v1/inbound-call
 *
 * Called by the SIP proxy, Asterisk AGI/AMI, or any server-side component
 * that detects an inbound call for a registered device.  The endpoint fans
 * out an APNs VoIP push (iOS) and/or an FCM data message (Android) so the
 * device wakes from a fully-terminated state and reports the call to CallKit
 * / TelecomManager before the SIP dialog is answered.
 *
 * Authentication: ADMIN_API_KEY (Bearer token)
 *
 * Body:
 *   deviceId    – app-level device identifier (same as used at activation)
 *   appId       – application identifier
 *   callId      – unique identifier for this call leg (e.g. SIP Call-ID)
 *   remoteUri   – SIP URI of the caller  (e.g. "sip:alice@example.com")
 *   displayName – human-readable caller name shown on the lock screen
 *   accountId   – (optional) SipKit account the call arrived on
 *
 * Response:
 *   { ok: true }  — push dispatch queued (per-token errors are logged server-side)
 *   or 404 if the device is not found / license is revoked
 *
 * Typical Asterisk AGI integration:
 *   curl -s -X POST https://your-backend/api/v1/inbound-call \
 *     -H "Authorization: Bearer $ADMIN_API_KEY" \
 *     -H "Content-Type: application/json" \
 *     -d '{"deviceId":"...", "appId":"...", "callId":"${UNIQUEID}",
 *          "remoteUri":"sip:${CALLERID(num)}@${SIPDOMAIN}",
 *          "displayName":"${CALLERID(name)}"}'
 */
router.post("/inbound-call", requireAdminKey, async (req, res) => {
  const { deviceId, appId, callId, remoteUri, displayName, accountId } =
    req.body as {
      deviceId?: string;
      appId?: string;
      callId?: string;
      remoteUri?: string;
      displayName?: string;
      accountId?: string;
    };

  if (!deviceId || !appId || !callId || !remoteUri) {
    res
      .status(400)
      .json({ error: "deviceId, appId, callId, and remoteUri are required" });
    return;
  }

  try {
    const [row] = await db
      .select({ deviceDbId: devicesTable.id })
      .from(devicesTable)
      .innerJoin(
        licensesTable,
        and(
          eq(licensesTable.id, devicesTable.licenseId),
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
      res.status(404).json({ error: "Device not found or license revoked" });
      return;
    }

    await fanOutCallPush(row.deviceDbId, {
      callId,
      remoteUri,
      displayName: displayName ?? remoteUri,
      accountId,
    });

    res.json({ ok: true });
  } catch (err) {
    req.log.error({ err }, "Inbound-call push error");
    res.status(500).json({ error: "Internal server error" });
  }
});

export default router;
