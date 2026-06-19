import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../errors.dart';
import '../models/call_direction.dart';
import '../models/call_state.dart';
import '../engine/sip_engine.dart';

/// Represents a single SIP call, inbound or outbound.
///
/// All media-level methods route through the [SipEngine] adapter seam.
/// Feature gating (video, transfer) is enforced by [SipKitClient] before
/// these methods are called — [SipKitCall] itself does not re-check entitlements.
class SipKitCall {
  SipKitCall._({
    required this.id,
    required this.accountId,
    required this.remoteUri,
    required this.displayName,
    required this.direction,
    required SipEngine engine,
    required String entitlementToken,
  })  : _engine = engine,
        _entitlementToken = entitlementToken,
        _stateCtrl = StreamController<CallState>.broadcast() {
    _currentState = direction == CallDirection.outbound
        ? CallState.connecting
        : CallState.ringing;
    _stateCtrl.add(_currentState);
  }

  /// Unique call identifier (stable for the lifetime of the call).
  final String id;

  /// ID of the [SipKitAccount] that owns this call.
  final String accountId;

  /// Remote party SIP URI.
  final String remoteUri;

  /// Remote party display name (may be empty).
  final String displayName;

  /// Whether this call was placed by the local user or received.
  final CallDirection direction;

  final SipEngine _engine;
  final String _entitlementToken;
  final StreamController<CallState> _stateCtrl;

  late CallState _currentState;

  /// Video renderers — populated when a video stream is negotiated.
  RTCVideoRenderer? localRenderer;
  RTCVideoRenderer? remoteRenderer;

  // ─── Public API ────────────────────────────────────────────────────────────

  /// Current call state as a broadcast stream.
  Stream<CallState> get state => _stateCtrl.stream;

  /// Snapshot of the current [CallState].
  CallState get currentState => _currentState;

  /// Answer an incoming call.  Throws [StateError] if the call is not inbound
  /// or is not in [CallState.ringing].
  Future<void> answer({bool video = false}) async {
    if (direction != CallDirection.inbound) {
      throw StateError('Cannot answer an outbound call.');
    }
    if (_currentState != CallState.ringing) {
      throw StateError('Call is not ringing (state: $_currentState).');
    }
    await _engine.answer(id, video: video);
  }

  /// Terminate the call regardless of direction or state.
  Future<void> hangup() async {
    await _engine.hangup(id);
  }

  /// Put the call on hold.
  Future<void> hold() async {
    await _engine.hold(id);
  }

  /// Resume a held call.
  Future<void> unhold() async {
    await _engine.unhold(id);
  }

  /// Mute or unmute the local microphone.
  void mute(bool muted) {
    _engine.mute(id, muted: muted);
  }

  /// Send one or more DTMF digits.
  void sendDtmf(String digits) {
    _engine.sendDtmf(id, digits);
  }

  /// Blind-transfer this call to [targetUri].
  Future<void> blindTransfer(String targetUri) async {
    await _engine.blindTransfer(id, targetUri);
  }

  /// Attended transfer: connect this call to [otherCall] and drop the local
  /// leg.
  Future<void> attendedTransfer(SipKitCall otherCall) async {
    await _engine.attendedTransfer(id, otherCall.id);
  }

  /// Enable or disable the video track.
  ///
  /// Throws [NotEntitledError] if the `"video"` feature is not entitled — this
  /// check is applied by [SipKitClient] before delegating here.
  Future<void> enableVideo(bool enabled) async {
    await _engine.enableVideo(id, enabled: enabled);
  }

  // ─── Internal helpers used by SipKitClient ─────────────────────────────────

  void updateState(CallState newState) {
    if (_currentState == newState) return;
    _currentState = newState;
    _stateCtrl.add(newState);
    if (newState == CallState.terminated) {
      _stateCtrl.close();
    }
  }

  void attachLocalStream(RTCVideoRenderer renderer) {
    localRenderer = renderer;
  }

  void attachRemoteStream(RTCVideoRenderer renderer) {
    remoteRenderer = renderer;
  }

  /// Factory used internally by [SipKitClient].
  static SipKitCall create({
    required String id,
    required String accountId,
    required String remoteUri,
    required String displayName,
    required CallDirection direction,
    required SipEngine engine,
    required String entitlementToken,
  }) =>
      SipKitCall._(
        id: id,
        accountId: accountId,
        remoteUri: remoteUri,
        displayName: displayName,
        direction: direction,
        engine: engine,
        entitlementToken: entitlementToken,
      );
}
