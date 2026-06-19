import 'dart:async';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sipkit_flutter/sipkit_flutter.dart';

// ---------------------------------------------------------------------------
// RSA-2048 test keypair — generated with Node crypto.generateKeyPairSync().
// FOR UNIT TESTS ONLY.  This key is not used in production.
// ---------------------------------------------------------------------------

const _testPrivatePem = '''
-----BEGIN PRIVATE KEY-----
MIIEvAIBADANBgkqhkiG9w0BAQEFAASCBKYwggSiAgEAAoIBAQDs44jXb+fTIFQc
1QUYYPr7evFa7GJw54RgExmm2hNth815oLqT+9bJ5Xrv60bEbICD5Es+HSaKC7Kl
9SRmU9+tlgoq908r+YsFyJZBEFLKDS3zp2CoOMTIUiPOB+Or9zi/dBOE3Zgz5svi
IlWXOgmG2ylhjksQkrBA86jyI+HgqRwKOXMdWwvETs4urfpppFty3rI1XMs0YLmP
dN4Cq3GsEYAzmcK0IVktXB1Vy/5mVsztGwfLeH0BBZzkJuKkrSGa3Q0mVTy5FQ+M
X2nv/mGW3zXetF05jcAuaRzL9v218TifSCOA9D0UNWl4RezrPcEvK/YIkoBSXKdO
2tmqYo+lAgMBAAECggEAJqOTe759VAbjKWPGpbwV3CSozxGdGfjtcuVSqxBJmHVM
+vCQVlh+56YmeBFKlPn0uW6opjxHf79aN68lbYpzQuNlC66Uq6HTvxEBjyHMOzhM
nUBZJ/9Ae8NII1BOnstfpnzWvTaO37Je4acDinv1N1mypX65+D1RAfssfLiFHKlw
b5RknHkWFgP7xKMmBbGqQqzMrdjaDYQizBbeehQBFA4J7GJm3rMEsFFrmUcQYh2/
YChD5RBCV3/wsXSKATVkKGvJ0sMELxR394awSO+1N5emXduVbZCo1BXW1T9kABMV
myxzab1XydeYsn9Gca318SIlVgpdei1Pk9dewyZiUQKBgQD+qqd83BtVovHrK4Xt
QmDkVVBu4nqxxqdP56j4uLBBB5GE8HudWW8YXxhqvqWNEEmzUnxQtTeC4hDWAITG
oXGxO9RlsVS6ks7LK60CGNJzisoa2RapmZBrqBBNqXQM/qLi+CGvLH/lXQW74ezR
ZTK0Yfu2i39qx5DfJd5vKmf/9QKBgQDuIQ0zXirkoRa5Sq3+5WCr0r8E24A1I8qv
Ds/BdrqUf8K4NxHtHx2s5MwMbWFyebBcZEjAgK6Kzbkipi05rzl3Z4394PnmZnbC
0v9wgDKvgV2my5c9pAXShbJAY783yHgEnjvwmTEKpuLjJrC8PCKo9ZZBiBweQJd5
FF+1alHy8QKBgGFmEWKuqAGrrUydO76PWZFak8Wk9voRGSJ1Xmmp8Tcd1uj6NLzs
XJH8pNEGkziNVzKvRH51oIJ9RaUjU6TIUDxRvp0aImatCUwpKyUXKz4ngb6c8o7w
/Yw/HeUl/w2NQez+q5tcsJmfZzcBZFp9ktPseaHKXnQPWXgO+rCXjmkVAoGAbzfO
o4w6ulemdloz09YsBXRDtTATvD4APyzKyc/7KrpVJpbJ75bV1Fd0GeXIWqANR8mq
1QYE/11AN7enbcayL1uVTNsTvJFkrG/B0Dh/88qXA/0YoTiHY6D/9OThfVtK+tUw
p5nU9uWlGHSMnQ31Hja9u9OnVlXSqUFjxiZnKfECgYBrvrhYZLtgaKvBGDKAOk9T
PGvGgfbP8B+gBLplU/LYWeLIjET19lQQHFvbCOCoOMg7pQaG/VpfuMMcTZc+URzO
rtZYuc+6Ndv2UQmnbpADHjgtaZ0xaU1uspajkbKThbTR8591Nm+vQW+x2f3EknI7
hz5IWQ6kS3ABDVXEuunaUA==
-----END PRIVATE KEY-----
''';

const _testPublicPem = '''
-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA7OOI12/n0yBUHNUFGGD6
+3rxWuxicOeEYBMZptoTbYfNeaC6k/vWyeV67+tGxGyAg+RLPh0miguypfUkZlPf
rZYKKvdPK/mLBciWQRBSyg0t86dgqDjEyFIjzgfjq/c4v3QThN2YM+bL4iJVlzoJ
htspYY5LEJKwQPOo8iPh4KkcCjlzHVsLxE7OLq36aaRbct6yNVzLNGC5j3TeAqtx
rBGAM5nCtCFZLVwdVcv+ZlbM7RsHy3h9AQWc5CbipK0hmt0NJlU8uRUPjF9p7/5h
lt813rRdOY3ALmkcy/b9tfE4n0gjgPQ9FDVpeEXs6z3BLyv2CJKAUlynTtrZqmKP
pQIDAQAB
-----END PUBLIC KEY-----
''';

// ---------------------------------------------------------------------------
// JWT helpers
// ---------------------------------------------------------------------------

/// Build a claim map ready for JWT.sign() or Entitlement.fromClaims().
Map<String, dynamic> _claims({
  String iss = 'sipkit-license',
  String sub = 'prov-test',
  String appId = 'com.test.app',
  List<String> features = const ['audio', 'video', 'conference', 'transfer', 'dtmf'],
  int maxAccounts = 5,
  int maxConcurrentCalls = 10,
  Duration expiresIn = const Duration(hours: 24),
  bool alreadyExpired = false,
}) {
  final now = DateTime.now();
  final expDelta = alreadyExpired ? -const Duration(hours: 1) : expiresIn;
  return {
    'iss': iss,
    'sub': sub,
    'appId': appId,
    'features': features,
    'maxAccounts': maxAccounts,
    'maxConcurrentCalls': maxConcurrentCalls,
    'iat': now.millisecondsSinceEpoch ~/ 1000,
    'exp': now.add(expDelta).millisecondsSinceEpoch ~/ 1000,
    'jti': 'test-jti-${now.millisecondsSinceEpoch}',
  };
}

/// Sign a claim map with the test RSA-2048 private key (RS256).
String _signRS256(Map<String, dynamic> payload) =>
    JWT(payload).sign(RSAPrivateKey(_testPrivatePem));

/// Produce a symmetric-key token (HS256) — the RS256 verifier must reject it.
String _signHMAC(Map<String, dynamic> payload) =>
    JWT(payload).sign(SecretKey('unit-test-hmac-secret'));

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // ─── Entitlement.fromClaims ──────────────────────────────────────────────

  group('Entitlement — fromClaims parsing', () {
    test('parses all fields correctly', () {
      final now = DateTime.now();
      final exp = now.add(const Duration(hours: 24));
      final claims = {
        'jti': 'jti-abc',
        'sub': 'prov-123',
        'appId': 'com.acme.app',
        'features': ['audio', 'video', 'conference'],
        'maxAccounts': 3,
        'maxConcurrentCalls': 20,
        'iat': now.millisecondsSinceEpoch ~/ 1000,
        'exp': exp.millisecondsSinceEpoch ~/ 1000,
      };
      final ent = Entitlement.fromClaims(claims);
      expect(ent.jti, 'jti-abc');
      expect(ent.sub, 'prov-123');
      expect(ent.appId, 'com.acme.app');
      expect(ent.features, {'audio', 'video', 'conference'});
      expect(ent.maxAccounts, 3);
      expect(ent.maxConcurrentCalls, 20);
      expect(ent.isExpired, isFalse);
    });

    test('isExpired is true when exp is in the past', () {
      final past = DateTime.now().subtract(const Duration(hours: 1));
      final claims = {
        'jti': 'x', 'sub': 'p', 'appId': 'a',
        'features': <String>[],
        'maxAccounts': 1, 'maxConcurrentCalls': 1,
        'iat': past.subtract(const Duration(hours: 24)).millisecondsSinceEpoch ~/ 1000,
        'exp': past.millisecondsSinceEpoch ~/ 1000,
      };
      expect(Entitlement.fromClaims(claims).isExpired, isTrue);
    });

    test('hasFeature returns true for present and false for absent', () {
      final exp = DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000;
      final ent = Entitlement.fromClaims({
        'jti': 'x', 'sub': 'p', 'appId': 'a',
        'features': ['audio', 'transfer'],
        'maxAccounts': 1, 'maxConcurrentCalls': 1, 'iat': 0, 'exp': exp,
      });
      expect(ent.hasFeature('audio'), isTrue);
      expect(ent.hasFeature('transfer'), isTrue);
      expect(ent.hasFeature('video'), isFalse);
    });

    test('empty features list produces empty set', () {
      final exp = DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000;
      final ent = Entitlement.fromClaims({
        'jti': 'x', 'sub': 'p', 'appId': 'a',
        'features': <String>[],
        'maxAccounts': 1, 'maxConcurrentCalls': 1, 'iat': 0, 'exp': exp,
      });
      expect(ent.features, isEmpty);
    });
  });

  // ─── EntitlementVerifier.tryDecode — offline / no-sig-check path ─────────

  group('EntitlementVerifier.tryDecode', () {
    test('decodes a valid RS256 token into Entitlement without signature check', () {
      final token = _signRS256(_claims());
      final verifier = EntitlementVerifier(publicKeyPem: _testPublicPem);
      final ent = verifier.tryDecode(token);
      expect(ent, isNotNull);
      expect(ent!.sub, 'prov-test');
      expect(ent.features, containsAll(['audio', 'video', 'conference']));
    });

    test('decodes an HMAC-signed token (signature is NOT verified)', () {
      final token = _signHMAC(_claims());
      final verifier = EntitlementVerifier(publicKeyPem: _testPublicPem);
      final ent = verifier.tryDecode(token);
      expect(ent, isNotNull);
      expect(ent!.appId, 'com.test.app');
    });

    test('returns null for a garbage string', () {
      final verifier = EntitlementVerifier(publicKeyPem: _testPublicPem);
      expect(verifier.tryDecode('not.a.jwt'), isNull);
    });

    test('decodes an expired token (claims still readable)', () {
      final token = _signRS256(_claims(alreadyExpired: true));
      final verifier = EntitlementVerifier(publicKeyPem: _testPublicPem);
      final ent = verifier.tryDecode(token);
      expect(ent, isNotNull);
      expect(ent!.isExpired, isTrue);
    });
  });

  // ─── EntitlementVerifier.verify — RS256 strict validation ────────────────

  group('EntitlementVerifier.verify — signature enforcement', () {
    test('accepts a valid RS256 token signed with matching private key', () {
      final token = _signRS256(_claims());
      final verifier = EntitlementVerifier(publicKeyPem: _testPublicPem);
      final ent = verifier.verify(token);
      expect(ent.sub, 'prov-test');
      expect(ent.appId, 'com.test.app');
      expect(ent.maxAccounts, 5);
      expect(ent.isExpired, isFalse);
    });

    test('accepts an expired RS256 token (expiry handled by grace window, not here)', () {
      final token = _signRS256(_claims(alreadyExpired: true));
      final verifier = EntitlementVerifier(publicKeyPem: _testPublicPem);
      final ent = verifier.verify(token); // must not throw
      expect(ent.isExpired, isTrue);
    });

    test('throws ActivationError when an HMAC-signed token is given to RS256 verifier', () {
      // Token signed with symmetric key must be rejected by the RSA verifier.
      final token = _signHMAC(_claims());
      final verifier = EntitlementVerifier(publicKeyPem: _testPublicPem);
      expect(
        () => verifier.verify(token),
        throwsA(isA<ActivationError>()),
      );
    });

    test('throws ActivationError when the bundled RSA key is used against an HMAC token', () {
      // Verify the PRODUCTION bundled key also rejects HMAC-signed tokens.
      final token = _signHMAC(_claims());
      final verifier = EntitlementVerifier(); // bundled production key
      expect(
        () => verifier.verify(token),
        throwsA(isA<ActivationError>()),
      );
    });

    test('throws ActivationError for a token with a tampered payload', () {
      // Sign a valid claim, then tamper with the Base64 payload segment.
      final validToken = _signRS256(_claims());
      final parts = validToken.split('.');
      // Encode a different payload (more maxAccounts) and splice it in.
      final fakePayload = parts[1].replaceAll('B', 'A'); // corrupt payload bytes
      final tampered = '${parts[0]}.$fakePayload.${parts[2]}';
      final verifier = EntitlementVerifier(publicKeyPem: _testPublicPem);
      expect(
        () => verifier.verify(tampered),
        throwsA(isA<ActivationError>()),
      );
    });

    test('throws ActivationError for garbage input', () {
      final verifier = EntitlementVerifier(publicKeyPem: _testPublicPem);
      expect(
        () => verifier.verify('garbage.not.a.jwt'),
        throwsA(isA<ActivationError>()),
      );
    });

    test('throws ActivationError when issuer does not match sipkit-license', () {
      final token = _signRS256(_claims(iss: 'rogue-issuer'));
      final verifier = EntitlementVerifier(publicKeyPem: _testPublicPem);
      expect(
        () => verifier.verify(token),
        throwsA(isA<ActivationError>().having(
            (e) => e.message, 'message', contains('issuer'))),
      );
    });

    test('tokens signed with a DIFFERENT RSA key are rejected', () {
      // Build a second keypair implicitly by using the production bundled key
      // to verify a token that was signed with the TEST private key.
      final token = _signRS256(_claims());
      final verifier = EntitlementVerifier(); // uses bundled PRODUCTION key
      expect(
        () => verifier.verify(token),
        throwsA(isA<ActivationError>()),
      );
    });
  });

  // ─── Feature gating ───────────────────────────────────────────────────────

  group('EntitlementChecks — feature gating', () {
    late Entitlement audioOnly;
    late Entitlement full;

    setUp(() {
      final exp = DateTime.now().add(const Duration(hours: 24)).millisecondsSinceEpoch ~/ 1000;
      audioOnly = Entitlement.fromClaims({
        'jti': 'a', 'sub': 'p', 'appId': 'x',
        'features': ['audio'],
        'maxAccounts': 1, 'maxConcurrentCalls': 2, 'iat': 0, 'exp': exp,
      });
      full = Entitlement.fromClaims({
        'jti': 'b', 'sub': 'p', 'appId': 'x',
        'features': ['audio', 'video', 'conference', 'transfer', 'dtmf'],
        'maxAccounts': 5, 'maxConcurrentCalls': 10, 'iat': 0, 'exp': exp,
      });
    });

    test('requireFeature throws NotEntitledError for absent feature', () {
      expect(() => audioOnly.requireFeature('video'),
          throwsA(isA<NotEntitledError>()));
    });

    test('requireFeature does not throw for present feature', () {
      expect(() => full.requireFeature('video'), returnsNormally);
      expect(() => full.requireFeature('conference'), returnsNormally);
    });

    test('requireFeature error message names the missing feature', () {
      try {
        audioOnly.requireFeature('video');
        fail('Should have thrown');
      } on NotEntitledError catch (e) {
        expect(e.message, contains('"video"'));
      }
    });

    test('requireFeature("conference") throws on audio-only plan', () {
      expect(() => audioOnly.requireFeature('conference'),
          throwsA(isA<NotEntitledError>().having(
              (e) => e.message, 'message', contains('"conference"'))));
    });

    test('requireAccountSlot throws at limit', () {
      expect(() => audioOnly.requireAccountSlot(1),
          throwsA(isA<NotEntitledError>()));
    });

    test('requireAccountSlot passes below limit', () {
      expect(() => full.requireAccountSlot(4), returnsNormally);
    });

    test('requireCallSlot throws at limit', () {
      expect(() => audioOnly.requireCallSlot(2),
          throwsA(isA<NotEntitledError>()));
    });

    test('requireCallSlot passes below limit', () {
      expect(() => full.requireCallSlot(9), returnsNormally);
    });

    test('ConferenceNotEntitledError is a NotEntitledError', () {
      expect(const ConferenceNotEntitledError(), isA<NotEntitledError>());
    });
  });

  // ─── Enum completeness ────────────────────────────────────────────────────

  group('Enum completeness', () {
    test('ActivationState has all required values', () {
      expect(ActivationState.values, containsAll([
        ActivationState.unactivated, ActivationState.activating,
        ActivationState.active, ActivationState.expired, ActivationState.locked,
      ]));
    });

    test('CallState has all required values', () {
      expect(CallState.values, containsAll([
        CallState.connecting, CallState.ringing, CallState.earlyMedia,
        CallState.established, CallState.held, CallState.terminated,
      ]));
    });

    test('AccountStatus has all required values', () {
      expect(AccountStatus.values, containsAll([
        AccountStatus.unregistered, AccountStatus.registering,
        AccountStatus.registered, AccountStatus.failed,
      ]));
    });
  });

  // ─── Error hierarchy ─────────────────────────────────────────────────────

  group('Error hierarchy', () {
    test('ActivationError is a SipKitError', () {
      expect(const ActivationError('x'), isA<SipKitError>());
    });

    test('NotEntitledError is a SipKitError', () {
      expect(const NotEntitledError('x'), isA<SipKitError>());
    });

    test('NetworkError carries statusCode', () {
      const e = NetworkError('test', statusCode: 503);
      expect(e.statusCode, 503);
    });

    test('toString includes class name and message', () {
      const e = ActivationError('License revoked');
      expect(e.toString(), contains('ActivationError'));
      expect(e.toString(), contains('License revoked'));
    });
  });

  // ─── SipKitCall state machine + feature gating ───────────────────────────

  group('SipKitCall — state machine', () {
    Entitlement _full() {
      final exp = DateTime.now().add(const Duration(hours: 24)).millisecondsSinceEpoch ~/ 1000;
      return Entitlement.fromClaims({
        'jti': 'j', 'sub': 'p', 'appId': 'a',
        'features': ['audio', 'video', 'conference', 'transfer', 'dtmf'],
        'maxAccounts': 5, 'maxConcurrentCalls': 10, 'iat': 0, 'exp': exp,
      });
    }

    Entitlement _audioOnly() {
      final exp = DateTime.now().add(const Duration(hours: 24)).millisecondsSinceEpoch ~/ 1000;
      return Entitlement.fromClaims({
        'jti': 'j', 'sub': 'p', 'appId': 'a',
        'features': ['audio'],
        'maxAccounts': 1, 'maxConcurrentCalls': 1, 'iat': 0, 'exp': exp,
      });
    }

    test('initial outbound state is connecting', () {
      final call = SipKitCall.create(
        id: 'c1', accountId: 'a1', remoteUri: 'sip:bob@test.com',
        displayName: 'Bob', direction: CallDirection.outbound,
        engine: _NoopEngine(), getEntitlement: _full,
      );
      expect(call.currentState, CallState.connecting);
    });

    test('initial inbound state is ringing', () {
      final call = SipKitCall.create(
        id: 'c2', accountId: 'a1', remoteUri: 'sip:alice@test.com',
        displayName: 'Alice', direction: CallDirection.inbound,
        engine: _NoopEngine(), getEntitlement: _full,
      );
      expect(call.currentState, CallState.ringing);
    });

    test('updateState emits transitions and updates snapshot', () async {
      final call = SipKitCall.create(
        id: 'c3', accountId: 'a1', remoteUri: 'sip:x@test.com',
        displayName: '', direction: CallDirection.outbound,
        engine: _NoopEngine(), getEntitlement: _full,
      );
      final states = <CallState>[];
      final sub = call.state.listen(states.add);
      call.updateState(CallState.ringing);
      call.updateState(CallState.established);
      call.updateState(CallState.terminated);
      await Future.delayed(Duration.zero);
      await sub.cancel();
      expect(states,
          [CallState.ringing, CallState.established, CallState.terminated]);
      expect(call.currentState, CallState.terminated);
    });

    test('updateState skips duplicate emissions', () async {
      final call = SipKitCall.create(
        id: 'c4', accountId: 'a1', remoteUri: 'sip:x@test.com',
        displayName: '', direction: CallDirection.outbound,
        engine: _NoopEngine(), getEntitlement: _full,
      );
      final states = <CallState>[];
      final sub = call.state.listen(states.add);
      call.updateState(CallState.ringing);
      call.updateState(CallState.ringing); // duplicate — must not re-emit
      call.updateState(CallState.established);
      await Future.delayed(Duration.zero);
      await sub.cancel();
      expect(states, [CallState.ringing, CallState.established]);
    });

    // ── Feature gating enforced on SipKitCall before engine is called ────────

    test('enableVideo(true) throws NotEntitledError when video is not entitled', () {
      final call = SipKitCall.create(
        id: 'c5', accountId: 'a1', remoteUri: 'sip:x@test.com',
        displayName: '', direction: CallDirection.outbound,
        engine: _NoopEngine(), getEntitlement: _audioOnly,
      );
      expect(() => call.enableVideo(true), throwsA(isA<NotEntitledError>()));
    });

    test('enableVideo(false) does not check entitlement', () {
      final call = SipKitCall.create(
        id: 'c6', accountId: 'a1', remoteUri: 'sip:x@test.com',
        displayName: '', direction: CallDirection.outbound,
        engine: _NoopEngine(), getEntitlement: _audioOnly,
      );
      expect(() => call.enableVideo(false), returnsNormally);
    });

    test('sendDtmf throws NotEntitledError when dtmf is not entitled', () {
      final call = SipKitCall.create(
        id: 'c7', accountId: 'a1', remoteUri: 'sip:x@test.com',
        displayName: '', direction: CallDirection.outbound,
        engine: _NoopEngine(), getEntitlement: _audioOnly,
      );
      expect(() => call.sendDtmf('1234'), throwsA(isA<NotEntitledError>()));
    });

    test('blindTransfer throws NotEntitledError when transfer is not entitled', () {
      final call = SipKitCall.create(
        id: 'c8', accountId: 'a1', remoteUri: 'sip:x@test.com',
        displayName: '', direction: CallDirection.outbound,
        engine: _NoopEngine(), getEntitlement: _audioOnly,
      );
      expect(() => call.blindTransfer('sip:carol@test.com'),
          throwsA(isA<NotEntitledError>()));
    });

    test('attendedTransfer throws NotEntitledError when transfer is not entitled', () {
      final engine = _NoopEngine();
      final call = SipKitCall.create(
        id: 'c9', accountId: 'a1', remoteUri: 'sip:x@test.com',
        displayName: '', direction: CallDirection.outbound,
        engine: engine, getEntitlement: _audioOnly,
      );
      final other = SipKitCall.create(
        id: 'c10', accountId: 'a1', remoteUri: 'sip:y@test.com',
        displayName: '', direction: CallDirection.outbound,
        engine: engine, getEntitlement: _audioOnly,
      );
      expect(() => call.attendedTransfer(other),
          throwsA(isA<NotEntitledError>()));
    });
  });

  // ─── SipKitAccount state machine ─────────────────────────────────────────

  group('SipKitAccount — state machine', () {
    test('initial status is unregistered', () {
      final acc = SipKitAccount.create(
        id: 'a1',
        config: const SipKitAccountConfig(
          username: 'alice', password: 'pw',
          domain: 'test.com', wsUrl: 'wss://test.com/ws',
        ),
        engine: _NoopEngine(),
      );
      expect(acc.currentStatus, AccountStatus.unregistered);
    });

    test('updateStatus emits and updates snapshot', () async {
      final acc = SipKitAccount.create(
        id: 'a2',
        config: const SipKitAccountConfig(
          username: 'bob', password: 'pw',
          domain: 'test.com', wsUrl: 'wss://test.com/ws',
        ),
        engine: _NoopEngine(),
      );
      final statuses = <AccountStatus>[];
      final sub = acc.status.listen(statuses.add);
      acc.updateStatus(AccountStatus.registering);
      acc.updateStatus(AccountStatus.registered);
      await Future.delayed(Duration.zero);
      await sub.cancel();
      expect(statuses, [AccountStatus.registering, AccountStatus.registered]);
    });
  });
}

// ---------------------------------------------------------------------------
// _NoopEngine — minimal SipEngine stub; no network, no platform channel.
// ---------------------------------------------------------------------------

class _NoopEngine extends SipEngine {
  final _ic = StreamController<IncomingCallEvent>.broadcast();
  final _cs = StreamController<CallStateEvent>.broadcast();
  final _as = StreamController<AccountStatusEvent>.broadcast();
  final _ls = StreamController<(String, dynamic)>.broadcast();
  final _rs = StreamController<(String, dynamic)>.broadcast();

  @override Stream<IncomingCallEvent> get incomingCall => _ic.stream;
  @override Stream<CallStateEvent> get callStateChanged => _cs.stream;
  @override Stream<AccountStatusEvent> get accountStatusChanged => _as.stream;
  @override Stream<(String, dynamic)> get localStream => _ls.stream;
  @override Stream<(String, dynamic)> get remoteStream => _rs.stream;

  @override Future<void> init() async {}
  @override Future<void> dispose() async {
    await _ic.close(); await _cs.close(); await _as.close();
    await _ls.close(); await _rs.close();
  }
  @override Future<void> registerAccount(String a, SipKitAccountConfig c) async {}
  @override Future<void> unregister(String a) async {}
  @override Future<String> makeCall(String a, String t, {bool video = false}) async => 'call_noop';
  @override Future<void> answer(String c, {bool video = false}) async {}
  @override Future<void> hangup(String c) async {}
  @override Future<void> hold(String c) async {}
  @override Future<void> unhold(String c) async {}
  @override Future<void> mute(String c, {required bool muted}) async {}
  @override Future<void> sendDtmf(String c, String d) async {}
  @override Future<void> blindTransfer(String c, String t) async {}
  @override Future<void> attendedTransfer(String c, String o) async {}
  @override Future<void> enableVideo(String c, {required bool enabled}) async {}
}
