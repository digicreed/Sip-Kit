import 'dart:async';
import 'dart:math';

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:sip_ua/sip_ua.dart';

import '../models/account_config.dart';
import '../models/account_status.dart';
import '../models/call_state.dart';
import 'sip_engine.dart';

/// SIP engine built on [sip_ua] + [flutter_webrtc].
///
/// Supports all Flutter targets (iOS, Android, macOS, Windows, Linux) in
/// the foreground.  No native code is required.  For background calling,
/// CallKit (iOS) or ConnectionService (Android), use [PjsipEngine] instead.
///
/// Each SIP account is backed by its own [SIPUAHelper] + dedicated
/// [_AccountListener] so that registration-state and call-state events can
/// be reliably mapped to the correct accountId even in multi-account setups.
class WebrtcEngine extends SipEngine {
  final Map<String, _AccountHandle> _accounts = {};
  final Map<String, _CallHandle> _calls = {};

  final _incomingCallCtrl = StreamController<IncomingCallEvent>.broadcast();
  final _callStateCtrl = StreamController<CallStateEvent>.broadcast();
  final _accountStatusCtrl = StreamController<AccountStatusEvent>.broadcast();
  final _localStreamCtrl = StreamController<(String, MediaStream)>.broadcast();
  final _remoteStreamCtrl = StreamController<(String, MediaStream)>.broadcast();

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

  @override
  Future<void> init() async {}

  @override
  Future<void> dispose() async {
    for (final h in _accounts.values) {
      h.helper.stop();
    }
    _accounts.clear();
    _calls.clear();
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
    String accountId,
    SipKitAccountConfig config,
  ) async {
    final wsUrl = config.wsUrl;
    if (wsUrl == null || wsUrl.trim().isEmpty) {
      throw ArgumentError.value(
        wsUrl,
        'config.wsUrl',
        'WebrtcEngine requires a SIP WebSocket URL',
      );
    }
    final helper = SIPUAHelper();
    // Per-account listener: events carry the correct accountId.
    final listener = _AccountListener(accountId: accountId, engine: this);
    _accounts[accountId] = _AccountHandle(
      accountId: accountId,
      helper: helper,
      listener: listener,
    );
    helper.addSipUaHelperListener(listener);

    final settings = UaSettings()
      ..webSocketUrl = wsUrl
      ..webSocketSettings.allowBadCertificate = !config.verifyTls
      ..uri = 'sip:${config.username}@${config.domain}'
      ..authorizationUser = config.authUsername ?? config.username
      ..password = config.password
      ..displayName = config.displayName ?? config.username
      ..userAgent = config.userAgent ?? 'SipKit-Flutter/0.1.0'
      ..dtmfMode = DtmfMode.RFC2833
      ..registerExpires = config.registrationExpiry
      ..iceServers = config.iceServers
          .map(
            (s) => RTCIceServer(
              urls: s.url,
              username: s.username,
              credential: s.credential,
            ),
          )
          .toList();

    await helper.start(settings);
  }

  @override
  Future<void> unregister(String accountId) async {
    _accounts[accountId]?.helper.unregister(true);
  }

  // ─── Calls ─────────────────────────────────────────────────────────────────

  @override
  Future<String> makeCall(
    String accountId,
    String target, {
    bool video = false,
  }) async {
    final handle = _accounts[accountId];
    if (handle == null) throw StateError('Account $accountId not registered');

    // Reserve the call ID before calling — the CALL_INITIATION event will
    // arrive synchronously or shortly after and must use this same ID.
    final callId = _generateCallId();
    handle.pendingOutboundCallId = callId;
    _calls[callId] = _CallHandle(callId: callId, accountId: accountId);

    final mediaConstraints = <String, dynamic>{'audio': true, 'video': video};
    handle.helper.call(
      target,
      mediaConstraints: mediaConstraints,
      voiceonly: !video,
    );
    return callId;
  }

  @override
  Future<void> answer(String callId, {bool video = false}) async {
    final sipCall = _calls[callId]?.sipCall;
    if (sipCall == null) return;
    sipCall.answer(<String, dynamic>{
      'mediaConstraints': {'audio': true, 'video': video},
    });
  }

  @override
  Future<void> hangup(String callId) async {
    _calls[callId]?.sipCall?.hangup({});
  }

  @override
  Future<void> hold(String callId) async {
    _calls[callId]?.sipCall?.hold();
  }

  @override
  Future<void> unhold(String callId) async {
    _calls[callId]?.sipCall?.unhold();
  }

  @override
  Future<void> mute(String callId, {required bool muted}) async {
    final sipCall = _calls[callId]?.sipCall;
    if (sipCall == null) return;
    if (muted) {
      sipCall.mute(audio: true, video: false);
    } else {
      sipCall.unmute(audio: true, video: false);
    }
  }

  @override
  Future<void> sendDtmf(String callId, String digits) async {
    _calls[callId]?.sipCall?.sendDTMF(digits);
  }

  @override
  Future<void> blindTransfer(String callId, String targetUri) async {
    _calls[callId]?.sipCall?.refer(targetUri);
  }

  @override
  Future<void> attendedTransfer(String callId, String otherCallId) async {
    final a = _calls[callId]?.sipCall;
    final b = _calls[otherCallId]?.sipCall;
    if (a == null || b == null) return;
    a.refer(b.remote_identity?.uri.toString() ?? '');
  }

  @override
  Future<void> enableVideo(String callId, {required bool enabled}) async {
    final sipCall = _calls[callId]?.sipCall;
    if (sipCall == null) return;
    if (enabled) {
      sipCall.unmute(audio: false, video: true);
    } else {
      sipCall.mute(audio: false, video: true);
    }
  }

  // ─── Per-account callbacks (called from _AccountListener) ─────────────────

  void _onRegistrationState(String accountId, RegistrationState state) {
    final AccountStatus status;
    if (state.state == RegistrationStateEnum.REGISTERED) {
      status = AccountStatus.registered;
    } else if (state.state == RegistrationStateEnum.UNREGISTERED) {
      status = AccountStatus.unregistered;
    } else if (state.state == RegistrationStateEnum.REGISTRATION_FAILED) {
      status = AccountStatus.failed;
    } else {
      status = AccountStatus.registering;
    }
    _accountStatusCtrl.add(
      AccountStatusEvent(
        accountId: accountId,
        status: status,
        reason: state.cause,
      ),
    );
  }

  void _onCallState(String accountId, Call call, CallState2 state) {
    // Skip mute/unmute events — they don't change SipKit CallState.
    if (state.state == CallStateEnum.MUTED ||
        state.state == CallStateEnum.UNMUTED) {
      return;
    }

    // Resolve call ID: existing → pending outbound → new inbound ID.
    final String callId = _resolveCallId(accountId, call, state);

    final CallState mapped;
    if (state.state == CallStateEnum.PROGRESS) {
      mapped = CallState.earlyMedia;
    } else if (state.state == CallStateEnum.CONFIRMED ||
        state.state == CallStateEnum.ACCEPTED) {
      mapped = CallState.established;
    } else if (state.state == CallStateEnum.HOLD) {
      mapped = CallState.held;
    } else if (state.state == CallStateEnum.UNHOLD) {
      mapped = CallState.established;
    } else if (state.state == CallStateEnum.ENDED ||
        state.state == CallStateEnum.FAILED) {
      mapped = CallState.terminated;
    } else if (state.state == CallStateEnum.CALL_INITIATION) {
      mapped = CallState.connecting;
    } else {
      mapped = CallState.connecting;
    }

    _callStateCtrl.add(CallStateEvent(callId: callId, state: mapped));

    if (mapped == CallState.terminated) {
      _calls.remove(callId);
    }

    // Emit media streams once the call is established.
    if (state.state == CallStateEnum.CONFIRMED ||
        state.state == CallStateEnum.ACCEPTED) {
      final local = call.localStream;
      final remote = call.remoteStream;
      if (local != null) _localStreamCtrl.add((callId, local));
      if (remote != null) _remoteStreamCtrl.add((callId, remote));
    }
  }

  void _onIncomingCall(String accountId, IncomingCall event) {
    final call = event.call;
    if (call == null) return;

    // Inbound calls always get a fresh ID.
    final callId = _generateCallId();
    _calls[callId] = _CallHandle(callId: callId, accountId: accountId)
      ..sipCall = call;

    _incomingCallCtrl.add(
      IncomingCallEvent(
        callId: callId,
        accountId: accountId,
        remoteUri: event.request?.from?.uri.toString() ?? '',
        displayName: event.request?.from?.display_name ?? '',
      ),
    );
  }

  // ─── Helpers ───────────────────────────────────────────────────────────────

  /// Find an existing call handle for [call], or claim the pending outbound
  /// slot, or allocate a new ID for an unexpected inbound event.
  String _resolveCallId(String accountId, Call call, CallState2 state) {
    // Check if we already track this Call object.
    for (final entry in _calls.entries) {
      if (entry.value.sipCall == call) return entry.key;
    }

    // First CALL_INITIATION for outbound: claim the pending slot.
    if (state.state == CallStateEnum.CALL_INITIATION) {
      final handle = _accounts[accountId];
      final pendingId = handle?.pendingOutboundCallId;
      if (pendingId != null) {
        handle!.pendingOutboundCallId = null;
        _calls[pendingId]!.sipCall = call;
        return pendingId;
      }
    }

    // Fallback: allocate a new ID.
    final id = _generateCallId();
    _calls[id] = _CallHandle(callId: id, accountId: accountId)..sipCall = call;
    return id;
  }

  static String _generateCallId() =>
      'call_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(9999)}';
}

// ─── Per-account SipUaHelperListener ─────────────────────────────────────────

class _AccountListener implements SipUaHelperListener {
  _AccountListener({required this.accountId, required this.engine});

  final String accountId;
  final WebrtcEngine engine;

  @override
  void registrationStateChanged(RegistrationState state) =>
      engine._onRegistrationState(accountId, state);

  @override
  void callStateChanged(Call call, CallState2 state) =>
      engine._onCallState(accountId, call, state);

  @override
  void incomingCall(IncomingCall event) =>
      engine._onIncomingCall(accountId, event);

  @override
  void onNewMessage(SIPMessageRequest msg) {}

  @override
  void onNewNotify(Notify ntf) {}

  @override
  void transportStateChanged(TransportState state) {}
}

// ─── Data holders ─────────────────────────────────────────────────────────────

class _AccountHandle {
  _AccountHandle({
    required this.accountId,
    required this.helper,
    required this.listener,
  });

  final String accountId;
  final SIPUAHelper helper;
  final _AccountListener listener;
  String? pendingOutboundCallId;
}

class _CallHandle {
  _CallHandle({required this.callId, required this.accountId});

  final String callId;
  final String accountId;
  Call? sipCall;
}
