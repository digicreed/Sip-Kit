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
