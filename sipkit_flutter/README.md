# SipKit Flutter SDK

A token-licensed Flutter SIP/VoIP SDK.  Add voice + video calling to your app — unlocked by a short-lived entitlement JWT issued by the SipKit licensing backend.

---

## Engine selection guide

| Platform | Recommended engine | Notes |
|---|---|---|
| iOS | `PjsipEngine` | CallKit native call screen; background socket via VoIP entitlement |
| Android | `PjsipEngine` | ConnectionService; background keepalive foreground service |
| macOS / Windows / Linux | `WebrtcEngine` | Foreground only — no OS call management on desktop |
| Any (fallback/dev) | `WebrtcEngine` | Works on all platforms; no native code required |

Switch with one constructor parameter:

```dart
// WebRTC (default — all platforms, foreground):
final client = SipKitClient();

// PJSIP (native background + CallKit/ConnectionService):
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

**IMPORTANT — Licensing:**  Token gating is applied by `SipKitClient` *before* any engine method is called.  Custom engines do **not** need to check entitlements — this enforcement cannot be bypassed regardless of which engine is used.

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
<key>NSCameraUsageDescription</key>
<string>SipKit needs the camera for video calls.</string>
<key>UIBackgroundModes</key>
<array>
  <string>voip</string>
</array>
```

### Entitlements (`.entitlements` file)

```xml
<key>com.apple.developer.networking.voip</key>
<true/>
```

### Podfile

```ruby
pod 'sipkit_flutter', :path => '../sipkit_flutter'
# Uncomment when PJSIP prebuilt xcframework is available:
# pod 'pjsip', '~> 2.14'
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
