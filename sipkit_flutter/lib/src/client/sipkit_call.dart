import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../errors.dart';
import '../licensing/entitlement.dart';
import '../models/call_direction.dart';
import '../models/call_state.dart';
import '../models/entitlement.dart';
import '../engine/sip_engine.dart';

/// Represents a single SIP call, inbound or outbound.
///
/// All media-level methods route through the [SipEngine] adapter seam.
/// Feature gating for call-level operations (video, DTMF, transfer) is
/// enforced here against the live [Entitlement] — [SipKitClient] also
/// pre-checks before creating the call, but this guard protects calls that
/// were established before a subsequent entitlement downgrade.
class SipKitCall {
  SipKitCall._({
    required this.id,
    required this.accountId,
    required this.remoteUri,
    required this.displayName,
    required this.direction,
    required SipEngine engine,
    required Entitlement Function() getEntitlement,
  })  : _engine = engine,
        _getEntitlement = getEntitlement,
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
  final Entitlement Function() _getEntitlement;
  final StreamController<CallState> _stateCtrl;

  late CallState _currentState;

  /// Local media stream — populated when the call is established.
  /// Attach to an [RTCVideoRenderer] for display in the UI.
  MediaStream? localStream;

  /// Remote media stream — populated once the remote side accepts.
  MediaStream? remoteStream;

  // ─── Public API ────────────────────────────────────────────────────────────

  /// Current call state as a broadcast stream.
  Stream<CallState> get state => _stateCtrl.stream;

  /// Snapshot of the current [CallState].
  CallState get currentState => _currentState;

  /// Answer an incoming call.
  ///
  /// Throws [StateError] if the call is not inbound or not ringing.
  /// Throws [NotEntitledError] if [video] is requested but not entitled.
  Future<void> answer({bool video = false}) async {
    if (direction != CallDirection.inbound) {
      throw StateError('Cannot answer an outbound call.');
    }
    if (_currentState != CallState.ringing) {
      throw StateError('Call is not ringing (state: $_currentState).');
    }
    if (video) _getEntitlement().requireFeature('video');
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
  ///
  /// Throws [NotEntitledError] if the `"dtmf"` feature is not entitled.
  void sendDtmf(String digits) {
    _getEntitlement().requireFeature('dtmf');
    _engine.sendDtmf(id, digits);
  }

  /// Blind-transfer this call to [targetUri].
  ///
  /// Throws [NotEntitledError] if the `"transfer"` feature is not entitled.
  Future<void> blindTransfer(String targetUri) async {
    _getEntitlement().requireFeature('transfer');
    await _engine.blindTransfer(id, targetUri);
  }

  /// Attended transfer: connect this call to [otherCall] and drop the local leg.
  ///
  /// Throws [NotEntitledError] if the `"transfer"` feature is not entitled.
  Future<void> attendedTransfer(SipKitCall otherCall) async {
    _getEntitlement().requireFeature('transfer');
    await _engine.attendedTransfer(id, otherCall.id);
  }

  /// Enable or disable the video track on an established call.
  ///
  /// Throws [NotEntitledError] if [enabled] is `true` and the `"video"`
  /// feature is not in the current entitlement — checked before the engine
  /// is called.
  Future<void> enableVideo(bool enabled) async {
    if (enabled) _getEntitlement().requireFeature('video');
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

  void attachLocalStream(MediaStream stream) {
    localStream = stream;
  }

  void attachRemoteStream(MediaStream stream) {
    remoteStream = stream;
  }

  /// Factory used internally by [SipKitClient].
  static SipKitCall create({
    required String id,
    required String accountId,
    required String remoteUri,
    required String displayName,
    required CallDirection direction,
    required SipEngine engine,
    required Entitlement Function() getEntitlement,
  }) =>
      SipKitCall._(
        id: id,
        accountId: accountId,
        remoteUri: remoteUri,
        displayName: displayName,
        direction: direction,
        engine: engine,
        getEntitlement: getEntitlement,
      );
}
