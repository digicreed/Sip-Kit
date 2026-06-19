import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';

import '../errors.dart';
import '../models/entitlement.dart';

/// Default RS256 public key bundled with the SDK.
///
/// Providers may override this by passing [publicKeyPem] to [EntitlementVerifier]
/// for key pinning (e.g., after rotating the licensing server keypair).
///
/// Replace this value with the output of:
///   GET https://your-sipkit-backend.com/api/v1/public-key
const _kDefaultPublicKeyPem = '''
-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA0000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000REPLACEME0000000000000
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA/REPLACEME==
-----END PUBLIC KEY-----
''';

/// Verifies and decodes the entitlement JWT issued by the SipKit licensing
/// backend.  The token is signed RS256 and verified offline using the bundled
/// public key (or an override supplied by the provider for key pinning).
class EntitlementVerifier {
  EntitlementVerifier({String? publicKeyPem})
      : _publicKey = RSAPublicKey(publicKeyPem ?? _kDefaultPublicKeyPem);

  final RSAPublicKey _publicKey;

  /// Verify [token] and return the decoded [Entitlement].
  ///
  /// Throws [ActivationError] if the token is invalid, has a wrong signature,
  /// is issued by an unexpected issuer, or is structurally malformed.
  ///
  /// Note: expiry is NOT checked here — the client applies the grace window
  /// separately via [EntitlementCache].
  Entitlement verify(String token) {
    try {
      final jwt = JWT.verify(
        token,
        _publicKey,
        checkExpiresIn: false,
      );

      final claims = jwt.payload as Map<String, dynamic>;

      if (claims['iss'] != 'sipkit-license') {
        throw const ActivationError(
            'Entitlement token has unexpected issuer. '
            'Ensure you are pointing at a SipKit licensing backend.');
      }

      return Entitlement.fromClaims(claims);
    } on JWTExpiredException {
      // We let this through — expiry with grace is handled by EntitlementCache.
      try {
        final jwt = JWT.decode(token);
        final claims = jwt.payload as Map<String, dynamic>;
        return Entitlement.fromClaims(claims);
      } catch (_) {
        rethrow;
      }
    } on JWTInvalidException catch (e) {
      throw ActivationError('Entitlement token is invalid: ${e.message}');
    } on JWTExpiredException catch (e) {
      throw ActivationError('Entitlement token expired: ${e.message}');
    } catch (e) {
      throw ActivationError('Failed to verify entitlement token: $e');
    }
  }

  /// Decode [token] without signature verification (for offline cache reads).
  /// Returns `null` if the token is malformed.
  Entitlement? tryDecode(String token) {
    try {
      final jwt = JWT.decode(token);
      final claims = jwt.payload as Map<String, dynamic>;
      return Entitlement.fromClaims(claims);
    } catch (_) {
      return null;
    }
  }
}

/// Feature and limit checks against a decoded [Entitlement].
extension EntitlementChecks on Entitlement {
  /// Throws [NotEntitledError] if [feature] is not in [features].
  void requireFeature(String feature) {
    if (!hasFeature(feature)) {
      throw NotEntitledError(
          'The "$feature" feature is not enabled in your current entitlement. '
          'Contact your SipKit administrator to upgrade your license.');
    }
  }

  /// Throws [NotEntitledError] if [currentCount] is already at [maxAccounts].
  void requireAccountSlot(int currentCount) {
    if (currentCount >= maxAccounts) {
      throw NotEntitledError(
          'Account limit reached ($currentCount/$maxAccounts). '
          'Your entitlement allows up to $maxAccounts simultaneous accounts. '
          'Contact your SipKit administrator to increase your limit.');
    }
  }

  /// Throws [NotEntitledError] if [currentCount] is already at
  /// [maxConcurrentCalls].
  void requireCallSlot(int currentCount) {
    if (currentCount >= maxConcurrentCalls) {
      throw NotEntitledError(
          'Concurrent call limit reached ($currentCount/$maxConcurrentCalls).');
    }
  }
}
