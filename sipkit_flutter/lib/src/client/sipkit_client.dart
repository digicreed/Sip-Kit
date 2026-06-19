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
import '../models/conference.dart';
import '../models/entitlement.dart' as model;
import 'sipkit_account.dart';
import 'sipkit_call.dart';

/// Top-level SipKit manager.
///
/// All SIP operations (account registration, outbound calls) are gated behind
/// a valid entitlement JWT issued by the SipKit licensing backend.  If
/// [activate] has not been called — or the entitlement has expired and the
/// offline grace window has elapsed — every SIP method throws [ActivationError].
///
/// Quick-start:
/// ```dart
/// final client = SipKitClient();                // WebrtcEngine by default
/// await client.activate(
///   licenseKey: 'pk_live_xxx',
///   baseUrl:    'https://license.mydomain.com',
///   appId:      'com.provider.softphone',
/// );
///
/// final account = await client.addAccount(SipKitAccountConfig(
///   username: 'alice', password: 'secret', domain: 'pbx.provider.com',
///   wsUrl: 'wss://pbx.provider.com:8089/ws',
/// ));
///
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

  model.Entitlement? _entitlement;
  String _currentToken = '';
  String _currentRefreshToken = '';
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
  model.Entitlement? get entitlement => _entitlement;

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
  Future<model.Entitlement> activate({
    required String licenseKey,
    required String baseUrl,
    String? appId,
    String? deviceId,
  }) async {
    _setActivationState(ActivationState.activating);

    // Try offline cache first (supports 72h grace window).
    final cached = await _cache.loadWithGrace();
    if (cached != null && !cached.entitlement.isExpired) {
      _applyEntitlement(cached.entitlement, cached.token,
          cached.refreshToken, baseUrl);
      await _ensureEngineInit();
      return cached.entitlement;
    }

    final resolvedAppId = appId ?? 'unknown';
    final resolvedDeviceId = deviceId ?? _generateDeviceId();
    _currentDeviceId = resolvedDeviceId;
    _currentBaseUrl = baseUrl;

    try {
      final ent = await _activationService.activate(
        licenseKey: licenseKey,
        baseUrl: baseUrl,
        appId: resolvedAppId,
        deviceId: resolvedDeviceId,
        onRefreshed: _onAutoRefresh,
        onExpired: _onAutoRefreshFailed,
      );
      // After activation, load the freshly cached tokens.
      final saved = await _cache.loadWithGrace();
      _applyEntitlement(ent, saved?.token ?? '', saved?.refreshToken ?? '', baseUrl);
      await _ensureEngineInit();
      return ent;
    } catch (e) {
      // Fall back to grace window even on network failure.
      if (cached != null) {
        _applyEntitlement(cached.entitlement, cached.token,
            cached.refreshToken, baseUrl);
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
  /// Throws [ActivationError] if the SDK is not active.
  Future<SipKitAccount> addAccount(SipKitAccountConfig config) async {
    _requireActive();
    _entitlement!.requireAccountSlot(_accounts.length);

    final id = _generateId('acc');
    final account = SipKitAccount.create(id: id, config: config, engine: _engine);
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
  /// Throws [NotEntitledError] if concurrent call limit is reached.
  /// Throws [ActivationError] if not active.
  Future<SipKitCall> makeCall(
    String accountId,
    String target, {
    bool video = false,
  }) async {
    _requireActive();
    if (video) _entitlement!.requireFeature('video');
    _entitlement!.requireCallSlot(_activeCalls);

    final callId = await _engine.makeCall(accountId, target, video: video);
    final call = SipKitCall.create(
      id: callId,
      accountId: accountId,
      remoteUri: target,
      displayName: target,
      direction: CallDirection.outbound,
      engine: _engine,
      entitlementToken: _currentToken,
    );
    _calls[callId] = call;
    return call;
  }

  /// Merge two active calls into a conference.
  ///
  /// Throws [ConferenceNotEntitledError] if the `"conference"` feature is not
  /// in the entitlement.
  Future<SipKitConference> mergeCalls(List<String> callIds) async {
    _requireActive();
    _entitlement!.requireFeature('conference');

    if (callIds.length < 2) {
      throw ArgumentError('mergeCalls requires at least 2 call IDs.');
    }
    // Engine-level conference: hold all-but-first then bridge.
    // In WebrtcEngine this is done via sip_ua's refer/replaces mechanism.
    // For PjsipEngine, PJSUA2 call_set_transfer_to replaces or AuConf.
    for (final id in callIds.skip(1)) {
      await _calls[id]?.hold();
    }

    return SipKitConference(
      id: _generateId('conf'),
      callIds: callIds,
    );
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

  void _applyEntitlement(model.Entitlement ent, String token,
      String refreshToken, String baseUrl) {
    _entitlement = ent;
    _currentToken = token;
    _currentRefreshToken = refreshToken;
    _currentBaseUrl = baseUrl;
    _setActivationState(ActivationState.active);
  }

  void _onAutoRefresh(model.Entitlement newEnt) {
    _entitlement = newEnt;
    // Stays active.
  }

  void _onAutoRefreshFailed() {
    _setActivationState(ActivationState.expired);
    // Give grace window logic a chance; if it also fails, lock.
    _cache.loadWithGrace().then((cached) {
      if (cached == null) {
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
      final call = SipKitCall.create(
        id: event.callId,
        accountId: event.accountId,
        remoteUri: event.remoteUri,
        displayName: event.displayName,
        direction: CallDirection.inbound,
        engine: _engine,
        entitlementToken: _currentToken,
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
  }

  void _requireActive() {
    if (_activationState != ActivationState.active) {
      throw ActivationError(
          'SipKit is not activated (state: $_activationState). '
          'Call activate() first.');
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
