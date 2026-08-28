# Native provider example

This example drives `PjsipEngine` only. It intentionally accepts provider and
license values at runtime instead of committing credentials.

1. Build the native artifact from the package root:

   ```sh
   # Android
   export ANDROID_NDK_HOME=/absolute/path/to/android-ndk
   ./tool/build_android_pjsua2_aar.sh

   # iOS, on macOS with Xcode
   ./tool/build_ios_pjsua2_xcframework.sh
   ```

2. Generate the unsigned Flutter host shells once, then install dependencies:

   ```sh
   cd example
   flutter create --platforms=android,ios .
   flutter pub get
   ```

3. For iOS, enable Push Notifications and the `audio` and `voip` background
   modes on the Runner target. Configure provider APNs/PushKit delivery.

4. For Android, configure Firebase Messaging for push-assisted inbound calls.
   Grant microphone and notification permissions on the device. A fully
   terminated-process call requires host-owned secure native account
   restoration, which this diagnostic app does not implement.

5. Run on a physical device, select the provider transport, enter a staging
   account, and press **Activate & register**. Registration and call labels
   change only from native callbacks. The call controls expose mute, DTMF,
   blind transfer, and a two-leg attended-transfer flow for the certification
   matrix.

6. Tap **Run registration diagnostics** to collect a local report. If a safe
   echo, voicemail, or test destination is entered, the action places one real
   audio call and hangs it up after an established, terminated, or timeout
   state. Use **Copy redacted JSON** or **Save / share report** to hand the
   report to provider support. Passwords, tokens, authorization headers, and
   credential-shaped evidence are replaced with `[REDACTED]`.

Do not use production SIP passwords in this diagnostic example. Follow
[`docs/NATIVE_PJSIP.md`](../docs/NATIVE_PJSIP.md) for push payload correlation,
GPL source distribution, and the complete physical-device test checklist.
For the release-gate ledger and evidence rules, see
[`docs/NATIVE_CERTIFICATION.md`](../docs/NATIVE_CERTIFICATION.md).