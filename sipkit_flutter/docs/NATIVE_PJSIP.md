# Building and distributing native PJSIP artifacts

The native build input is intentionally immutable:

```text
pjproject repository: https://github.com/pjsip/pjproject.git
pjproject commit:     08578e86eea120c5ab2ab1af5a18b7840120d87b
```

`tool/common.sh` fetches this commit by object ID and compares `HEAD` to that
full ID before every build. A checkout at a branch, tag, or a different commit
is rejected rather than silently used.

## Prerequisites and commands

Run commands from the `sipkit_flutter` directory.

### Android

Install Git, GNU make, `zip`, a JDK (`jar`), and an Android NDK. Point
`ANDROID_NDK_HOME` (or `ANDROID_NDK_ROOT`) at the NDK directory that contains
`ndk-build`, then run:

```sh
export ANDROID_NDK_HOME=/opt/android-ndk
./tool/build_android_pjsua2_aar.sh
```

The output is `android/libs/pjsua2-2.14.aar`, the path consumed by this
package's Gradle configuration. It contains upstream SWIG-generated
`org.pjsip.pjsua2` Java classes, `libpjsua2.so`, and the required
`libc++_shared.so` runtime for `arm64-v8a`, `armeabi-v7a`, and `x86_64`, plus
the GPL notice and GPLv2 text. PJSIP's default static component archives are
linked into `libpjsua2.so`, rather than being shipped as an uncontrolled set
of PJSIP shared libraries. Installing this artifact activates SipKit's
built-in Android native bridge; a consuming application must not provide its
own Java/Kotlin JNI bridge.

### iOS

Run on macOS with Xcode selected (`xcode-select -p`), Xcode command-line tools,
Git, and make:

```sh
./tool/build_ios_pjsua2_xcframework.sh
```

The output is `ios/Frameworks/PJSIP.xcframework`, the path consumed by this
package's podspec. It has one device arm64 library and one universal simulator
arm64/x86_64 library, plus public PJSIP, PJLIB, PJLIB-UTIL, PJMEDIA, and
PJNATH headers, the GPL notice, and GPLv2 text. Installing it activates
SipKit's built-in iOS native bridge; a consuming application must not supply a
separate bridge. The script fails before compiling when it is not running on
macOS or Xcode tools are unavailable.

These scripts build libraries only. They do not assert that a physical device,
provider, registration, or call has been tested.

## Provider configuration and push contract

Native accounts use `registrar`, `sipPort`, and `transport`; `wsUrl` is only
required by `WebrtcEngine`. Keep TLS verification enabled in production. A
bare dial string such as `12065550100` is resolved against the account domain,
while a complete `sip:` or `sips:` URI is used as supplied.

Push-assisted incoming calls require provider-owned signaling in addition to
SIP:

- Send data-only FCM messages on Android and VoIP pushes on iOS.
- Include `callId`, `accountId`, `remoteUri`, and `displayName`.
- On both platforms, `callId` must exactly match the SIP `Call-ID` header so
  the OS call can be reconciled with the real dialog.
- Deliver the real SIP INVITE immediately after the push. SipKit never treats
  a push-only CallKit/Telecom action as an answered SIP dialog.
- SipKit accepts a push only when its native SIP account is already active.
  Suspended/background apps retain that account. Fully terminated-process
  recovery requires host-specific secure native account restoration before the
  push callback; this package intentionally does not persist SIP passwords.

The iOS host target must enable Push Notifications and the `voip` and `audio`
background modes. The Android host must configure Firebase Messaging and
request microphone and notification permissions at runtime where required.

## Physical-device validation checklist

Run these checks against a provider staging account before shipping:

1. Register over every supported provider transport (UDP/TCP/TLS), confirm a
   genuine 2xx registration callback, then test auth and TLS failures.
2. Place and receive an audio call; verify calling, ringing, established, held,
   resumed, and terminated states come from the provider dialog.
3. Verify two-way audio, mute, DTMF, blind transfer, and attended transfer.
4. Route audio through earpiece, speaker, wired audio, and Bluetooth.
5. Receive and answer while foregrounded, backgrounded, and screen-locked.
   Confirm remote hangup clears CallKit or Android Telecom immediately. Test a
   terminated-process cold start only if the host implements secure native
   account restoration before push handling.
6. Repeat after network loss/recovery and app relaunch. Inspect native logs for
   registration loops, leaked calls, or silent fallback behavior.

## GPL v2-or-later distribution obligations

PJSIP/pjproject is available under a GPLv2 licensing option (or separately
under commercial terms). If you distribute an artifact made under the GPL
option, your distribution must meet GPL version 2 or later obligations:

1. Preserve copyright and GPL notices, including
   [`LICENSES/PJPROJECT-GPL-NOTICE.md`](../LICENSES/PJPROJECT-GPL-NOTICE.md)
   and the upstream `COPYING` file.
2. License the covered distribution under GPLv2-or-later and provide recipients
   complete corresponding source, including scripts and configuration needed to
   build the binary.
3. Make that source available with the binary or through a valid written offer
   for the period required by the GPL. Consult counsel for a particular
   distribution model.

Do not rely on a URL to a moving upstream branch as the sole source offer.
Create the matching source archive from the same committed SipKit revision:

```sh
./tool/package_gpl_source.sh
```

It writes `dist/sipkit-pjsip-gpl-source.tar.gz`, containing the complete
tracked SipKit checkout (including build scripts and notices) and the exact
pjproject checkout. The script refuses dirty SipKit trees and normalizes file
ordering, ownership, and timestamps using the SipKit commit timestamp, so a
given committed input produces a reproducible source package. It intentionally
does not commit third-party pjproject source into this repository.