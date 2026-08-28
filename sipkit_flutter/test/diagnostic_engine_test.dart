import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:sipkit_flutter/sipkit_flutter.dart';

void main() {
  const config = SipKitAccountConfig(
    username: 'alice',
    password: 'not-reported',
    domain: 'voice.provider.test',
    registrar: 'registrar.provider.test',
    transport: SipTransport.tls,
  );

  test('attributes a rejected registration to the provider', () async {
    final engine = _DiagnosticEngine(
      accountSnapshot: const {
        'platform': 'test',
        'nativeAvailable': true,
        'accountPresent': true,
        'registrationActive': false,
        'registrationCode': 403,
        'registrationReason': 'Forbidden',
        'transport': 'tls',
        'registrar': 'registrar.provider.test',
        'sipPort': 5061,
        'audioAvailable': true,
        'microphonePermission': true,
      },
    );

    final report = await engine.runDiagnostics('acc_1', config);
    final registration = report.checks.singleWhere(
      (c) => c.id == 'provider.registration',
    );
    expect(registration.status, SipDiagnosticStatus.failed);
    expect(registration.owner, SipDiagnosticOwner.provider);
    expect(registration.evidence['responseCode'], 403);
    expect(report.platform, 'test');
    await engine.dispose();
  });

  test('reports a missing native artifact without simulated success', () async {
    final engine = _DiagnosticEngine(
      accountSnapshot: const {
        'nativeAvailable': false,
        'accountPresent': false,
        'audioAvailable': false,
      },
    );

    final report = await engine.runDiagnostics('acc_1', config);
    final native = report.checks.singleWhere(
      (c) => c.id == 'sipkit.native_artifact',
    );
    expect(native.status, SipDiagnosticStatus.failed);
    expect(native.owner, SipDiagnosticOwner.sipkit);
    await engine.dispose();
  });

  test('controlled call timeout is a network-owned failure', () async {
    final engine = _DiagnosticEngine(accountSnapshot: const {});
    final report = await engine.runDiagnostics(
      'acc_1',
      config,
      testTarget: 'sip:echo@provider.test',
      timeout: const Duration(milliseconds: 5),
    );

    final call = report.checks.singleWhere(
      (c) => c.id == 'call.controlled_test',
    );
    expect(call.status, SipDiagnosticStatus.failed);
    expect(call.owner, SipDiagnosticOwner.network);
    expect(engine.hungUpCalls, ['call_test']);
    await engine.dispose();
  });

  test('separates established signaling from active audio media', () async {
    final engine = _DiagnosticEngine(
      accountSnapshot: const {},
      establishCall: true,
      callSnapshot: const {
        'responseCode': 200,
        'responseReason': 'OK',
        'audioMediaActive': true,
        'audioMediaStatus': 'active',
      },
    );
    final report = await engine.runDiagnostics(
      'acc_1',
      config,
      testTarget: 'sip:echo@provider.test',
    );

    expect(
      report.checks.singleWhere((c) => c.id == 'call.controlled_test').status,
      SipDiagnosticStatus.passed,
    );
    expect(
      report.checks.singleWhere((c) => c.id == 'media.audio_path').status,
      SipDiagnosticStatus.passed,
    );
    await engine.dispose();
  });

  test('retains the final SIP response for a rejected INVITE', () async {
    final engine = _DiagnosticEngine(
      accountSnapshot: const {},
      terminateCall: true,
      terminalCode: 403,
      terminalReason: 'Forbidden',
    );
    final report = await engine.runDiagnostics(
      'acc_1',
      config,
      testTarget: 'sip:blocked@provider.test',
    );

    final call = report.checks.singleWhere(
      (c) => c.id == 'call.controlled_test',
    );
    expect(call.status, SipDiagnosticStatus.failed);
    expect(call.evidence['responseCode'], 403);
    expect(call.evidence['finalReason'], 'Forbidden');
    await engine.dispose();
  });

  test(
    'cancellation hangs up the controlled call and returns a report',
    () async {
      final cancellation = SipDiagnosticCancellationToken();
      final engine = _DiagnosticEngine(
        accountSnapshot: const {},
        onMakeCall: cancellation.cancel,
      );

      final report = await engine.runDiagnostics(
        'acc_1',
        config,
        testTarget: 'sip:echo@provider.test',
        cancellationToken: cancellation,
      );

      expect(
        report.checks.singleWhere((c) => c.id == 'session.cancelled').status,
        SipDiagnosticStatus.skipped,
      );
      expect(engine.hungUpCalls, ['call_test']);
      await engine.dispose();
    },
  );
}

class _DiagnosticEngine extends SipEngine {
  _DiagnosticEngine({
    required this.accountSnapshot,
    this.callSnapshot = const {},
    this.establishCall = false,
    this.terminateCall = false,
    this.terminalCode,
    this.terminalReason,
    this.onMakeCall,
  });

  final Map<String, Object?> accountSnapshot;
  final Map<String, Object?> callSnapshot;
  final bool establishCall;
  final bool terminateCall;
  final int? terminalCode;
  final String? terminalReason;
  final void Function()? onMakeCall;
  final hungUpCalls = <String>[];
  final _incoming = StreamController<IncomingCallEvent>.broadcast();
  final _calls = StreamController<CallStateEvent>.broadcast();
  final _accounts = StreamController<AccountStatusEvent>.broadcast();
  final _local = StreamController<(String, MediaStream)>.broadcast();
  final _remote = StreamController<(String, MediaStream)>.broadcast();

  @override
  Future<Map<String, Object?>> diagnosticSnapshot(String accountId) async =>
      accountSnapshot;

  @override
  Future<Map<String, Object?>> diagnosticCallSnapshot(String callId) async =>
      callSnapshot;

  @override
  Future<String> makeCall(
    String accountId,
    String target, {
    bool video = false,
  }) async {
    if (establishCall) {
      scheduleMicrotask(() {
        _calls.add(
          const CallStateEvent(
            callId: 'call_test',
            state: CallState.established,
            reason: 'OK',
          ),
        );
      });
    } else if (terminateCall) {
      scheduleMicrotask(() {
        _calls.add(
          CallStateEvent(
            callId: 'call_test',
            state: CallState.terminated,
            reason: terminalReason,
            code: terminalCode,
          ),
        );
      });
    }
    if (onMakeCall != null) scheduleMicrotask(onMakeCall!);
    return 'call_test';
  }

  @override
  Future<void> hangup(String callId) async {
    hungUpCalls.add(callId);
    scheduleMicrotask(() {
      _calls.add(CallStateEvent(callId: callId, state: CallState.terminated));
    });
  }

  @override
  Future<void> dispose() async {
    await Future.wait([
      _incoming.close(),
      _calls.close(),
      _accounts.close(),
      _local.close(),
      _remote.close(),
    ]);
  }

  @override
  Future<void> init() async {}
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
  Stream<IncomingCallEvent> get incomingCall => _incoming.stream;
  @override
  Stream<CallStateEvent> get callStateChanged => _calls.stream;
  @override
  Stream<AccountStatusEvent> get accountStatusChanged => _accounts.stream;
  @override
  Stream<(String, MediaStream)> get localStream => _local.stream;
  @override
  Stream<(String, MediaStream)> get remoteStream => _remote.stream;
}
