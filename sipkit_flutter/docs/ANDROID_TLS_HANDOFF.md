# Android TLS/5061 developer handoff

The provider endpoint and account have been independently verified:

- Registrar: `sip.talkloop.ai`
- Transport: TLS
- Port: 5061
- Server certificate verification succeeds.
- Correct provider credentials complete an authenticated REGISTER with
  `SIP/2.0 200 OK`.

Do not put SIP passwords in source code, build scripts, screenshots, or logs.

## 1. Install build prerequisites

Use a Linux x86_64 or macOS x86_64/Apple Silicon machine with:

- Android SDK and NDK
- JDK with `java`, `javac`, and `jar`
- Git
- GNU make
- Perl
- SWIG
- `zip`, `unzip`, and `file`
- Flutter SDK for the final application build

The scripts do not use Docker and do not download the Android NDK.

## 2. Build the TLS-enabled native AAR

From `sipkit_flutter/`:

```sh
export ANDROID_NDK_HOME=/absolute/path/to/android-ndk
./tool/build_android_tls_aar.sh
```

This command:

1. Fetches pinned OpenSSL 3.0.4 source.
2. Builds static OpenSSL for `arm64-v8a`, `armeabi-v7a`, and `x86_64`.
3. Fetches the pinned pjproject revision.
4. Builds PJSUA2 with `--with-ssl` for every ABI.
5. Fails if pjproject does not print `SSL support enabled`.
6. Creates and verifies `android/libs/pjsua2-2.14.aar`.

Optional build controls:

```sh
export ANDROID_API=24
export JOBS=8
export OPENSSL_ANDROID_ROOT=/absolute/output/path/android-openssl
```

Do not continue if the native build or verification command fails.

## 3. Build and reinstall the Flutter application

From the Flutter application directory:

```sh
flutter clean
flutter pub get
flutter build apk --release
```

Uninstall the old application before installing the new APK so stale native
libraries and persisted test accounts cannot affect the result:

```sh
adb uninstall <application-id>
adb install build/app/outputs/flutter-apk/app-release.apk
```

If ADB is unavailable, uninstall the old app from Android settings and install
the generated APK manually.

## 4. Configure the provider account

Use the provider-issued values:

- Username/authentication username: the exact `.talkloop.ai` account value
- Domain/registrar: `sip.talkloop.ai`
- Transport: TLS
- SIP port: 5061
- Verify TLS certificate: enabled

Do not reuse the earlier `.talkloop.com` username typo.

## 5. Acceptance checks

1. The app reports the account as registered.
2. `pjsip show contacts` shows the device contact while the app is running.
3. The contact becomes `Avail` when Asterisk qualifies it.
4. Place an outbound audio call and confirm two-way audio.
5. Place an inbound audio call and confirm Android Telecom UI.
6. Repeat registration after app restart and network switching.

`PJSIP_EUNSUPTRANSPORT` means the APK still contains an old non-TLS AAR.
An immediate final `401 Unauthorized` means the auth username/password is
wrong. A timeout requires checking device logs and provider-side SIP traces.