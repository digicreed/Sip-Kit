import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../models/account_config.dart';
import '../models/account_status.dart';
import '../models/call_state.dart';
import 'sip_engine.dart';

/// SIP engine backed by PJSUA2 (PJSIP) via Flutter platform channels.
///
/// Unlike [WebrtcEngine], this engine delegates all media and SIP processing
/// to native code (Swift on iOS, Kotlin on Android).  This enables:
///
///   • **True background calling** — PJSIP keeps a socket alive in a
///     foreground service (Android) or background VoIP socket (iOS).
///   • **CallKit (iOS)** — incoming calls show the native iOS call screen
///     even when the app is locked or closed.
///   • **ConnectionService (Android)** — native Android incoming call UI,
///     system call log integration, and Bluetooth headset support.
///
/// Platform support:
///   | Platform | Supported |
///   |---|---|
///   | iOS     | ✅ (CallKit + VoIP socket) |
///   | Android | ✅ (ConnectionService + foreground service) |
///   | macOS / Windows / Linux | ⚠️ Not yet supported (see ROADMAP) |
///
/// Switching from [WebrtcEngine] to [PjsipEngine] requires only one change:
/// ```dart
/// final client = SipKitClient(engine: PjsipEngine());
/// ```
///
/// LICENSING:
///   All token gating is applied by [SipKitClient] before engine methods are
///   called.  [PjsipEngine] does not need to check entitlements.
class PjsipEngine extends SipEngine {
  static const _channel =
      MethodChannel('com.sipkit.sipkit_flutter/pjsip');
  static const _eventChannel =
      EventChannel('com.sipkit.sipkit_flutter/pjsip_events');

  StreamSubscription<dynamic>? _eventSubscription;

  final _incomingCallCtrl = StreamController<IncomingCallEvent>.broadcast();
  final _callStateCtrl = StreamController<CallStateEvent>.broadcast();
  final _accountStatusCtrl =
      StreamController<AccountStatusEvent>.broadcast();
  final _localStreamCtrl =
      StreamController<(String, MediaStream)>.broadcast();
  final _remoteStreamCtrl =
      StreamController<(String, MediaStream)>.broadcast();

  @override
  Stream<IncomingCallEvent> get incomingCall => _incomingCallCtrl.stream;
  @override
  Stream<CallStateEvent> get callStateChanged => _callStateCtrl.stream;
  @override
  Stream<AccountStatusEvent> get accountStatusChanged =>
      _accountStatusCtrl.stream;
  @override
  Stream<(String, MediaStream)> get localStream => _localStreamCtrl.stream;
  @override
  Stream<(String, MediaStream)> get remoteStream => _remoteStreamCtrl.stream;

  // ─── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  Future<void> init() async {
    await _channel.invokeMethod<void>('init');
    _eventSubscription =
        _eventChannel.receiveBroadcastStream().listen(_onNativeEvent);
  }

  @override
  Future<void> dispose() async {
    await _eventSubscription?.cancel();
    await _channel.invokeMethod<void>('dispose');
    await Future.wait([
      _incomingCallCtrl.close(),
      _callStateCtrl.close(),
      _accountStatusCtrl.close(),
      _localStreamCtrl.close(),
      _remoteStreamCtrl.close(),
    ]);
  }

  // ─── Accounts ──────────────────────────────────────────────────────────────

  @override
  Future<void> registerAccount(
      String accountId, SipKitAccountConfig config) async {
    await _channel.invokeMethod<void>('registerAccount', {
      'accountId': accountId,
      'username': config.username,
      'password': config.password,
      'domain': config.domain,
      'wsUrl': config.wsUrl,
      'displayName': config.displayName ?? config.username,
      'authUsername': config.authUsername ?? config.username,
      'registrationExpiry': config.registrationExpiry,
      'iceServers': config.iceServers
          .map((s) => {
                'url': s.url,
                if (s.username != null) 'username': s.username,
                if (s.credential != null) 'credential': s.credential,
              })
          .toList(),
    });
  }

  @override
  Future<void> unregister(String accountId) async {
    await _channel
        .invokeMethod<void>('unregister', {'accountId': accountId});
  }

  // ─── Calls ─────────────────────────────────────────────────────────────────

  @override
  Future<String> makeCall(
    String accountId,
    String target, {
    bool video = false,
  }) async {
    final callId = await _channel.invokeMethod<String>('makeCall', {
      'accountId': accountId,
      'target': target,
      'video': video,
    });
    return callId!;
  }

  @override
  Future<void> answer(String callId, {bool video = false}) async {
    await _channel
        .invokeMethod<void>('answer', {'callId': callId, 'video': video});
  }

  @override
  Future<void> hangup(String callId) async {
    await _channel.invokeMethod<void>('hangup', {'callId': callId});
  }

  @override
  Future<void> hold(String callId) async {
    await _channel.invokeMethod<void>('hold', {'callId': callId});
  }

  @override
  Future<void> unhold(String callId) async {
    await _channel.invokeMethod<void>('unhold', {'callId': callId});
  }

  @override
  Future<void> mute(String callId, {required bool muted}) async {
    await _channel
        .invokeMethod<void>('mute', {'callId': callId, 'muted': muted});
  }

  @override
  Future<void> sendDtmf(String callId, String digits) async {
    await _channel
        .invokeMethod<void>('sendDtmf', {'callId': callId, 'digits': digits});
  }

  @override
  Future<void> blindTransfer(String callId, String targetUri) async {
    await _channel.invokeMethod<void>(
        'blindTransfer', {'callId': callId, 'targetUri': targetUri});
  }

  @override
  Future<void> attendedTransfer(String callId, String otherCallId) async {
    await _channel.invokeMethod<void>('attendedTransfer',
        {'callId': callId, 'otherCallId': otherCallId});
  }

  @override
  Future<void> enableVideo(String callId, {required bool enabled}) async {
    await _channel.invokeMethod<void>(
        'enableVideo', {'callId': callId, 'enabled': enabled});
  }

  // ─── Native event dispatch ─────────────────────────────────────────────────

  void _onNativeEvent(dynamic raw) {
    if (raw is! Map) return;
    final event = Map<String, dynamic>.from(raw);
    final type = event['type'] as String?;

    if (type == 'accountStatus') {
      final status = _parseAccountStatus(event['status'] as String? ?? '');
      _accountStatusCtrl.add(AccountStatusEvent(
        accountId: event['accountId'] as String? ?? '',
        status: status,
        reason: event['reason'] as String?,
      ));
    } else if (type == 'callState') {
      final state = _parseCallState(event['state'] as String? ?? '');
      _callStateCtrl.add(CallStateEvent(
        callId: event['callId'] as String? ?? '',
        state: state,
        reason: event['reason'] as String?,
      ));
    } else if (type == 'incomingCall') {
      _incomingCallCtrl.add(IncomingCallEvent(
        callId: event['callId'] as String? ?? '',
        accountId: event['accountId'] as String? ?? '',
        remoteUri: event['remoteUri'] as String? ?? '',
        displayName: event['displayName'] as String? ?? '',
        hasVideo: event['hasVideo'] as bool? ?? false,
      ));
    }
  }

  static AccountStatus _parseAccountStatus(String s) {
    if (s == 'registered') return AccountStatus.registered;
    if (s == 'unregistered') return AccountStatus.unregistered;
    if (s == 'registering') return AccountStatus.registering;
    return AccountStatus.failed;
  }

  static CallState _parseCallState(String s) {
    if (s == 'connecting') return CallState.connecting;
    if (s == 'ringing') return CallState.ringing;
    if (s == 'earlyMedia') return CallState.earlyMedia;
    if (s == 'established') return CallState.established;
    if (s == 'held') return CallState.held;
    return CallState.terminated;
  }
}
