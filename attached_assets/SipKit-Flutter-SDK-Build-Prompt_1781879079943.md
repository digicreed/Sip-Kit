# Build Prompt — "SipKit": Token-Licensed Flutter SIP SDK for VoIP Providers

> A B2B SDK I sell/provide to VoIP providers. They embed it in **their** softphone and unlock it with an **access token I issue**. Flutter first. "SipKit" is a placeholder name — rename freely.

---

## 0. Toolchain split (important — read first)

This build has three components. Route them correctly:

| Component | Where it builds/runs |
|---|---|
| **A. Flutter SDK package** (`sipkit_flutter`) | Replit/agent **scaffolds + writes all Dart code**. Compile/run on a real Flutter toolchain (local machine, or Codemagic/GitHub Actions). Replit cannot run a Flutter app. |
| **B. Licensing backend** (`sipkit-license-server`, NestJS) | Replit builds **and runs** this fully. Node.js + Postgres. |
| **C. Demo softphone** (`example_softphone`, Flutter) | Scaffolded by agent; compile/run on Flutter toolchain. |

So: do all of B end-to-end (runnable now). For A and C, generate complete, correct Dart code and a README with exact `flutter run` / build steps — don't try to execute Flutter.

---

## 1. Product model (one-liner)

A reusable Flutter SIP/VoIP SDK (like Siprix) that adds voice + video calling to a provider's app. Usage is **gated by an access token I issue**: the SDK refuses to register or place calls until it validates a token against my licensing backend. The backend lets me issue, scope, expire, and revoke provider access, and (optionally) meter usage for billing.

---

## 2. The token flow (the heart of this — implement exactly)

Two token tiers. Keep them distinct.

1. **Provider License Key** — long-lived secret string I issue to a VoIP provider (e.g. `pk_live_XXXX`). Identifies + entitles the provider.
2. **Entitlement Token** — short-lived **signed JWT** the backend returns when the SDK activates. This is what the SDK enforces at runtime (features, limits, expiry). Refreshed before expiry.

```
[Admin: me] --issues--> Provider License Key  (stored hashed server-side)
        |
        v
VoIP provider embeds SDK, calls:  SipKitClient.activate(licenseKey, baseUrl)
        |
        v   POST /v1/activate { licenseKey, appId, deviceId }
[License server]  validates key (not revoked, not expired, seat available)
        |
        v   returns: { entitlement: <signed JWT>, refreshToken, expiresIn }
[SDK]  verifies JWT signature offline (bundled public key),
       caches entitlement (offline grace window), UNLOCKS the API
        |
        v   before exp:  POST /v1/refresh { refreshToken } -> new entitlement
        v   (optional)   POST /v1/usage   { callMinutes, registrations, ... }
```

**SIP credentials are separate** from licensing. The provider supplies their own SIP username/password/domain/WSS URL when adding an account. (If I later act as the SIP carrier myself, the entitlement JWT can additionally carry SIP auth — design the account config so a token-supplied credential can be slotted in without API changes.)

Entitlement JWT claims (RS256, signed by server private key; SDK ships the public key):
```json
{
  "iss": "sipkit-license",
  "sub": "<providerId>",
  "appId": "<provider app id>",
  "features": ["audio","video","conference","transfer","dtmf"],
  "maxAccounts": 5,
  "maxConcurrentCalls": 50,
  "iat": 0,
  "exp": 0,
  "jti": "<token id>"
}
```
- **Offline grace:** SDK caches the last valid entitlement and keeps working until `exp + graceWindow` (e.g. 72h) if the network is down, then locks.
- **Feature gating:** if `features` lacks `video`, `enableVideo()` throws a clear "not entitled" error. If active accounts exceed `maxAccounts`, `addAccount()` throws.

---

## 3. Component A — Flutter SDK package (`sipkit_flutter`)

### 3.1 Design principles
- **Engine behind an adapter seam.** Phase 1 engine = `sip_ua` (dart-sip-ua) + `flutter_webrtc` (SIP over secure WebSocket + WebRTC media; works across Flutter targets, no native C). The public API must **not leak `sip_ua` types** — define a `SipEngine` abstract class that the web/WSS engine implements, so a future native **PJSIP** engine (background calls, CallKit/ConnectionService) swaps in without breaking provider code.
- **Idiomatic Dart:** expose state via `Stream`s and `ValueListenable`, not JS-style `.on()` emitters.
- **Token gating is mandatory:** no registration or call method works until `activate()` succeeds.

### 3.2 Package structure
```
sipkit_flutter/
├─ pubspec.yaml                 # deps: sip_ua, flutter_webrtc, http, jose/jwt verify, equatable
├─ lib/
│  ├─ sipkit_flutter.dart       # public exports only
│  └─ src/
│     ├─ client/
│     │  ├─ sipkit_client.dart   # top-level manager (activation + accounts + calls)
│     │  ├─ sipkit_account.dart
│     │  └─ sipkit_call.dart
│     ├─ licensing/
│     │  ├─ activation.dart      # calls /v1/activate + /v1/refresh
│     │  ├─ entitlement.dart     # JWT verify (public key), feature checks
│     │  └─ entitlement_cache.dart # offline grace persistence (shared_prefs/secure storage)
│     ├─ engine/
│     │  ├─ sip_engine.dart       # ABSTRACT interface (the seam)
│     │  └─ webrtc_engine.dart    # impl with sip_ua + flutter_webrtc
│     ├─ models/                  # configs, enums, event payloads (no engine types)
│     └─ errors.dart              # SipKitError, NotEntitledError, ActivationError
├─ example/                       # -> Component C lives here or as sibling
└─ test/                          # unit tests for entitlement + state machines
```

### 3.3 Public API (build to this)
```dart
// 1. Activation (gates everything)
final client = SipKitClient();
final activation = await client.activate(
  licenseKey: 'pk_live_xxx',
  baseUrl: 'https://license.mydomain.com',
  appId: 'com.provider.softphone',
); // throws ActivationError on invalid/expired/revoked

client.entitlement;            // current Entitlement (features, limits, exp)
client.activationState;        // Stream<ActivationState> { unactivated, activating, active, expired, locked }

// 2. Accounts (provider supplies their SIP creds)
final account = await client.addAccount(SipKitAccountConfig(
  username: 'alice', password: 'secret', domain: 'pbx.provider.com',
  wsUrl: 'wss://pbx.provider.com:8089/ws',
  displayName: 'Alice', iceServers: const [...], registerOnAdd: true,
)); // throws NotEntitledError if over maxAccounts
account.status;                // Stream<AccountStatus> { unregistered, registering, registered, failed }
await account.register(); await account.unregister();
client.accounts;              // List<SipKitAccount>

// 3. Calls
final call = await client.makeCall(account.id, 'sip:bob@pbx.provider.com', video: false);
client.calls;                 // List<SipKitCall>  (multiple concurrent)
client.incomingCalls;         // Stream<SipKitCall>

call.state;                   // Stream<CallState> { connecting, ringing, earlyMedia, established, held, terminated }
await call.answer(video: false);
await call.hangup();
await call.hold(); await call.unhold();
call.mute(true);
call.sendDtmf('123#');
await call.blindTransfer('sip:carol@pbx.provider.com');
await call.attendedTransfer(otherCall);
await call.enableVideo(true);  // throws NotEntitledError if 'video' not in features
call.localRenderer;            // RTCVideoRenderer (flutter_webrtc) for UI
call.remoteRenderer;           // RTCVideoRenderer

// 4. Conference (multi-call)
final conf = await client.mergeCalls([callA.id, callB.id]); // throws if 'conference' not entitled

await client.dispose();
```

### 3.4 Engine seam (`sip_engine.dart`)
Abstract methods: `init`, `registerAccount`, `unregister`, `makeCall`, `answer`, `hangup`, `hold`, `mute`, `sendDtmf`, `transfer`, `enableVideo`, `dispose`, plus broadcast `Stream`s for `incomingCall`, `callStateChanged`, `accountStatusChanged`, `localStream`, `remoteStream`. `WebrtcEngine` implements it with `sip_ua` (`SIPUAHelper`, `Call`, `RegistrationState`, `CallState`). Add a header comment in `sip_engine.dart` describing how a future `PjsipEngine` (FFI/native) implements the same contract.

---

## 4. Component B — Licensing backend (`sipkit-license-server`, NestJS + Postgres)

Runs fully on Replit. This is what makes the SDK sellable + controllable.

### 4.1 Stack
NestJS, TypeScript, PostgreSQL (TypeORM or Prisma), RS256 JWT (keypair generated on first run, private key in env/secret, public key exported for the SDK), bcrypt for hashing license keys, rate limiting on `/v1/activate`.

### 4.2 Endpoints
**SDK-facing (public, rate-limited):**
- `POST /v1/activate` — body `{ licenseKey, appId, deviceId }` → validate (exists, not revoked, not expired, seat/device limit), create device record, return `{ entitlement: <RS256 JWT>, refreshToken, expiresIn }`. Generic 401 on any failure (don't leak which check failed).
- `POST /v1/refresh` — body `{ refreshToken }` → re-check revocation/expiry, return fresh entitlement.
- `POST /v1/usage` — body `{ deviceId, callMinutes, registrations, callsPlaced }` → append usage event (for metering/billing). Auth via refresh/entitlement token.
- `GET /v1/jwks` or `GET /v1/public-key` — serve the public key so SDK builds can fetch/pin it.

**Admin-facing (protected by admin API key / separate auth):**
- `POST /v1/admin/providers` → create a provider (name, contact).
- `POST /v1/admin/providers/:id/licenses` → issue a license key: body `{ features[], maxAccounts, maxConcurrentCalls, maxDevices, expiresAt }` → returns the **plaintext key once** (store only its hash).
- `POST /v1/admin/licenses/:id/revoke` → revoke.
- `GET /v1/admin/usage?providerId=` → usage report.

### 4.3 Data model (Postgres)
- `providers(id, name, contact_email, created_at)`
- `licenses(id, provider_id, key_hash, features jsonb, max_accounts, max_concurrent_calls, max_devices, expires_at, revoked_at, created_at)`
- `devices(id, license_id, device_id, app_id, first_seen, last_seen)`
- `refresh_tokens(id, license_id, device_id, token_hash, expires_at, revoked_at)`
- `usage_events(id, license_id, device_id, call_minutes, registrations, calls_placed, created_at)`

### 4.4 Security requirements
License keys stored **hashed only**; plaintext shown once at issuance. Entitlement JWTs short-lived (e.g. 24h) + signed RS256. Refresh tokens hashed, rotated on use, revocable. `/v1/activate` rate-limited per IP + per license key. Revocation checked on every `/v1/refresh`. CORS locked down.

### 4.5 Seed + admin
Provide a seed script that creates one demo provider + one demo license key (printed to console) so the demo softphone can activate immediately. Add a minimal admin endpoint test or a short curl script in the README.

---

## 5. Component C — Demo softphone (`example_softphone`, Flutter)

A working softphone that proves the whole flow:
1. **Activation screen:** enter license key + backend URL → `client.activate(...)`. Show entitlement (features, limits, expiry). Invalid key → clear locked state, SDK unusable.
2. **Account setup:** WSS URL, domain, username, password, display name → register. Live status badge. Support **2+ accounts** (multi-account proof).
3. **Dialer:** SIP target input, Audio + Video call buttons (Video disabled/greyed if not entitled).
4. **Active calls panel:** per-call card — remote party, state, Answer/Hangup/Hold/Mute/DTMF keypad/Transfer.
5. **Incoming call** modal: Answer / Reject.
6. **Conference:** "Merge" button when 2+ calls active (disabled if not entitled).
7. **Video tiles:** local + remote `RTCVideoView`.
8. **Event log panel:** prints SDK events (activated, registered, ringing, established, terminated).

Persist activation + account fields in secure storage (demo convenience). README must include exact steps: set backend URL, run seed to get a license key, `flutter run`, register two extensions, call between them.

---

## 6. Testing notes
- Backend: unit/e2e tests for activate → entitlement → refresh → revoke (revoked key must fail refresh).
- SDK: Dart unit tests for entitlement JWT verification (valid/expired/wrong-signature), feature gating (NotEntitledError paths), and account/call state machines — these need no network.
- SIP testing: README documents enabling **Asterisk/FreePBX WebSocket transport** (`chan_pjsip`, `transport-wss`, `wss://host:8089/ws`) and creating two test extensions; note a public SIP-over-WebSocket provider as a fallback.

---

## 7. Out of scope now — design seams, document in README "Roadmap"
- **Native PJSIP engine** (`PjsipEngine` via FFI/platform channels) for real background calls, TLS/UDP/TCP transports, CallKit (iOS) + ConnectionService (Android). This is the true Siprix-parity path.
- **Push wake-up** (FCM/PushKit) so calls ring when the app is backgrounded.
- **Token-carried SIP auth** (when I'm the carrier): entitlement JWT supplies SIP credentials.
- Call recording, provisioning/top-up/balance, web + Windows/macOS/Linux engine hardening.

---

## 8. Deliverables / acceptance criteria
1. **Backend runs on Replit**, issues a license key via admin endpoint, validates it via `/v1/activate`, returns a signed entitlement, refreshes it, and revocation blocks refresh.
2. **SDK package** compiles on a Flutter toolchain; `activate()` gates the API — invalid/expired/revoked key leaves the SDK locked; valid key unlocks registration + calls; feature flags enforce `video`/`conference`.
3. **Public API matches Section 3.3**; no `sip_ua` types leak through it; engine sits behind `SipEngine`.
4. **Demo softphone** activates with a token, registers **two** accounts, places audio + video calls, holds/mutes/DTMF/blind-transfer, and merges two calls into a conference — all visible in the UI, all gated by entitlement.
5. **README** covers: architecture, the two-token flow, how I issue/revoke licenses, how a provider integrates the SDK (10-line quickstart), Asterisk WSS test setup, and the native-PJSIP roadmap.

Build Component B fully and runnably. Generate complete Dart code for A and C with exact local build/run instructions. Ask me before changing the public API in Section 3.3 or the token flow in Section 2.
