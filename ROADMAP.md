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

---

## Planned — v0.2

### APNs / FCM push wakeup for cold-start background calls

Currently `PjsipEngine` keeps a VoIP socket alive while the app is in the
background via an iOS background VoIP socket (`UIBackgroundModes: voip`) and
an Android foreground service.  This does **not** wake the app when it is
fully closed (cold start).

True cold-start wakeup requires:

- **iOS (PushKit / APNs VoIP push):** Server sends a VoIP push notification
  via APNs when a call arrives.  iOS wakes the app and calls
  `PKPushRegistryDelegate.pushRegistry(_:didReceiveIncomingPushWith:)`.
  The app must report the call to CallKit within ~2s or iOS kills it.
  The `SipKitPlugin.swift` already stubs `PKPushRegistry` setup.

- **Android (FCM):** Server sends a data-only FCM message.  A `FirebaseMessagingService`
  starts the PJSIP engine and reports the call to `TelecomManager`.

**Design seam:** The licensing backend is the natural place to relay push
tokens (stored per device) and fan out notifications.  A
`POST /api/v1/push-token { deviceId, platform, token }` endpoint, plus a
worker that calls APNs / FCM when PJSIP reports an inbound call.

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
