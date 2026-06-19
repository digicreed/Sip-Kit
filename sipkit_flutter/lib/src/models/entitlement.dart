import 'package:equatable/equatable.dart';

/// The decoded payload of the entitlement JWT returned by the SipKit
/// licensing backend.  All feature gating and limit enforcement is performed
/// against this object.
class Entitlement extends Equatable {
  const Entitlement({
    required this.jti,
    required this.sub,
    required this.appId,
    required this.features,
    required this.maxAccounts,
    required this.maxConcurrentCalls,
    required this.issuedAt,
    required this.expiresAt,
  });

  /// Unique token ID.
  final String jti;

  /// Provider ID (subject claim).
  final String sub;

  /// Application ID this token was issued for.
  final String appId;

  /// Set of entitled feature strings.  Known values: `"audio"`, `"video"`,
  /// `"conference"`, `"transfer"`, `"dtmf"`.
  final Set<String> features;

  /// Maximum number of simultaneous registered SIP accounts.
  final int maxAccounts;

  /// Maximum number of concurrent active calls.
  final int maxConcurrentCalls;

  /// When the token was issued.
  final DateTime issuedAt;

  /// When the token expires (hard deadline — grace is layered on top).
  final DateTime expiresAt;

  /// `true` when the current clock time is past [expiresAt].
  bool get isExpired => DateTime.now().isAfter(expiresAt);

  /// `true` when the entitlement includes the given [feature] string.
  bool hasFeature(String feature) => features.contains(feature);

  factory Entitlement.fromClaims(Map<String, dynamic> claims) {
    final rawFeatures = claims['features'];
    final featureSet = rawFeatures is List
        ? Set<String>.from(rawFeatures.cast<String>())
        : <String>{};

    return Entitlement(
      jti: claims['jti'] as String? ?? '',
      sub: claims['sub'] as String? ?? '',
      appId: claims['appId'] as String? ?? '',
      features: featureSet,
      maxAccounts: (claims['maxAccounts'] as num?)?.toInt() ?? 1,
      maxConcurrentCalls: (claims['maxConcurrentCalls'] as num?)?.toInt() ?? 1,
      issuedAt:
          DateTime.fromMillisecondsSinceEpoch(((claims['iat'] as num) * 1000).toInt()),
      expiresAt:
          DateTime.fromMillisecondsSinceEpoch(((claims['exp'] as num) * 1000).toInt()),
    );
  }

  @override
  List<Object?> get props => [
        jti,
        sub,
        appId,
        features,
        maxAccounts,
        maxConcurrentCalls,
        issuedAt,
        expiresAt,
      ];
}
