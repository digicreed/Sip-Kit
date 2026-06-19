import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sipkit_flutter/sipkit_flutter.dart';

const _kLicenseKeyStorageKey = 'demo_license_key';
const _kBaseUrlStorageKey = 'demo_base_url';
const _kAccountsStorageKey = 'demo_saved_accounts';

/// Central ChangeNotifier that owns a [SipKitClient] and drives all screens.
class SoftphoneState extends ChangeNotifier {
  SoftphoneState() {
    _init();
  }

  // ─── Engine selection ──────────────────────────────────────────────────────
  bool useWebrtcEngine = true;
  SipEngine _buildEngine() =>
      useWebrtcEngine ? WebrtcEngine() : PjsipEngine();

  late SipKitClient _client;
  final _storage = const FlutterSecureStorage();

  // ─── State exposed to UI ───────────────────────────────────────────────────
  ActivationState activationState = ActivationState.unactivated;
  Entitlement? entitlement;
  String? activationError;

  List<SipKitAccount> get accounts => _client.accounts;
  List<SipKitCall> get calls => _client.calls;

  final _incomingCallQueue = <SipKitCall>[];
  List<SipKitCall> get incomingCalls => List.unmodifiable(_incomingCallQueue);

  final log = <String>[];

  // ─── Init ──────────────────────────────────────────────────────────────────
  void _init() {
    _client = SipKitClient(engine: _buildEngine());
    _subscribeClient();
    // Restore persisted session asynchronously; UI renders immediately with
    // the unactivated state and updates once restoration completes.
    _restoreSession();
  }

  /// Attempts to re-activate using stored credentials and, if activation
  /// succeeds, re-adds every saved account (registering each one).
  Future<void> _restoreSession() async {
    final creds = await loadSavedCredentials();
    final licenseKey = creds['licenseKey'];
    final baseUrl = creds['baseUrl'];
    if (licenseKey == null || baseUrl == null) return;

    try {
      await activate(licenseKey: licenseKey, baseUrl: baseUrl);
    } catch (_) {
      // Silent: if activation fails the UI already shows the activate screen.
      return;
    }

    if (activationState != ActivationState.active &&
        activationState != ActivationState.expired) {
      return;
    }

    // Re-add persisted SIP accounts.
    final configs = await loadSavedAccountConfigs();
    for (final config in configs) {
      try {
        await addAccount(config);
      } catch (_) {
        // Skip individual accounts that fail (e.g. entitlement limit changed).
        _addLog(
            'Could not restore account ${config.username}@${config.domain}');
      }
    }
    if (configs.isNotEmpty) {
      _addLog('Session restored — ${configs.length} account(s) reconnected');
      notifyListeners();
    }
  }

  StreamSubscription<ActivationState>? _activationSub;
  StreamSubscription<SipKitCall>? _incomingCallSub;

  void _subscribeClient() {
    _activationSub = _client.activationState.listen((s) {
      activationState = s;
      _addLog('Activation state → $s');
      notifyListeners();
    });
    _incomingCallSub = _client.incomingCalls.listen((call) {
      _incomingCallQueue.add(call);
      _addLog('Incoming call from ${call.remoteUri}');
      call.state.listen((s) {
        if (s == CallState.terminated) {
          _incomingCallQueue.remove(call);
        }
        _addLog('Call ${call.id.substring(0, 8)} → $s');
        notifyListeners();
      });
      notifyListeners();
    });
  }

  // ─── Activation ────────────────────────────────────────────────────────────
  Future<void> activate({
    required String licenseKey,
    required String baseUrl,
  }) async {
    activationError = null;
    notifyListeners();
    try {
      final ent = await _client.activate(
        licenseKey: licenseKey,
        baseUrl: baseUrl,
        appId: 'com.sipkit.example',
        deviceId: 'demo-device-01',
      );
      entitlement = ent;
      activationState = ActivationState.active;
      // Persist for next launch.
      await _storage.write(key: _kLicenseKeyStorageKey, value: licenseKey);
      await _storage.write(key: _kBaseUrlStorageKey, value: baseUrl);
      _addLog('Activated — expires ${ent.expiresAt.toLocal()}');
    } on ActivationError catch (e) {
      activationError = e.message;
      activationState = ActivationState.locked;
      _addLog('Activation failed: ${e.message}');
    } on NetworkError catch (e) {
      activationError = 'Network error: ${e.message}';
      _addLog('Network error during activation: ${e.message}');
    } catch (e) {
      activationError = e.toString();
    }
    notifyListeners();
  }

  Future<Map<String, String?>> loadSavedCredentials() async {
    final key = await _storage.read(key: _kLicenseKeyStorageKey);
    final url = await _storage.read(key: _kBaseUrlStorageKey);
    return {'licenseKey': key, 'baseUrl': url};
  }

  // ─── Engine toggle ─────────────────────────────────────────────────────────
  Future<void> toggleEngine() async {
    await _disposeClient();
    useWebrtcEngine = !useWebrtcEngine;
    _client = SipKitClient(engine: _buildEngine());
    activationState = ActivationState.unactivated;
    entitlement = null;
    _incomingCallQueue.clear();
    _subscribeClient();
    _addLog(
        'Engine switched to ${useWebrtcEngine ? "WebrtcEngine" : "PjsipEngine"}');
    notifyListeners();
  }

  // ─── Accounts ──────────────────────────────────────────────────────────────

  /// Persist a config so it can be restored on next launch.
  Future<void> saveAccount(SipKitAccountConfig config) async {
    final existing = await _loadSavedAccountConfigs();
    final updated = existing
        .where((c) =>
            c['username'] != config.username || c['domain'] != config.domain)
        .toList();
    updated.add(_configToMap(config));
    await _storage.write(
        key: _kAccountsStorageKey, value: jsonEncode(updated));
  }

  /// Return all account configs that were persisted across sessions.
  Future<List<SipKitAccountConfig>> loadSavedAccountConfigs() async {
    return (await _loadSavedAccountConfigs())
        .map(_configFromMap)
        .whereType<SipKitAccountConfig>()
        .toList();
  }

  Future<List<Map<String, dynamic>>> _loadSavedAccountConfigs() async {
    final raw = await _storage.read(key: _kAccountsStorageKey);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List)
          .cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  static Map<String, dynamic> _configToMap(SipKitAccountConfig c) => {
        'username': c.username,
        'password': c.password,
        'domain': c.domain,
        'wsUrl': c.wsUrl,
        'displayName': c.displayName,
        'authUsername': c.authUsername,
        'registerOnAdd': c.registerOnAdd,
        'registrationExpiry': c.registrationExpiry,
      };

  static SipKitAccountConfig? _configFromMap(Map<String, dynamic> m) {
    try {
      return SipKitAccountConfig(
        username: m['username'] as String,
        password: m['password'] as String,
        domain: m['domain'] as String,
        wsUrl: m['wsUrl'] as String,
        displayName: m['displayName'] as String?,
        authUsername: m['authUsername'] as String?,
        registerOnAdd: m['registerOnAdd'] as bool? ?? true,
        registrationExpiry: m['registrationExpiry'] as int? ?? 600,
      );
    } catch (_) {
      return null;
    }
  }

  Future<SipKitAccount?> addAccount(SipKitAccountConfig config) async {
    try {
      final acc = await _client.addAccount(config);
      _addLog('Account added: ${config.username}@${config.domain}');
      // Persist config for next launch.
      await saveAccount(config);
      acc.status.listen((s) {
        _addLog('Account ${acc.id.substring(0, 6)} → $s');
        notifyListeners();
      });
      notifyListeners();
      return acc;
    } on NotEntitledError catch (e) {
      _addLog('Cannot add account: ${e.message}');
      rethrow;
    }
  }

  Future<void> removeAccount(String accountId) async {
    await _client.removeAccount(accountId);
    _addLog('Account $accountId removed');
    notifyListeners();
  }

  // ─── Calls ─────────────────────────────────────────────────────────────────
  Future<SipKitCall?> makeCall(
    String accountId,
    String target, {
    bool video = false,
  }) async {
    try {
      final call = await _client.makeCall(accountId, target, video: video);
      call.state.listen((s) {
        _addLog('Call ${call.id.substring(0, 8)} → $s');
        notifyListeners();
      });
      _addLog('Calling $target...');
      notifyListeners();
      return call;
    } on NotEntitledError catch (e) {
      _addLog('Not entitled: ${e.message}');
      rethrow;
    }
  }

  Future<void> mergeActiveCalls() async {
    final ids = _client.calls.map((c) => c.id).toList();
    if (ids.length < 2) return;
    try {
      final conf = await _client.mergeCalls(ids);
      _addLog(
          'Conference ${conf.id} created with ${conf.callIds.length} calls');
      notifyListeners();
    } on ConferenceNotEntitledError catch (e) {
      _addLog('Conference not entitled: ${e.message}');
    }
  }

  // ─── Log ───────────────────────────────────────────────────────────────────
  void _addLog(String msg) {
    final ts = DateTime.now().toIso8601String().substring(11, 19);
    log.insert(0, '[$ts] $msg');
    if (log.length > 100) log.removeLast();
    notifyListeners();
  }

  Future<void> _disposeClient() async {
    await _activationSub?.cancel();
    await _incomingCallSub?.cancel();
    await _client.dispose();
  }

  // Override must be `void` to match ChangeNotifier.dispose().
  @override
  void dispose() {
    _disposeClient(); // fire-and-forget; GC will clean up
    super.dispose();
  }
}
