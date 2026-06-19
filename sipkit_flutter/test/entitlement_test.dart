import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sipkit_flutter/sipkit_flutter.dart';

void main() {
  group('Entitlement — JWT decoding', () {
    test('fromClaims parses all fields correctly', () {
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

    test('isExpired returns true when exp is in the past', () {
      final past = DateTime.now().subtract(const Duration(hours: 1));
      final claims = {
        'jti': 'x',
        'sub': 'p',
        'appId': 'a',
        'features': <String>[],
        'maxAccounts': 1,
        'maxConcurrentCalls': 1,
        'iat': past.subtract(const Duration(hours: 24)).millisecondsSinceEpoch ~/ 1000,
        'exp': past.millisecondsSinceEpoch ~/ 1000,
      };
      final ent = Entitlement.fromClaims(claims);
      expect(ent.isExpired, isTrue);
    });

    test('hasFeature returns true for present features and false for absent ones', () {
      final claims = {
        'jti': 'x', 'sub': 'p', 'appId': 'a',
        'features': ['audio', 'transfer'],
        'maxAccounts': 1, 'maxConcurrentCalls': 1,
        'iat': 0,
        'exp': DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000,
      };
      final ent = Entitlement.fromClaims(claims);
      expect(ent.hasFeature('audio'), isTrue);
      expect(ent.hasFeature('transfer'), isTrue);
      expect(ent.hasFeature('video'), isFalse);
      expect(ent.hasFeature('conference'), isFalse);
    });

    test('fromClaims with empty features list sets empty set', () {
      final claims = {
        'jti': 'x', 'sub': 'p', 'appId': 'a',
        'features': <String>[],
        'maxAccounts': 1, 'maxConcurrentCalls': 1,
        'iat': 0,
        'exp': DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000,
      };
      final ent = Entitlement.fromClaims(claims);
      expect(ent.features, isEmpty);
    });
  });

  group('EntitlementChecks — feature gating', () {
    late Entitlement audioOnly;
    late Entitlement full;

    setUp(() {
      final exp =
          DateTime.now().add(const Duration(hours: 24)).millisecondsSinceEpoch ~/ 1000;
      audioOnly = Entitlement.fromClaims({
        'jti': 'a', 'sub': 'p', 'appId': 'x',
        'features': ['audio'],
        'maxAccounts': 1,
        'maxConcurrentCalls': 2,
        'iat': 0, 'exp': exp,
      });
      full = Entitlement.fromClaims({
        'jti': 'b', 'sub': 'p', 'appId': 'x',
        'features': ['audio', 'video', 'conference', 'transfer', 'dtmf'],
        'maxAccounts': 5,
        'maxConcurrentCalls': 10,
        'iat': 0, 'exp': exp,
      });
    });

    test('requireFeature throws NotEntitledError for absent feature', () {
      expect(
        () => audioOnly.requireFeature('video'),
        throwsA(isA<NotEntitledError>()),
      );
    });

    test('requireFeature does not throw for present feature', () {
      expect(() => full.requireFeature('video'), returnsNormally);
      expect(() => full.requireFeature('conference'), returnsNormally);
    });

    test('requireFeature("conference") throws NotEntitledError on audio-only plan', () {
      expect(
        () => audioOnly.requireFeature('conference'),
        throwsA(isA<NotEntitledError>().having(
          (e) => e.message,
          'message',
          contains('"conference"'),
        )),
      );
    });

    test('requireAccountSlot throws when at limit', () {
      expect(
        () => audioOnly.requireAccountSlot(1), // maxAccounts = 1, current = 1
        throwsA(isA<NotEntitledError>()),
      );
    });

    test('requireAccountSlot does not throw below limit', () {
      expect(() => full.requireAccountSlot(4), returnsNormally); // maxAccounts=5
    });

    test('requireCallSlot throws when at limit', () {
      expect(
        () => audioOnly.requireCallSlot(2), // maxConcurrentCalls = 2
        throwsA(isA<NotEntitledError>()),
      );
    });

    test('requireCallSlot does not throw below limit', () {
      expect(() => full.requireCallSlot(9), returnsNormally); // max=10
    });

    test('NotEntitledError message contains feature name', () {
      try {
        audioOnly.requireFeature('video');
        fail('Should have thrown');
      } on NotEntitledError catch (e) {
        expect(e.message, contains('"video"'));
      }
    });

    test('ConferenceNotEntitledError is a NotEntitledError', () {
      expect(const ConferenceNotEntitledError(), isA<NotEntitledError>());
    });
  });

  group('ActivationState transitions', () {
    test('ActivationState enum has all required values', () {
      expect(ActivationState.values, containsAll([
        ActivationState.unactivated,
        ActivationState.activating,
        ActivationState.active,
        ActivationState.expired,
        ActivationState.locked,
      ]));
    });
  });

  group('CallState enum', () {
    test('CallState has all required values', () {
      expect(CallState.values, containsAll([
        CallState.connecting,
        CallState.ringing,
        CallState.earlyMedia,
        CallState.established,
        CallState.held,
        CallState.terminated,
      ]));
    });
  });

  group('AccountStatus enum', () {
    test('AccountStatus has all required values', () {
      expect(AccountStatus.values, containsAll([
        AccountStatus.unregistered,
        AccountStatus.registering,
        AccountStatus.registered,
        AccountStatus.failed,
      ]));
    });
  });

  group('Error hierarchy', () {
    test('ActivationError is a SipKitError', () {
      expect(const ActivationError('test'), isA<SipKitError>());
    });

    test('NotEntitledError is a SipKitError', () {
      expect(const NotEntitledError('test'), isA<SipKitError>());
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

  group('SipKitCall — state machine', () {
    test('initial outbound call state is connecting', () {
      final call = SipKitCall.create(
        id: 'c1',
        accountId: 'a1',
        remoteUri: 'sip:bob@test.com',
        displayName: 'Bob',
        direction: CallDirection.outbound,
        engine: _NoopEngine(),
        entitlementToken: 'tok',
      );
      expect(call.currentState, CallState.connecting);
    });

    test('initial inbound call state is ringing', () {
      final call = SipKitCall.create(
        id: 'c2',
        accountId: 'a1',
        remoteUri: 'sip:alice@test.com',
        displayName: 'Alice',
        direction: CallDirection.inbound,
        engine: _NoopEngine(),
        entitlementToken: 'tok',
      );
      expect(call.currentState, CallState.ringing);
    });

    test('updateState emits on stream and updates snapshot', () async {
      final call = SipKitCall.create(
        id: 'c3',
        accountId: 'a1',
        remoteUri: 'sip:x@test.com',
        displayName: '',
        direction: CallDirection.outbound,
        engine: _NoopEngine(),
        entitlementToken: 'tok',
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

    test('updateState does not emit duplicate states', () async {
      final call = SipKitCall.create(
        id: 'c4',
        accountId: 'a1',
        remoteUri: 'sip:x@test.com',
        displayName: '',
        direction: CallDirection.outbound,
        engine: _NoopEngine(),
        entitlementToken: 'tok',
      );

      final states = <CallState>[];
      final sub = call.state.listen(states.add);

      call.updateState(CallState.ringing);
      call.updateState(CallState.ringing); // duplicate — should not emit
      call.updateState(CallState.established);

      await Future.delayed(Duration.zero);
      await sub.cancel();

      expect(states, [CallState.ringing, CallState.established]);
    });
  });

  group('SipKitAccount — state machine', () {
    test('initial status is unregistered', () {
      final acc = SipKitAccount.create(
        id: 'a1',
        config: const SipKitAccountConfig(
          username: 'alice',
          password: 'pw',
          domain: 'test.com',
          wsUrl: 'wss://test.com/ws',
        ),
        engine: _NoopEngine(),
      );
      expect(acc.currentStatus, AccountStatus.unregistered);
    });

    test('updateStatus emits on stream and updates snapshot', () async {
      final acc = SipKitAccount.create(
        id: 'a2',
        config: const SipKitAccountConfig(
          username: 'bob',
          password: 'pw',
          domain: 'test.com',
          wsUrl: 'wss://test.com/ws',
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
// _NoopEngine — minimal SipEngine stub (no network required for unit tests).
// ---------------------------------------------------------------------------

class _NoopEngine extends SipEngine {
  final _ic = StreamController<IncomingCallEvent>.broadcast();
  final _cs = StreamController<CallStateEvent>.broadcast();
  final _as = StreamController<AccountStatusEvent>.broadcast();
  final _ls = StreamController<(String, dynamic)>.broadcast();
  final _rs = StreamController<(String, dynamic)>.broadcast();

  @override
  Stream<IncomingCallEvent> get incomingCall => _ic.stream;
  @override
  Stream<CallStateEvent> get callStateChanged => _cs.stream;
  @override
  Stream<AccountStatusEvent> get accountStatusChanged => _as.stream;
  @override
  Stream<(String, dynamic)> get localStream => _ls.stream;
  @override
  Stream<(String, dynamic)> get remoteStream => _rs.stream;

  @override
  Future<void> init() async {}

  @override
  Future<void> dispose() async {
    await _ic.close();
    await _cs.close();
    await _as.close();
    await _ls.close();
    await _rs.close();
  }

  @override
  Future<void> registerAccount(String a, SipKitAccountConfig c) async {}
  @override
  Future<void> unregister(String a) async {}
  @override
  Future<String> makeCall(String a, String t, {bool video = false}) async =>
      'call_noop';
  @override
  Future<void> answer(String c, {bool video = false}) async {}
  @override
  Future<void> hangup(String c) async {}
  @override
  Future<void> hold(String c) async {}
  @override
  Future<void> unhold(String c) async {}
  @override
  Future<void> mute(String c, {required bool muted}) async {}
  @override
  Future<void> sendDtmf(String c, String d) async {}
  @override
  Future<void> blindTransfer(String c, String t) async {}
  @override
  Future<void> attendedTransfer(String c, String o) async {}
  @override
  Future<void> enableVideo(String c, {required bool enabled}) async {}
}
