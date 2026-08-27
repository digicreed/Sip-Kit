# Native certification results ledger

Status values are `PASS`, `FAIL`, `BLOCKED`, or `UNVERIFIED`. A release is
certified only when every required row is `PASS`. Do not put credentials,
license keys, push tokens, authorization headers, or unredacted SIP traces in
this file.

## Lab metadata

| Field | Value |
|---|---|
| SDK revision | |
| App version/build | |
| Test window (UTC) | |
| Tester/lab | |
| Provider staging environment | |

## Workspace preflight (this workspace)

These are environment blockers, not native certification passes. They explain
why the real-device rows below remain `UNVERIFIED`.

| Status | Check | Observed | Consequence |
|---|---|---|---|
| BLOCKED | Android build/install | Flutter, Android NDK, and ADB are unavailable in the Linux workspace | Cannot build or install the Android host |
| BLOCKED | iOS build/linkage | Xcode, `xcodebuild`, `xcrun`, and CocoaPods are unavailable in the Linux workspace | Cannot build or link the iOS host |
| BLOCKED | Provider registration | No staging provider account or SIP trace endpoint is available | UDP/TCP/TLS registration cannot be observed |
| BLOCKED | Physical behavior | No Android/iOS devices, FCM/PushKit credentials, or audio peripherals are attached | OS lifecycle, push, network, and audio rows cannot be exercised |

## Provider registrations

| Status | Provider/account alias | Transport/port | Device + OS | Expected | Observed callback/provider evidence | Failure reference |
|---|---|---|---|---|---|---|
| UNVERIFIED | | UDP/5060 | | `registered` after 2xx | | |
| UNVERIFIED | | TCP/5060 | | `registered` after 2xx | | |
| UNVERIFIED | | TLS/5061 | | `registered` after verified TLS + 2xx | | |
| UNVERIFIED | | Invalid credentials | | `failed`, never `registered` | | |
| UNVERIFIED | | Invalid/untrusted TLS | | `failed`, never `registered` | | |

## Call and OS behavior

| Status | Device + OS | Provider/transport | Scenario | Expected | Observed native/OS evidence | Failure reference |
|---|---|---|---|---|---|---|
| UNVERIFIED | | | Outbound: ringing → answer → hangup | | | |
| UNVERIFIED | | | Inbound: foreground → answer → remote hangup | | | |
| UNVERIFIED | | | Hold → resume | | | |
| UNVERIFIED | | | Mute → unmute | | | |
| UNVERIFIED | | | DTMF received by peer | | | |
| UNVERIFIED | | | Blind transfer | | | |
| UNVERIFIED | | | Attended transfer | | | |
| UNVERIFIED | | | Background inbound | | | |
| UNVERIFIED | | | Locked-screen inbound | | | |
| UNVERIFIED | | | FCM/PushKit correlation and timeout | | | |
| UNVERIFIED | | | Network loss and recovery | | | |
| UNVERIFIED | | | Earpiece | | | |
| UNVERIFIED | | | Speaker | | | |
| UNVERIFIED | | | Wired audio | | | |
| UNVERIFIED | | | Bluetooth audio | | | |

## Reproducible failures

| ID | First seen | Device/OS/provider | Scenario | Reproduction steps | Logs/evidence (redacted) | Current disposition |
|---|---|---|---|---|---|---|
| | | | | | | |