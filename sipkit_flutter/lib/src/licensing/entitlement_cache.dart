import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/entitlement.dart';
import 'entitlement.dart';

const _kTokenKey = 'sipkit_entitlement_token';
const _kRefreshTokenKey = 'sipkit_refresh_token';
const _kBaseUrlKey = 'sipkit_base_url';

/// Persists the entitlement JWT and refresh token in [FlutterSecureStorage] so
/// the SDK can operate within the offline grace window when the network is
/// unavailable.
///
/// Offline grace:
///   If the stored token is expired but within [graceWindow] of [Entitlement.expiresAt],
///   [loadWithGrace] returns it as valid so SIP operations continue.  Once the
///   grace window elapses the token is discarded and the SDK transitions to
///   [ActivationState.locked].
class EntitlementCache {
  EntitlementCache({
    Duration graceWindow = const Duration(hours: 72),
    FlutterSecureStorage? storage,
    EntitlementVerifier? verifier,
  })  : _graceWindow = graceWindow,
        _storage = storage ?? const FlutterSecureStorage(),
        _verifier = verifier ?? EntitlementVerifier();

  final Duration _graceWindow;
  final FlutterSecureStorage _storage;
  final EntitlementVerifier _verifier;

  /// Persist [token] and [refreshToken] to secure storage.
  Future<void> save({
    required String token,
    required String refreshToken,
    required String baseUrl,
  }) async {
    await Future.wait([
      _storage.write(key: _kTokenKey, value: token),
      _storage.write(key: _kRefreshTokenKey, value: refreshToken),
      _storage.write(key: _kBaseUrlKey, value: baseUrl),
    ]);
  }

  /// Load and decode the cached entitlement.  Returns `null` if nothing is
  /// cached or if the token is outside the grace window (effectively expired
  /// and locked).
  Future<CachedEntitlement?> loadWithGrace() async {
    final token = await _storage.read(key: _kTokenKey);
    if (token == null) return null;

    final entitlement = _verifier.tryDecode(token);
    if (entitlement == null) return null;

    final deadline = entitlement.expiresAt.add(_graceWindow);
    final now = DateTime.now();

    if (now.isAfter(deadline)) {
      await clear();
      return null;
    }

    final refreshToken = await _storage.read(key: _kRefreshTokenKey);
    final baseUrl = await _storage.read(key: _kBaseUrlKey);

    return CachedEntitlement(
      token: token,
      entitlement: entitlement,
      refreshToken: refreshToken ?? '',
      baseUrl: baseUrl ?? '',
      isExpiredButWithinGrace:
          entitlement.isExpired && now.isBefore(deadline),
    );
  }

  /// Overwrite only the tokens (used after a successful auto-refresh).
  Future<void> updateTokens({
    required String token,
    required String refreshToken,
  }) async {
    await Future.wait([
      _storage.write(key: _kTokenKey, value: token),
      _storage.write(key: _kRefreshTokenKey, value: refreshToken),
    ]);
  }

  /// Delete all cached data (on explicit deactivation or permanent lock).
  Future<void> clear() async {
    await Future.wait([
      _storage.delete(key: _kTokenKey),
      _storage.delete(key: _kRefreshTokenKey),
      _storage.delete(key: _kBaseUrlKey),
    ]);
  }
}

/// Holds a decoded entitlement along with its raw token strings.
class CachedEntitlement {
  const CachedEntitlement({
    required this.token,
    required this.entitlement,
    required this.refreshToken,
    required this.baseUrl,
    required this.isExpiredButWithinGrace,
  });

  final String token;
  final Entitlement entitlement;
  final String refreshToken;
  final String baseUrl;

  /// `true` when the token's `exp` is in the past but still within the 72-hour
  /// grace window.  SIP operations are permitted; the client should schedule an
  /// immediate refresh attempt.
  final bool isExpiredButWithinGrace;
}
