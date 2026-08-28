import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:sipkit_flutter/sipkit_flutter.dart';

void main() {
  test(
    'a controlled diagnostic call reserves an entitlement call slot',
    () async {
      final entitlement = Entitlement(
        jti: 'test',
        sub: 'provider',
        appId: 'app',
        features: const {'audio'},
        maxAccounts: 1,
        maxConcurrentCalls: 1,
        issuedAt: DateTime.now().subtract(const Duration(minutes: 1)),
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );
      final cache = _EmptyCache();
      final cancellation = SipDiagnosticCancellationToken();
      final engine = _BlockingDiagnosticEngine(onMakeCall: cancellation.cancel);
      final client = SipKitClient(
        engine: engine,
        cache: cache,
        activationService: _FakeActivationService(cache, entitlement),
      );
      await client.activate(
        licenseKey: 'test',
        baseUrl: 'https://license.test',
      );
      final account = await client.addAccount(
        const SipKitAccountConfig(
          username: 'alice',
          password: 'secret',
          domain: 'provider.test',
          registerOnAdd: false,
        ),
      );

      final diagnostic = client.diagnoseAccount(
        account.id,
        testTarget: 'sip:echo@provider.test',
        cancellationToken: cancellation,
      );
      await engine.diagnosticStarted.future;
      await engine.hangupRequested.future;

      await expectLater(
        client.makeCall(account.id, 'sip:bob@provider.test'),
        throwsA(isA<NotEntitledError>()),
      );

      engine.finishHangup();
      await diagnostic;
      await client.dispose();
    },
  );
}

class _EmptyCache extends EntitlementCache {
  @override
  Future<CachedEntitlement?> loadWithGrace() async => null;
}

class _FakeActivationService extends ActivationService {
  _FakeActivationService(EntitlementCache cache, this.entitlement)
    : super(cache: cache, verifier: EntitlementVerifier());

  final Entitlement entitlement;

  @override
  Future<Entitlement> activate({
    required String licenseKey,
    required String baseUrl,
    required String appId,
    required String deviceId,
    required void Function(Entitlement) onRefreshed,
    required void Function() onExpired,
  }) async => entitlement;
}

class _BlockingDiagnosticEngine extends SipEngine {
  _BlockingDiagnosticEngine({required this.onMakeCall});

  final void Function() onMakeCall;
  final diagnosticStarted = Completer<void>();
  final hangupRequested = Completer<void>();
  final _calls = StreamController<CallStateEvent>.broadcast();

  @override
  Future<Map<String, Object?>> diagnosticSnapshot(String accountId) async =>
      const {};

  @override
  Future<String> makeCall(
    String accountId,
    String target, {
    bool video = false,
  }) async {
    if (!diagnosticStarted.isCompleted) diagnosticStarted.complete();
    scheduleMicrotask(onMakeCall);
    return 'diagnostic_call';
  }

  void finishHangup() {
    _calls.add(
      const CallStateEvent(
        callId: 'diagnostic_call',
        state: CallState.terminated,
      ),
    );
  }

  @override
  Future<void> init() async {}
  @override
  Future<void> dispose() async => _calls.close();
  @override
  Future<void> registerAccount(
    String accountId,
    SipKitAccountConfig config,
  ) async {}
  @override
  Future<void> unregister(String accountId) async {}
  @override
  Future<void> answer(String callId, {bool video = false}) async {}
  @override
  Future<void> hangup(String callId) async {
    if (!hangupRequested.isCompleted) hangupRequested.complete();
  }

  @override
  Future<void> hold(String callId) async {}
  @override
  Future<void> unhold(String callId) async {}
  @override
  Future<void> mute(String callId, {required bool muted}) async {}
  @override
  Future<void> sendDtmf(String callId, String digits) async {}
  @override
  Future<void> blindTransfer(String callId, String targetUri) async {}
  @override
  Future<void> attendedTransfer(String callId, String otherCallId) async {}
  @override
  Future<void> enableVideo(String callId, {required bool enabled}) async {}

  @override
  Stream<IncomingCallEvent> get incomingCall => const Stream.empty();
  @override
  Stream<CallStateEvent> get callStateChanged => _calls.stream;
  @override
  Stream<AccountStatusEvent> get accountStatusChanged => const Stream.empty();
  @override
  Stream<(String, MediaStream)> get localStream => const Stream.empty();
  @override
  Stream<(String, MediaStream)> get remoteStream => const Stream.empty();
}
