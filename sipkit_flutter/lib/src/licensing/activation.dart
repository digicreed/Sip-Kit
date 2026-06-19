import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../errors.dart';
import '../models/entitlement.dart';
import 'entitlement.dart';
import 'entitlement_cache.dart';

/// Handles HTTP communication with the SipKit licensing backend:
///   • POST /api/v1/activate
///   • POST /api/v1/refresh
///   • POST /api/v1/usage
///
/// Also manages automatic token refresh scheduling.
class ActivationService {
  ActivationService({
    required this.cache,
    required this.verifier,
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  final EntitlementCache cache;
  final EntitlementVerifier verifier;
  final http.Client _http;

  Timer? _refreshTimer;

  // ─── Activation ────────────────────────────────────────────────────────────

  /// Activate the SDK with the provider's [licenseKey].
  ///
  /// On success, caches the entitlement + refresh token and schedules auto-
  /// refresh before the JWT expires.
  ///
  /// Throws [ActivationError] on invalid/revoked/expired keys.
  /// Throws [NetworkError] on HTTP or connectivity failures.
  Future<Entitlement> activate({
    required String licenseKey,
    required String baseUrl,
    required String appId,
    required String deviceId,
    required void Function(Entitlement) onRefreshed,
    required void Function() onExpired,
  }) async {
    final uri = Uri.parse('${_trimSlash(baseUrl)}/api/v1/activate');
    final body = jsonEncode({
      'licenseKey': licenseKey,
      'appId': appId,
      'deviceId': deviceId,
    });

    final response = await _post(uri, body);
    final data = _parseJson(response, uri);

    final token = data['entitlement'] as String?;
    final refreshToken = data['refreshToken'] as String?;
    if (token == null || refreshToken == null) {
      throw const ActivationError(
          'Licensing server returned an unexpected response format.');
    }

    final entitlement = verifier.verify(token);
    await cache.save(
        token: token, refreshToken: refreshToken, baseUrl: baseUrl);

    _scheduleRefresh(
      baseUrl: baseUrl,
      refreshToken: refreshToken,
      expiresAt: entitlement.expiresAt,
      onRefreshed: onRefreshed,
      onExpired: onExpired,
    );

    return entitlement;
  }

  // ─── Refresh ───────────────────────────────────────────────────────────────

  /// Exchange [refreshToken] for a fresh entitlement JWT.
  ///
  /// Returns the new [Entitlement] and updates the cache.  Throws
  /// [ActivationError] if the refresh token is revoked or expired.
  Future<Entitlement> refresh({
    required String baseUrl,
    required String refreshToken,
  }) async {
    final uri = Uri.parse('${_trimSlash(baseUrl)}/api/v1/refresh');
    final body = jsonEncode({'refreshToken': refreshToken});
    final response = await _post(uri, body);
    final data = _parseJson(response, uri);

    final newToken = data['entitlement'] as String?;
    final newRefresh = data['refreshToken'] as String?;
    if (newToken == null || newRefresh == null) {
      throw const ActivationError(
          'Refresh response from licensing server had unexpected format.');
    }

    final entitlement = verifier.verify(newToken);
    await cache.updateTokens(token: newToken, refreshToken: newRefresh);
    return entitlement;
  }

  // ─── Usage metering ────────────────────────────────────────────────────────

  /// Report usage metrics to the licensing backend.  Fire-and-forget — callers
  /// should not await this in a critical path.
  Future<void> reportUsage({
    required String baseUrl,
    required String entitlementToken,
    required String deviceId,
    int callMinutes = 0,
    int registrations = 0,
    int callsPlaced = 0,
  }) async {
    try {
      final uri = Uri.parse('${_trimSlash(baseUrl)}/api/v1/usage');
      final body = jsonEncode({
        'deviceId': deviceId,
        'callMinutes': callMinutes,
        'registrations': registrations,
        'callsPlaced': callsPlaced,
      });
      await _http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $entitlementToken',
        },
        body: body,
      );
    } catch (_) {
      // Usage reporting is best-effort; swallow errors silently.
    }
  }

  // ─── Auto-refresh scheduling ───────────────────────────────────────────────

  void _scheduleRefresh({
    required String baseUrl,
    required String refreshToken,
    required DateTime expiresAt,
    required void Function(Entitlement) onRefreshed,
    required void Function() onExpired,
  }) {
    _refreshTimer?.cancel();

    // Refresh 5 minutes before expiry (or immediately if already close).
    final refreshAt = expiresAt.subtract(const Duration(minutes: 5));
    final delay = refreshAt.difference(DateTime.now());
    final safeDelay = delay.isNegative ? Duration.zero : delay;

    _refreshTimer = Timer(safeDelay, () async {
      try {
        final entitlement =
            await refresh(baseUrl: baseUrl, refreshToken: refreshToken);
        onRefreshed(entitlement);
        // Read new refresh token from cache for next schedule.
        final cached = await cache.loadWithGrace();
        if (cached != null) {
          _scheduleRefresh(
            baseUrl: baseUrl,
            refreshToken: cached.refreshToken,
            expiresAt: entitlement.expiresAt,
            onRefreshed: onRefreshed,
            onExpired: onExpired,
          );
        }
      } catch (_) {
        onExpired();
      }
    });
  }

  void cancelRefresh() => _refreshTimer?.cancel();

  // ─── HTTP helpers ──────────────────────────────────────────────────────────

  Future<http.Response> _post(Uri uri, String body) async {
    try {
      return await _http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: body,
      );
    } on SocketException catch (e) {
      throw NetworkError('Cannot reach licensing server: ${e.message}');
    } on TimeoutException catch (_) {
      throw const NetworkError('Licensing server request timed out.');
    } catch (e) {
      throw NetworkError('Unexpected network error: $e');
    }
  }

  Map<String, dynamic> _parseJson(http.Response response, Uri uri) {
    if (response.statusCode == 401 || response.statusCode == 403) {
      Map<String, dynamic>? body;
      try {
        body = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (_) {}
      final msg = body?['message'] as String? ?? 'License key is invalid or revoked.';
      throw ActivationError(msg);
    }
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw NetworkError(
          'Licensing server returned HTTP ${response.statusCode}.',
          statusCode: response.statusCode);
    }
    try {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw const NetworkError(
          'Licensing server returned non-JSON response.');
    }
  }

  static String _trimSlash(String url) =>
      url.endsWith('/') ? url.substring(0, url.length - 1) : url;
}
