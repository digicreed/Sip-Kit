import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../engine/sip_engine.dart';
import '../engine/webrtc_engine.dart';
import '../errors.dart';
import '../licensing/activation.dart';
import '../licensing/entitlement.dart';
import '../licensing/entitlement_cache.dart';
import '../models/account_config.dart';
import '../models/activation_state.dart';
import '../models/call_direction.dart';
import '../models/call_state.dart';
import '../models/conference.dart';
import '../models/entitlement.dart';
import 'sipkit_account.dart';
import 'sipkit_call.dart';

/// Top-level SipKit manager.
///
/// All SIP operations (account registration, outbound calls) are gated behind
/// a valid entitlement JWT issued by the SipKit licensing backend.
///
/// Activation state lifecycle:
/// ```
/// unactivated → activating → active → expired (grace) → locked
/// ```
///
/// During [ActivationState.expired] the SDK is still functional — the offline
/// grace window (default 72 h) keeps SIP operations alive while a background
/// refresh is attempted.  Only [ActivationState.locked] blocks SIP.
///
/// Quick-start:
/// ```dart
/// final client = SipKitClient();
/// await client.activate(
///   licenseKey: 'pk_live_xxx',
///   baseUrl:    'https://license.mydomain.com',
///   appId:      'com.provider.softphone',
/// );
/// final account = await client.addAccount(SipKitAccountConfig(
///   username: 'alice', password: 'secret', domain: 'pbx.provider.com',
///   wsUrl: 'wss://pbx.provider.com:8089/ws',
/// ));
/// final call = await client.makeCall(account.id, 'sip:bob@pbx.provider.com');
/// ```
class SipKitClient {
  SipKitClient({
    SipEngine? engine,
    EntitlementCache? cache,
    EntitlementVerifier? verifier,
    ActivationService? activationService,
  })  : _engine = engine ?? WebrtcEngine(),
        _cache = cache ?? EntitlementCache(),
        _verifier = verifier ?? EntitlementVerifier() {
    final c = _cache;
    final v = _verifier;
    _activationService = activationService ??
        ActivationService(cache: c, verifier: v);
  }

  final SipEngine _engine;
  final EntitlementCache _cache;
  final EntitlementVerifier _verifier;
  late final ActivationService _activationService;

  // ─── State ─────────────────────────────────────────────────────────────────
  final _activationStateCtrl =
      StreamController<ActivationState>.broadcast();
  ActivationState _activationState = ActivationState.unactivated;

  Entitlement? _entitlement;
  String _currentBaseUrl = '';
  String _currentDeviceId = '';

  final _accounts = <String, SipKitAccount>{};
  final _calls = <String, SipKitCall>{};
  final _incomingCallCtrl = StreamController<SipKitCall>.broadcast();

  StreamSubscription<IncomingCallEvent>? _incomingCallSub;
  StreamSubscription<CallStateEvent>? _callStateSub;
  StreamSubscription<AccountStatusEvent>? _accountStatusSub;
  StreamSubscription<(String, MediaStream)>? _localStreamSub;
  StreamSubscription<(String, MediaStream)>? _remoteStreamSub;

  bool _engineInitialised = false;

  // ─── Public streams + state ────────────────────────────────────────────────

  /// Broadcasts [ActivationState] transitions.
  Stream<ActivationState> get activationState => _activationStateCtrl.stream;

  /// Current activation state snapshot.
  ActivationState get currentActivationState => _activationState;

  /// The current decoded entitlement, or `null` if not activated.
  Entitlement? get entitlement => _entitlement;

  /// All currently registered accounts.
  List<SipKitAccount> get accounts => List.unmodifiable(_accounts.values);

  /// All active calls (excluding terminated).
  List<SipKitCall> get calls => List.unmodifiable(
      _calls.values.where((c) => c.currentState != CallState.terminated));

  /// Broadcast stream of incoming [SipKitCall]s.
  Stream<SipKitCall> get incomingCalls => _incomingCallCtrl.stream;

  // ─── Activation ────────────────────────────────────────────────────────────

  /// Activate the SDK using the provider's [licenseKey].
  ///
  /// Contacts the SipKit licensing backend to exchange the key for a signed
  /// entitlement JWT, then initialises the SIP engine.  The SDK is unusable
  /// until this succeeds.
  ///
  /// If a cached entitlement is still within the 72-hour grace window, the
  /// SDK activates offline immediately and schedules a background refresh.
  ///
  /// Throws [ActivationError] on invalid/revoked/expired keys.
  /// Throws [NetworkError] on unreachable backend.
  Future<Entitlement> activate({
    required String licenseKey,
    required String baseUrl,
    String? appId,
    String? deviceId,
  }) async {
    _setActivationState(ActivationState.activating);

    final resolvedAppId = appId ?? 'unknown';
    final resolvedDeviceId = deviceId ?? _generateDeviceId();
    _currentDeviceId = resolvedDeviceId;
    _currentBaseUrl = baseUrl;

    // Try offline cache first (supports 72h grace window).
    final cached = await _cache.loadWithGrace();

    try {
      final ent = await _activationService.activate(
        licenseKey: licenseKey,
        baseUrl: baseUrl,
        appId: resolvedAppId,
        deviceId: resolvedDeviceId,
        onRefreshed: _onAutoRefresh,
        onExpired: _onAutoRefreshFailed,
      );
      _applyEntitlement(ent, baseUrl, ActivationState.active);
      await _ensureEngineInit();
      return ent;
    } catch (e) {
      // Fall back to grace window on any network failure.
      if (cached != null) {
        final graceState = cached.isExpiredButWithinGrace
            ? ActivationState.expired
            : ActivationState.active;
        _applyEntitlement(cached.entitlement, baseUrl, graceState);
        await _ensureEngineInit();
        return cached.entitlement;
      }
      _setActivationState(ActivationState.locked);
      rethrow;
    }
  }

  // ─── Accounts ──────────────────────────────────────────────────────────────

  /// Add and optionally register a SIP account.
  ///
  /// Throws [NotEntitledError] if [Entitlement.maxAccounts] would be exceeded.
  /// Throws [ActivationError] if the SDK is locked (not active or in grace).
  Future<SipKitAccount> addAccount(SipKitAccountConfig config) async {
    _requireNotLocked();
    _entitlement!.requireAccountSlot(_accounts.length);

    final id = _generateId('acc');
    final account =
        SipKitAccount.create(id: id, config: config, engine: _engine);
    _accounts[id] = account;

    if (config.registerOnAdd) {
      await _engine.registerAccount(id, config);
    }
    return account;
  }

  /// Remove an account and unregister it from the registrar.
  Future<void> removeAccount(String accountId) async {
    final account = _accounts.remove(accountId);
    if (account == null) return;
    await _engine.unregister(accountId);
    account.dispose();
  }

  // ─── Calls ─────────────────────────────────────────────────────────────────

  /// Place an outbound call from [accountId] to [target] (SIP URI or number).
  ///
  /// Throws [NotEntitledError] if concurrent call limit is reached or if
  /// [video] is requested without the `"video"` feature.
  /// Throws [ActivationError] if the SDK is locked.
  Future<SipKitCall> makeCall(
    String accountId,
    String target, {
    bool video = false,
  }) async {
    _requireNotLocked();
    if (video) _entitlement!.requireFeature('video');
    _entitlement!.requireCallSlot(_activeCalls);

    final callId = await _engine.makeCall(accountId, target, video: video);
    final call = _buildCall(
      id: callId,
      accountId: accountId,
      remoteUri: target,
      displayName: target,
      direction: CallDirection.outbound,
    );
    _calls[callId] = call;
    return call;
  }

  /// Merge two active calls into a conference.
  ///
  /// Throws [ConferenceNotEntitledError] if the `"conference"` feature is not
  /// in the entitlement.
  Future<SipKitConference> mergeCalls(List<String> callIds) async {
    _requireNotLocked();
    _entitlement!.requireFeature('conference');

    if (callIds.length < 2) {
      throw ArgumentError('mergeCalls requires at least 2 call IDs.');
    }
    for (final id in callIds.skip(1)) {
      await _calls[id]?.hold();
    }
    return SipKitConference(id: _generateId('conf'), callIds: callIds);
  }

  // ─── Dispose ───────────────────────────────────────────────────────────────

  Future<void> dispose() async {
    _activationService.cancelRefresh();
    await _incomingCallSub?.cancel();
    await _callStateSub?.cancel();
    await _accountStatusSub?.cancel();
    await _localStreamSub?.cancel();
    await _remoteStreamSub?.cancel();

    for (final a in _accounts.values) {
      a.dispose();
    }
    _accounts.clear();
    _calls.clear();

    if (_engineInitialised) {
      await _engine.dispose();
      _engineInitialised = false;
    }

    await _activationStateCtrl.close();
    await _incomingCallCtrl.close();
  }

  // ─── Internal ──────────────────────────────────────────────────────────────

  void _setActivationState(ActivationState state) {
    if (_activationState == state) return;
    _activationState = state;
    _activationStateCtrl.add(state);
  }

  void _applyEntitlement(
      Entitlement ent, String baseUrl, ActivationState state) {
    _entitlement = ent;
    _currentBaseUrl = baseUrl;
    _setActivationState(state);
  }

  void _onAutoRefresh(Entitlement newEnt) {
    _entitlement = newEnt;
    _setActivationState(ActivationState.active);
  }

  void _onAutoRefreshFailed() {
    // Transition to `expired` — SIP keeps working through the grace window.
    // Only when loadWithGrace() returns null do we move to `locked`.
    _setActivationState(ActivationState.expired);
    _cache.loadWithGrace().then((cached) {
      if (cached == null && _activationState == ActivationState.expired) {
        _setActivationState(ActivationState.locked);
      }
    });
  }

  Future<void> _ensureEngineInit() async {
    if (_engineInitialised) return;
    await _engine.init();
    _engineInitialised = true;
    _subscribeEngineEvents();
  }

  void _subscribeEngineEvents() {
    _incomingCallSub = _engine.incomingCall.listen((event) {
      final call = _buildCall(
        id: event.callId,
        accountId: event.accountId,
        remoteUri: event.remoteUri,
        displayName: event.displayName,
        direction: CallDirection.inbound,
      );
      _calls[event.callId] = call;
      _incomingCallCtrl.add(call);
    });

    _callStateSub = _engine.callStateChanged.listen((event) {
      _calls[event.callId]?.updateState(event.state);
      if (event.state == CallState.terminated) {
        _calls.remove(event.callId);
      }
    });

    _accountStatusSub = _engine.accountStatusChanged.listen((event) {
      _accounts[event.accountId]
          ?.updateStatus(event.status, reason: event.reason);
    });

    // Wire media streams → SipKitCall renderers.
    _localStreamSub = _engine.localStream.listen((event) {
      final (callId, stream) = event;
      _calls[callId]?.attachLocalStream(stream);
    });

    _remoteStreamSub = _engine.remoteStream.listen((event) {
      final (callId, stream) = event;
      _calls[callId]?.attachRemoteStream(stream);
    });
  }

  SipKitCall _buildCall({
    required String id,
    required String accountId,
    required String remoteUri,
    required String displayName,
    required CallDirection direction,
  }) =>
      SipKitCall.create(
        id: id,
        accountId: accountId,
        remoteUri: remoteUri,
        displayName: displayName,
        direction: direction,
        engine: _engine,
        // Live getter — reflects the current (possibly refreshed) entitlement.
        getEntitlement: () {
          if (_entitlement == null) {
            throw const ActivationError(
                'SipKit is not activated. Call activate() first.');
          }
          return _entitlement!;
        },
      );

  /// Blocks if [ActivationState.locked]; permits [active] and [expired] (grace).
  void _requireNotLocked() {
    if (_activationState == ActivationState.locked) {
      throw const ActivationError(
          'SipKit is locked — the entitlement has expired beyond the grace window. '
          'Call activate() again to reactivate.');
    }
    if (_activationState == ActivationState.unactivated ||
        _activationState == ActivationState.activating) {
      throw ActivationError(
          'SipKit is not yet activated (state: $_activationState). '
          'Call activate() first.');
    }
    if (_entitlement == null) {
      throw const ActivationError(
          'No entitlement loaded. Call activate() first.');
    }
  }

  int get _activeCalls => _calls.values
      .where((c) => c.currentState != CallState.terminated)
      .length;

  static String _generateId(String prefix) =>
      '${prefix}_${DateTime.now().millisecondsSinceEpoch}';

  static String _generateDeviceId() =>
      'device_${DateTime.now().millisecondsSinceEpoch}';
}
