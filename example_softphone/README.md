# SipKit Example Softphone

A demo Flutter softphone that proves the full SipKit flow:

```
Activate → Register accounts → Place/receive calls →
Hold / Mute / DTMF / Transfer → Conference → Video
```

---

## Prerequisites

1. **SipKit licensing backend** running (see `artifacts/api-server/README.md`).
2. **Flutter 3.10+** installed locally (Replit cannot compile Flutter).
3. A SIP server (Asterisk, FreePBX, or the public sip2sip.info fallback).

---

## Step 1 — Start the licensing backend and get a license key

```bash
# In the Replit workspace or locally:
cd artifacts/api-server
pnpm dev

# Seed a demo provider + license key:
pnpm tsx scripts/seed.ts
# Output: pk_live_XXXXXXXXXXXXXXXX   ← copy this
```

The backend runs at `http://localhost:8080` locally or your Replit dev URL.

---

## Step 2 — Configure the softphone

Open the app's **Activation screen** and enter:

| Field | Value |
|---|---|
| Backend URL | `https://your-replit-dev.repl.co` (or `http://localhost:8080`) |
| License Key | `pk_live_XXXXXXXXXXXXXXXX` (from Step 1) |

Tap **Activate**.  The app shows your entitlement details (features, limits, expiry).

---

## Step 3 — Register SIP extensions

Go to the **Accounts** tab.  Add two accounts:

**Extension 6001:**
| Field | Value |
|---|---|
| Username | `6001` |
| Password | `test1234` |
| Domain | `your-pbx-host.com` |
| WSS URL | `wss://your-pbx-host.com:8089/ws` |

**Extension 6002:** (same domain, username `6002`, password `test5678`)

Both should show **REGISTERED** within a few seconds.

**Public fallback (no own PBX):**  Use `sip2sip.info` — register a free account at https://mdns.sip2sip.info/ and use `wss://sip2sip.info:5061` as the WSS URL.

---

## Step 4 — Run the app

```bash
cd example_softphone

# iOS (needs Xcode + iOS device or simulator):
flutter run -d ios

# Android:
flutter run -d android

# macOS desktop (WebrtcEngine only):
flutter run -d macos
```

---

## Step 5 — Test calling features

1. **Audio call:** Dialer tab → select account 6001 → type `sip:6002@your-pbx.com` → **Audio Call**.
2. **Video call:** Same flow → **Video Call** (must have `video` in entitlement features).
3. **Hold:** Active Calls tab → **Hold** / **Resume**.
4. **Mute:** Active Calls tab → **Mute** / **Unmute**.
5. **DTMF:** Active Calls tab → **DTMF** → press digits.
6. **Blind transfer:** Active Calls tab → **Transfer** → enter target URI.
7. **Conference:** Place two calls → the **Conference** FAB appears in the bottom right → tap to merge.
8. **Incoming call:** From extension 6002 call 6001 → the incoming call overlay appears.

---

## Engine toggle

Tap the engine icon (top-right of any screen) to switch between:

- **WebrtcEngine** — `sip_ua` + `flutter_webrtc`; foreground only; works on all platforms.
- **PjsipEngine** — PJSUA2 + CallKit (iOS) / ConnectionService (Android); background calling.

Switching engine disconnects all accounts and resets activation state.

---

## Step 6 — APNs VoIP push + FCM cold-start wakeup (optional)

When the app is **fully terminated**, the background socket maintained by
PjsipEngine cannot receive calls.  APNs (iOS) and FCM (Android) wake the
process and ring the native call screen before the SIP dialog is answered.

### iOS — APNs VoIP push

**1. Apple Developer portal**

- Enable the **Push Notifications** capability on your App ID.
- Under *Keys*, create an **APNs Auth Key** (`.p8`) and download it once.
- Note the **Key ID** (10 chars) and your **Team ID**.

**2. Info.plist — verify background modes**

```xml
<key>UIBackgroundModes</key>
<array>
  <string>voip</string>
</array>
```

**3. Entitlements**

```xml
<key>com.apple.developer.networking.voip</key>
<true/>
<key>aps-environment</key>
<string>development</string>   <!-- or "production" for release -->
```

**4. Licensing backend environment variables**

Set these secrets in your deployment (or `.env` locally):

| Variable | Value |
|---|---|
| `APNS_KEY_ID` | 10-char key ID from Apple portal |
| `APNS_TEAM_ID` | 10-char Apple Team ID |
| `APNS_PRIVATE_KEY` | Full contents of the `.p8` file (newlines as `\n`) |
| `APNS_BUNDLE_ID` | Your app bundle ID, e.g. `com.example.softphone` |
| `APNS_PRODUCTION` | `true` for App Store builds; omit for sandbox |

**5. Token flow**

When `PjsipEngine` is initialised, `SipKitPlugin` creates a `PKPushRegistry`.
iOS calls `pushRegistry(_:didUpdate:for:)` with a device token.  The SDK emits
a `voipPushToken` event; your app should POST it to the backend:

```dart
sipKit.events.where((e) => e['type'] == 'voipPushToken').listen((e) {
  sipKit.httpClient.post('/api/v1/push-token', body: {
    'deviceId': myDeviceId,
    'platform': e['platform'],   // "apns"
    'token':    e['token'],
  });
});
```

---

### Android — FCM data messages

**1. Firebase project setup**

- Create a project at [console.firebase.google.com](https://console.firebase.google.com).
- Register your Android app and download `google-services.json` into `android/app/`.
- In *Project Settings → Service accounts* generate a new private key (JSON).

**2. `android/build.gradle`** — add at the bottom of the `plugins` block:

```groovy
id "com.google.gms.google-services" version "4.4.2" apply false
```

**3. `android/app/build.gradle`** — add the plugin and dependency:

```groovy
plugins {
  id "com.google.gms.google-services"
}
dependencies {
  implementation "com.google.firebase:firebase-messaging:24.1.1"
}
```

**4. Licensing backend environment variables**

| Variable | Value |
|---|---|
| `FCM_PROJECT_ID` | Firebase project ID (from Project Settings) |
| `FCM_SERVICE_ACCOUNT_JSON` | Full service-account JSON string (from the downloaded key file) |

**5. Token flow**

`SipKitFirebaseMessagingService.onNewToken` emits a `voipPushToken` event (same
shape as iOS) which your app POSTs to `/api/v1/push-token` with `platform: "fcm"`.

---

### Server — fan out a push when a call arrives

Call `fanOutCallPush` from your PJSIP inbound-call webhook or SIP proxy event:

```typescript
import { fanOutCallPush } from "./lib/push-worker.js";

await fanOutCallPush(deviceDbId, {
  callId:      "call_abc123",
  remoteUri:   "sip:alice@example.com",
  displayName: "Alice",
  accountId:   "acc_xyz",
});
```

The worker reads all stored tokens for the device and dispatches APNs / FCM in
parallel.  Missing credentials are a no-op warning — the live SIP socket
remains the primary delivery path.

---

## Asterisk WebSocket transport setup

In `pjsip.conf`:

```ini
[transport-wss]
type=transport
protocol=wss
bind=0.0.0.0:8089
cert_file=/etc/asterisk/keys/asterisk.crt
priv_key_file=/etc/asterisk/keys/asterisk.key

[6001]
type=endpoint
transport=transport-wss
context=default
aors=6001
auth=6001-auth
allow=ulaw,alaw,g722,opus,vp8,h264

[6001-auth]
type=auth
auth_type=userpass
username=6001
password=test1234

[6001]
type=aor
max_contacts=5
```

Restart Asterisk after changes:
```bash
asterisk -rx "core reload"
```

---

## Directory structure

```
example_softphone/
├─ lib/
│  ├─ main.dart                    # App + ChangeNotifierProvider
│  ├─ softphone_state.dart         # Central state (SipKitClient wrapper)
│  └─ screens/
│     ├─ activation_screen.dart    # Screen 1: license key entry
│     ├─ home_screen.dart          # Tab host + incoming call overlay trigger
│     ├─ account_setup_screen.dart # Screen 2: add/remove SIP accounts
│     ├─ dialer_screen.dart        # Screen 3: DTMF keypad + call buttons
│     ├─ active_calls_screen.dart  # Screen 4: per-call cards + video tiles
│     ├─ event_log_screen.dart     # Screen 7: real-time SDK event feed
│     └─ incoming_call_overlay.dart# Screen 5: answer/reject modal
└─ pubspec.yaml
```
