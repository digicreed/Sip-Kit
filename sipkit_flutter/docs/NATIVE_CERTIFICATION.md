# Native call release certification

This document is the release gate for `PjsipEngine`. The build scripts create
reproducible native inputs, but a successful build is not evidence that SIP
signaling, OS call UI, audio routing, push delivery, or a provider
interoperates correctly. Every release must have a completed results ledger
from real devices and staging accounts.

## Current workspace status

**Not certified.** This Linux workspace cannot run the required Android NDK or
Xcode builds, install a Flutter app on physical devices, deliver FCM/PushKit
notifications, exercise audio routes, or register against provider staging
accounts. The unavailable checks are recorded as `BLOCKED` rather than being
treated as passes. Complete and attach
[`NATIVE_CERTIFICATION_RESULTS.md`](NATIVE_CERTIFICATION_RESULTS.md) from the
macOS/Android device lab before shipping.

## Release inputs

Run from the `sipkit_flutter` directory. The native scripts pin pjproject to
the commit in `tool/pjproject.env`; do not substitute a branch, tag, or local
checkout.

### Android artifact and app consumption

On a machine with the Android NDK, JDK, Git, `make`, `zip`, and SWIG:

```sh
export ANDROID_NDK_HOME=/absolute/path/to/android-ndk
./tool/build_android_pjsua2_aar.sh
./tool/verify_native_artifacts.sh --android-only
```

The generated `android/libs/pjsua2-2.14.aar` is consumed automatically by the
plugin's Gradle configuration when it exists. In a clean checkout, create the
Flutter host and build it before installing to a device:

```sh
cd example
flutter create --platforms=android,ios .
flutter pub get
flutter build apk --debug
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

Record the app build identifier and the output of the artifact verifier. Do
not commit the AAR unless the distribution policy explicitly requires it; the
GPL source package must match the shipped binary.

### iOS artifact and CocoaPods/Xcode linkage

On macOS with Xcode command-line tools selected:

```sh
./tool/build_ios_pjsua2_xcframework.sh
./tool/verify_native_artifacts.sh --ios-only
cd example
flutter create --platforms=android,ios .
flutter pub get
cd ios
pod install
xcodebuild -workspace Runner.xcworkspace -scheme Runner \
  -sdk iphoneos -configuration Debug build
```

The build must select the `PJSIPBridge.mm` path in the podspec and link
`PJSIP.xcframework`; a build that silently selects
`PJSIPUnavailableBridge.m` is not a native certification pass. Install the
resulting app on a physical iPhone and record the device/OS and Xcode version.

## Provider interoperability matrix

Use two staging accounts or two registered devices on the same provider so
both call legs can be observed. Use a fresh account for each transport where
possible. TLS validation must remain enabled.

| Transport | Registrar port | Required evidence |
|---|---:|---|
| UDP | 5060 or provider port | Native `registered` callback and provider-side 2xx REGISTER |
| TCP | 5060 or provider port | Native `registered` callback and provider-side 2xx REGISTER |
| TLS | 5061 or provider port | Native `registered` callback, 2xx REGISTER, and verified certificate chain |

For each transport, also submit a negative auth result with an intentionally
invalid password and a negative TLS result using an invalid/untrusted
certificate where the provider supports it. The app must report a failed
registration and must not report `registered`.

## Device and call matrix

Each row is a required observation, not a scripted mock. The call state must
come from the provider dialog and the remote device must confirm the behavior.

| Area | Required observations |
|---|---|
| Call lifecycle | Outbound and inbound; ringing; answer; hangup; remote termination |
| Media controls | Hold/resume; mute/unmute; DTMF digits received by the peer |
| Transfer | Blind transfer and attended transfer with a third call leg |
| App state | Foreground, background, locked screen, and relaunch |
| Push | FCM/PushKit correlation by exact SIP `Call-ID`; timeout and duplicate push |
| Network | Wi-Fi to cellular or loss/recovery; registration and active call recovery |
| Audio | Earpiece, speaker, wired headset, and Bluetooth route changes |

At minimum, cover one current Android phone and one current iPhone plus one
older supported OS/device combination. Repeat inbound scenarios with the app
backgrounded and screen-locked. A terminated-process test is only valid when
the host restores the SIP account from secure native storage before handling
the push; this SDK intentionally does not persist SIP passwords.

## Pass/fail evidence rules

For every row in the results ledger, record:

- provider name, staging environment, transport, registrar port, and account
  alias (never a password or token);
- app version/build, SDK revision, device model, OS version, and test timestamp;
- expected result, observed native callback/OS UI, and a short pass/fail reason;
- redacted native logs containing the relevant call or registration identifier;
- a reproducible failure description and the smallest known reproduction when
  the result is not a pass.

Never use a screenshot or a push receipt alone as evidence of a SIP call:
correlate it with the native registration/call event and provider-side dialog.
Remove phone numbers, SIP usernames, authorization headers, push tokens, and
license material before sharing logs.

## Failure triage

1. Confirm the artifact verifier passed and that the host linked the native
   bridge, not the unavailable fallback.
2. Compare the native callback with provider SIP traces. Distinguish DNS,
   transport, TLS, digest authentication, SDP/media, and OS lifecycle failures.
3. Re-run the smallest failing row on a second device or network.
4. Add the failure to the ledger with exact reproduction steps; do not mark a
   release certified while any required row is `FAIL`, `BLOCKED`, or
   `UNVERIFIED`.