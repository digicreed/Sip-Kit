# SipKit — Roadmap

## Current state (v0.1)

| Feature | Status |
|---|---|
| Licensing backend (Express + Postgres, RS256 JWT) | ✅ Complete |
| WebrtcEngine (`sip_ua` + `flutter_webrtc`) | ✅ Complete |
| PjsipEngine Dart side (platform channels) | ✅ Complete |
| PjsipEngine iOS native (Swift + CallKit) | ✅ Stub complete (needs PJSIP pod) |
| PjsipEngine Android native (Kotlin + ConnectionService) | ✅ Stub complete (needs PJSIP AAR) |
| Feature gating (video, conference, maxAccounts, maxCalls) | ✅ Complete |
| Offline grace window (72h, flutter_secure_storage) | ✅ Complete |
| Auto-refresh (5 min before JWT expiry) | ✅ Complete |
| Demo softphone (7 screens, engine toggle) | ✅ Complete |
| APNs VoIP push + FCM cold-start wakeup | ✅ Complete (credentials required) |

---

## v0.2 — APNs / FCM push wakeup (complete)

### What was implemented

- **`POST /api/v1/push-token`** — stores one APNs or FCM token per activated
  device (upserts on re-registration).  Protected by the entitlement JWT.

- **`artifacts/api-server/src/lib/push-worker.ts`** — server-side fan-out:
  - `sendApnsPush()` — HTTP/2 request to `api.push.apple.com` using token-based
    auth (.p8 key), `apns-push-type: voip`, `apns-priority: 10`.
  - `sendFcmPush()` — FCM HTTP v1 API using a Google service-account JWT.
  - `fanOutCallPush()` — fetches all tokens for a device and dispatches in parallel.

- **iOS `SipKitPlugin.swift`** — full `PKPushRegistryDelegate` implementation:
  - `setupVoipPushRegistry()` creates a live `PKPushRegistry` on init.
  - `pushRegistry(_:didUpdate:for:)` emits a `voipPushToken` event to Flutter
    so the SDK can POST the token to `/api/v1/push-token`.
  - `pushRegistry(_:didReceiveIncomingPushWith:completion:)` calls
    `CXProvider.reportNewIncomingCall` synchronously within the ~2s deadline,
    then emits `incomingCall` to Flutter.

- **Android `SipKitFirebaseMessagingService.kt`** — `FirebaseMessagingService`:
  - `onNewToken` emits a `voipPushToken` event via `SipKitEventBus`.
  - `onMessageReceived` calls `TelecomManager.addNewIncomingCall`, starts
    `SipKitForegroundService`, and emits `incomingCall`.

- **`SipKitEventBus.kt`** — process-level singleton that queues events emitted
  by background services before the Flutter engine attaches, then replays them.

- **`AndroidManifest.xml`** — declares `SipKitFirebaseMessagingService` with
  `com.google.firebase.MESSAGING_EVENT` intent-filter.

See `example_softphone/README.md` → **Step 6** for credential setup.

---

## Planned — v0.3

---

### macOS `PjsipEngine`

PJSIP builds on macOS via Homebrew (`brew install pjproject`).  The Flutter
macOS plugin architecture (`macos/Classes/`) mirrors the iOS structure.
CallKit equivalent on macOS is `CXCallObserver` (read-only); there is no
CXProvider API for macOS.  Native call screen integration is not possible on
macOS — foreground calling via WebrtcEngine remains the primary path.

---

### Windows / Linux `PjsipEngine`

PJSIP provides native Windows and Linux builds.  Integration via FFI
(`dart:ffi`) directly from Dart is feasible without a platform channel,
using a thin C wrapper around pjsua2.  This would enable background calling
on desktop without any OS call-management UI.

---

### Token-carried SIP credentials

When the SipKit operator acts as the SIP carrier, the entitlement JWT can
carry SIP credentials (username, domain, WSS URL) rather than requiring the
provider to supply them.  The `SipKitAccountConfig` is already shaped to
accept these fields from the token — no public API change needed.

Add to JWT claims:
```json
{
  "sipConfig": {
    "username": "alice_auto",
    "password": "...",
    "domain":   "carrier.sipkit.io",
    "wsUrl":    "wss://carrier.sipkit.io:8089/ws"
  }
}
```

---

### Usage metering + billing dashboard

- Periodic `POST /api/v1/usage` calls from the SDK (currently implemented but
  not yet called automatically).
- Admin dashboard (web UI) to view per-provider usage, export CSV, and set
  billing thresholds.
- Webhook support: `POST` to provider's endpoint when metered thresholds are hit.

---

### Additional hardening

- Call recording (server-side via Asterisk `MixMonitor` or SIPREC).
- Provisioning API: operators top up device seats or extend expiry via a
  self-service portal.
- SRTP / ZRTP media encryption enforcement in WebrtcEngine.
- Web (Flutter Web) DTLS-SRTP hardening.
