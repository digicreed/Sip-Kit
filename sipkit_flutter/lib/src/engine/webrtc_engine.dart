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
/// Internal [sip_ua] types ([SIPUAHelper], [Call], [RegistrationState]) do
/// **not** leak through the [SipEngine] interface or the public SipKit API.
class WebrtcEngine extends SipEngine implements SipUaHelperListener {
  // One SIPUAHelper per registered account to support multi-account.
  final Map<String, _AccountHandle> _accounts = {};
  final Map<String, _CallHandle> _calls = {};

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
      String accountId, SipKitAccountConfig config) async {
    final helper = SIPUAHelper();
    final handle = _AccountHandle(accountId: accountId, helper: helper);
    _accounts[accountId] = handle;

    helper.addSipUaHelperListener(this);

    final settings = UaSettings()
      ..webSocketUrl = config.wsUrl
      ..webSocketSettings.allowBadCertificate = true
      ..uri = 'sip:${config.username}@${config.domain}'
      ..authorizationUser = config.authUsername ?? config.username
      ..password = config.password
      ..displayName = config.displayName ?? config.username
      ..userAgent = config.userAgent ?? 'SipKit-Flutter/0.1.0'
      ..dtmfMode = DtmfMode.RFC2833
      ..registerExpires = config.registrationExpiry
      ..iceServers = config.iceServers
          .map((s) => RTCIceServer(
                urls: s.url,
                username: s.username,
                credential: s.credential,
              ))
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

    final callId = _generateCallId();
    final mediaConstraints = <String, dynamic>{
      'audio': true,
      'video': video,
    };

    handle.helper.call(target,
        mediaConstraints: mediaConstraints, voiceonly: !video);

    _calls[callId] = _CallHandle(callId: callId, accountId: accountId);
    return callId;
  }

  @override
  Future<void> answer(String callId, {bool video = false}) async {
    final call = _calls[callId]?.sipCall;
    if (call == null) return;
    final options = <String, dynamic>{
      'mediaConstraints': {'audio': true, 'video': video}
    };
    call.answer(options);
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

  // ─── SipUaHelperListener ───────────────────────────────────────────────────

  @override
  void registrationStateChanged(RegistrationState state) {
    // Best-effort match: iterate accounts to find one with this helper.
    String? accountId;
    for (final e in _accounts.entries) {
      accountId = e.key;
      break;
    }
    if (accountId == null) return;

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

    _accountStatusCtrl.add(AccountStatusEvent(
        accountId: accountId, status: status, reason: state.cause));
  }

  @override
  void callStateChanged(Call call, CallState2 state) {
    final callId = _findOrRegisterCall(call);

    // Skip mute/unmute notifications — they don't change CallState.
    if (state.state == CallStateEnum.MUTED ||
        state.state == CallStateEnum.UNMUTED) {
      return;
    }

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
      _calls.remove(callId);
    } else if (state.state == CallStateEnum.CALL_INITIATION) {
      mapped = CallState.connecting;
    } else {
      mapped = CallState.connecting;
    }

    _callStateCtrl.add(CallStateEvent(callId: callId, state: mapped));

    // Emit media streams when the call is established.
    if (state.state == CallStateEnum.CONFIRMED ||
        state.state == CallStateEnum.ACCEPTED) {
      final local = call.localStream;
      final remote = call.remoteStream;
      if (local != null) _localStreamCtrl.add((callId, local));
      if (remote != null) _remoteStreamCtrl.add((callId, remote));
    }
  }

  @override
  void onNewMessage(SIPMessageRequest msg) {}

  @override
  void onNewNotify(Notify ntf) {}

  @override
  void transportStateChanged(TransportState state) {}

  @override
  void incomingCall(IncomingCall event) {
    final callId = _findOrRegisterCall(event.call!,
        remoteUri: event.request?.from?.uri.toString());

    String? accountId;
    for (final e in _accounts.entries) {
      accountId = e.key;
      break;
    }

    _incomingCallCtrl.add(IncomingCallEvent(
      callId: callId,
      accountId: accountId ?? '',
      remoteUri: event.request?.from?.uri.toString() ?? '',
      displayName: event.request?.from?.display_name ?? '',
    ));
  }

  // ─── Helpers ───────────────────────────────────────────────────────────────

  String _findOrRegisterCall(Call call, {String? remoteUri}) {
    for (final e in _calls.entries) {
      if (e.value.sipCall == call) return e.key;
    }
    final id = _generateCallId();
    _calls[id] = _CallHandle(callId: id, accountId: '')..sipCall = call;
    return id;
  }

  static String _generateCallId() =>
      'call_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(9999)}';
}

class _AccountHandle {
  _AccountHandle({required this.accountId, required this.helper});
  final String accountId;
  final SIPUAHelper helper;
}

class _CallHandle {
  _CallHandle({required this.callId, required this.accountId});
  final String callId;
  final String accountId;
  Call? sipCall;
}
