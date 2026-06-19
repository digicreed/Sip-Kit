import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../models/account_config.dart';
import '../models/account_status.dart';
import '../models/call_direction.dart';
import '../models/call_state.dart';

// ---------------------------------------------------------------------------
// SipEngine — PUBLIC STABLE EXTENSION POINT
// ---------------------------------------------------------------------------
//
// `SipEngine` is the adapter seam between the SipKit public API and the
// underlying SIP transport/media stack.  SipKit ships two built-in engines:
//
//   • WebrtcEngine  — sip_ua + flutter_webrtc.  Works on all Flutter targets
//                     (iOS, Android, macOS, Windows, Linux) in the foreground.
//                     No native code required.
//
//   • PjsipEngine   — PJSUA2 via Flutter platform channels.  Enables true
//                     background calling, CallKit (iOS), and ConnectionService
//                     (Android).  Requires the bundled Swift/Kotlin plugin.
//
// PROVIDERS MAY IMPLEMENT THEIR OWN ENGINE by subclassing `SipEngine`.  This
// lets you plug in a proprietary SIP stack, a cloud CPaaS SDK, or a custom
// transport without changing a single line of provider-facing API.
//
//   class MyCpaasSipEngine extends SipEngine {
//     @override Future<void> init() async { /* ... */ }
//     // ... implement all abstract members
//   }
//
//   final client = SipKitClient(engine: MyCpaasSipEngine());
//
// IMPORTANT — LICENSING:
//   Token gating is applied by `SipKitClient` **before** any engine method is
//   called.  Custom engines do NOT need to check entitlements — that
//   enforcement cannot be bypassed regardless of which engine is used.
//
// STREAM CONTRACTS:
//   All broadcast streams must remain open for the lifetime of the engine
//   instance.  `dispose()` must close all stream controllers.
// ---------------------------------------------------------------------------

/// Event emitted when the account registration status changes.
class AccountStatusEvent {
  const AccountStatusEvent({
    required this.accountId,
    required this.status,
    this.reason,
  });

  final String accountId;
  final AccountStatus status;
  final String? reason;
}

/// Event emitted when a call's state changes.
class CallStateEvent {
  const CallStateEvent({
    required this.callId,
    required this.state,
    this.reason,
  });

  final String callId;
  final CallState state;
  final String? reason;
}

/// Event emitted when an incoming call arrives.
class IncomingCallEvent {
  const IncomingCallEvent({
    required this.callId,
    required this.accountId,
    required this.remoteUri,
    required this.displayName,
    this.hasVideo = false,
  });

  final String callId;
  final String accountId;
  final String remoteUri;
  final String displayName;
  final bool hasVideo;
}

/// Abstract adapter between [SipKitClient] and a concrete SIP/media stack.
///
/// All methods are guarded by licensing checks in [SipKitClient] before they
/// are dispatched here — engines must not perform their own entitlement checks.
abstract class SipEngine {
  // ─── Lifecycle ─────────────────────────────────────────────────────────────

  /// Initialise the engine.  Called once by [SipKitClient] before any account
  /// or call operations.
  Future<void> init();

  /// Release all resources held by the engine.  After this call the engine
  /// must not emit further events.
  Future<void> dispose();

  // ─── Account management ────────────────────────────────────────────────────

  /// Register a SIP account described by [config].  The engine must use
  /// [accountId] as the stable identifier for subsequent calls.
  Future<void> registerAccount(String accountId, SipKitAccountConfig config);

  /// Send a REGISTER with `expires=0` for [accountId].
  Future<void> unregister(String accountId);

  // ─── Call management ───────────────────────────────────────────────────────

  /// Place an outbound call from [accountId] to [target] (a full SIP URI or
  /// phone number).  Returns a stable [callId] for the new call.
  Future<String> makeCall(
    String accountId,
    String target, {
    bool video = false,
  });

  /// Answer an incoming call identified by [callId].
  Future<void> answer(String callId, {bool video = false});

  /// Terminate a call (BYE / CANCEL depending on state).
  Future<void> hangup(String callId);

  /// Put the call on hold (`a=inactive` / `sendonly`).
  Future<void> hold(String callId);

  /// Resume a held call.
  Future<void> unhold(String callId);

  /// Mute or unmute the local microphone.
  Future<void> mute(String callId, {required bool muted});

  /// Send one or more DTMF digits via RFC 2833 INFO.
  Future<void> sendDtmf(String callId, String digits);

  /// Initiate a blind (unattended) transfer to [targetUri].
  Future<void> blindTransfer(String callId, String targetUri);

  /// Initiate an attended transfer: [callId] is transferred to [otherCallId].
  Future<void> attendedTransfer(String callId, String otherCallId);

  /// Enable or disable the video track on an established call.
  /// Throws if the engine does not support video for the current platform.
  Future<void> enableVideo(String callId, {required bool enabled});

  // ─── Streams ───────────────────────────────────────────────────────────────

  /// Emits [IncomingCallEvent] for every incoming call.
  Stream<IncomingCallEvent> get incomingCall;

  /// Emits [CallStateEvent] whenever a call's state changes.
  Stream<CallStateEvent> get callStateChanged;

  /// Emits [AccountStatusEvent] whenever an account's registration status
  /// changes.
  Stream<AccountStatusEvent> get accountStatusChanged;

  /// Emits the local [MediaStream] when it becomes available for [callId].
  Stream<(String callId, MediaStream stream)> get localStream;

  /// Emits the remote [MediaStream] when it becomes available for [callId].
  Stream<(String callId, MediaStream stream)> get remoteStream;
}
