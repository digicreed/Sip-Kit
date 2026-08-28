# SipKit Flutter SDK

A GPLv2-or-later Flutter SIP/VoIP SDK with token-gated service entitlements.
Add voice + video calling to your app, unlocked in unmodified builds by a
short-lived entitlement JWT issued by the SipKit licensing backend.

---

## Engine selection guide

| Platform | Recommended engine | Notes |
|---|---|---|
| iOS | `PjsipEngine` | Requires a locally built PJSUA2 XCFramework; CallKit native call screen |
| Android | `PjsipEngine` | Requires a locally built PJSUA2 AAR; ConnectionService and foreground keepalive |
| macOS / Windows / Linux | `WebrtcEngine` | Foreground only — no OS call management on desktop |
| Any (fallback/dev) | `WebrtcEngine` | Works on all platforms; no native code required |

Switch with one constructor parameter:

```dart
// WebRTC (default — all platforms, foreground):
final client = SipKitClient();

// PJSIP (native background + CallKit/ConnectionService; build native artifacts first):
final client = SipKitClient(engine: PjsipEngine());

// Custom engine (provider-built):
final client = SipKitClient(engine: MyCpaasSipEngine());
```

---

## Quickstart

```dart
import 'package:sipkit_flutter/sipkit_flutter.dart';

// 1. Activate (gates everything else)
final client = SipKitClient();
await client.activate(
  licenseKey: 'pk_live_xxxxxxxxxxxxx',
  baseUrl:    'https://license.mydomain.com',
  appId:      'com.provider.softphone',
  deviceId:   'device-uuid-or-platform-id',
);

// 2. Add a SIP account (provider supplies their own SIP creds)
final account = await client.addAccount(SipKitAccountConfig(
  username:    'alice',
  password:    'secret',
  domain:      'pbx.provider.com',
  wsUrl:       'wss://pbx.provider.com:8089/ws',
  displayName: 'Alice',
  registerOnAdd: true,
));

// Listen to registration status
account.status.listen((s) => print('Registration: $s'));

// 3. Place a call
final call = await client.makeCall(account.id, 'sip:bob@pbx.provider.com');
call.state.listen((s) => print('Call: $s'));

// 4. Call control
await call.hold();
await call.unhold();
call.mute(true);
call.sendDtmf('123#');
await call.blindTransfer('sip:carol@pbx.provider.com');
await call.enableVideo(true);   // throws NotEntitledError if 'video' not in features

// 5. Incoming calls
client.incomingCalls.listen((call) async {
  await call.answer(video: false);
});

// 6. Conference (requires 'conference' feature)
await client.mergeCalls([callA.id, callB.id]);

// 7. Clean up
await client.dispose();
```

---

## `SipEngine` — public extension point

`SipEngine` is the adapter between the SipKit public API and the underlying SIP/media stack.  Providers can implement their own engine:

```dart
class MyCpaasSipEngine extends SipEngine {
  // Streams (must be broadcast, live for engine lifetime)
  final _incomingCallCtrl = StreamController<IncomingCallEvent>.broadcast();
  @override Stream<IncomingCallEvent> get incomingCall => _incomingCallCtrl.stream;
  // ... other streams

  @override Future<void> init() async {
    // Initialise your SDK here
  }

  @override Future<String> makeCall(String accountId, String target, {bool video = false}) async {
    // Place call and return a stable call ID
    return 'call_${DateTime.now().millisecondsSinceEpoch}';
  }

  // ... implement remaining abstract methods
}

// Use your engine transparently:
final client = SipKitClient(engine: MyCpaasSipEngine());
```

**IMPORTANT — Licensing:** Token gating is applied by `SipKitClient` *before*
any engine method is called. Custom engines therefore do not need to duplicate
entitlement checks when used with an unmodified SDK. Because GPL recipients
may inspect and modify the covered source, token enforcement must not be
described as technically or legally unbypassable in a GPL distribution.

---

## Feature gating

| Feature string | Gates |
|---|---|
| `"audio"` | Basic audio calling (always required) |
| `"video"` | `call.enableVideo(true)` and `makeCall(..., video: true)` |
| `"conference"` | `client.mergeCalls([...])` |
| `"transfer"` | `call.blindTransfer(...)` and `call.attendedTransfer(...)` |
| `"dtmf"` | `call.sendDtmf(...)` |

Attempting a gated operation without the feature throws `NotEntitledError` with a clear message.

---

## Offline grace window

The SDK caches the last valid entitlement JWT in `flutter_secure_storage`.  If the network is unavailable at refresh time, the SDK keeps functioning until `exp + graceWindow` (default **72 hours**).  After that it transitions to `ActivationState.locked` and all SIP operations throw `ActivationError`.

Customise the grace window:

```dart
final client = SipKitClient(
  cache: EntitlementCache(graceWindow: const Duration(hours: 48)),
);
```

---

## Public key pinning

By default the SDK ships a bundled RS256 public key for offline JWT verification.  To pin a custom key (e.g. after a server-side key rotation):

```dart
final client = SipKitClient(
  verifier: EntitlementVerifier(publicKeyPem: '''
-----BEGIN PUBLIC KEY-----
...your rotated public key...
-----END PUBLIC KEY-----
  '''),
);
```

Fetch the current public key from:
```
GET https://your-sipkit-backend.com/api/v1/public-key
```

---

## iOS setup (CallKit + PjsipEngine)

### `Info.plist` keys

```xml
<key>NSMicrophoneUsageDescription</key>
<string>SipKit needs the microphone for voice calls.</string>
<key>UIBackgroundModes</key>
<array>
  <string>audio</string>
  <string>voip</string>
</array>
```

Enable the Push Notifications capability when using PushKit. Native SipKit
calls are audio-only.

### Podfile

```ruby
pod 'sipkit_flutter', :path => '../sipkit_flutter'
# Build ios/Frameworks/PJSIP.xcframework before pod install; the SipKit podspec
# detects that path and links SipKit's built-in bridge to it.
```

---

## Android setup (ConnectionService + PjsipEngine)

### `AndroidManifest.xml` (in your app module)

```xml
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.MANAGE_OWN_CALLS" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_PHONE_CALL" />

<service android:name="com.sipkit.sipkit_flutter.SipKitConnectionService"
         android:permission="android.permission.BIND_TELECOM_CONNECTION_SERVICE"
         android:exported="true">
  <intent-filter>
    <action android:name="android.telecom.ConnectionService" />
  </intent-filter>
</service>
```

---

## Native PJSIP artifacts and GPL source

`PjsipEngine` does **not** bundle PJSIP/PJSUA2 binaries. Native SIP calls need
the platform artifact built at the paths consumed by SipKit's built-in native
bridge. The checked-in scripts pin pjproject to
`08578e86eea120c5ab2ab1af5a18b7840120d87b`, fetch that exact revision, and
abort if the checkout is different.

From `sipkit_flutter/`:

```sh
# Android: set this to an installed Android NDK, then produces android/libs/pjsua2-2.14.aar
export ANDROID_NDK_HOME=/absolute/path/to/android-ndk
./tool/build_android_pjsua2_aar.sh

# macOS/Xcode only: produces ios/Frameworks/PJSIP.xcframework
./tool/build_ios_pjsua2_xcframework.sh
```

The Android artifact contains arm64-v8a, armeabi-v7a, and x86_64 native
libraries. The iOS script builds device arm64 plus simulator arm64 and x86_64
slices. See [`docs/NATIVE_PJSIP.md`](docs/NATIVE_PJSIP.md) for prerequisites,
integration boundaries, reproducible source packaging, and GPL obligations.

The SDK source and GPL-built native distribution are licensed under
GPLv2-or-later. Distributors must provide complete corresponding source. This
licensing route allows recipients to modify and redistribute the covered code;
use a commercial PJSIP license and separately reviewed SDK terms instead if
that is incompatible with the product's business model.

---

## Provider native SIP configuration

For native PJSIP, `wsUrl` is optional. Use a registrar and UDP, TCP, or TLS
transport instead. This example deliberately uses provider values rather than
a public test service:

```dart
final account = await client.addAccount(SipKitAccountConfig(
  username: 'alice',
  password: providerIssuedPassword,
  domain: 'voice.provider.example',
  // wsUrl is optional for PjsipEngine; only supply it for WebrtcEngine.
  registrar: 'registrar.provider.example',
  sipPort: 5061,
  transport: SipTransport.tls,
  outboundProxy: 'sip:edge.provider.example;lr',
  verifyTls: true,
  tlsCaCertPath: '/app-support/provider-ca.pem',
  codecPreferences: const ['opus', 'PCMU'],
  keepAliveInterval: 30,
));
```

Provider checklist:

- Select `udp`, `tcp`, or `tls`; omitted ports resolve to 5060 (UDP/TCP) or
  5061 (TLS).
- Set `registrar` when it differs from `domain`; otherwise `domain` is used.
- For TLS, keep `verifyTls: true` and provide `tlsCaCertPath` only for an
  additional trusted PEM CA bundle. Do not disable verification in production.
- Use `outboundProxy` only when the provider requires a route, and ensure codec
  names and `keepAliveInterval` are accepted by the provider.
- Keep `wsUrl` for `WebrtcEngine` deployments; it is not a native SIP
  transport setting.

### Credential-redacted provider diagnostics

After activation and account creation, generate an opt-in local report:

```dart
final report = await client.diagnoseAccount(
  account.id,
  testTarget: 'sip:echo@provider.example', // optional; places a real call
);
print(report.toPrettyJson());
```

Pass a `SipDiagnosticCancellationToken` when the host needs a cancel action.
Cancellation hangs up a controlled test call and returns the partial,
credential-redacted report instead of discarding the completed checks.

Reports include stable check IDs, ownership labels, native artifact and audio
readiness, current registration response code/reason, transport evidence, and
an optional controlled call result. Credential-shaped evidence is redacted
during JSON serialization. SipKit does not upload reports; the host app must
explicitly copy, save, or send one.

---

## Asterisk / FreePBX WebSocket transport test setup

Create a WSS transport in `pjsip.conf`:
```ini
[transport-wss]
type=transport
protocol=wss
bind=0.0.0.0:8089
cert_file=/etc/asterisk/keys/asterisk.crt
priv_key_file=/etc/asterisk/keys/asterisk.key
```

Create two test extensions (`6001`, `6002`) in `pjsip.conf`:
```ini
[6001]
type=endpoint
transport=transport-wss
context=default
aors=6001
auth=6001-auth

[6001-auth]
type=auth
auth_type=userpass
username=6001
password=test1234

[6001]
type=aor
max_contacts=5
```

Register from the app with:
- domain: `your-pbx-host.com`
- wsUrl: `wss://your-pbx-host.com:8089/ws`
- username: `6001` / password: `test1234`

**Public SIP-over-WebSocket fallback:** `wss://sip2sip.info:5061` (free test accounts at https://mdns.sip2sip.info/).

---

## Roadmap

See `ROADMAP.md` in the project root.
