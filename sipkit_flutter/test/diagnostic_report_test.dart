import 'package:flutter_test/flutter_test.dart';
import 'package:sipkit_flutter/sipkit_flutter.dart';

void main() {
  test('diagnostic JSON redacts credential-shaped evidence', () {
    final now = DateTime.utc(2026, 8, 28);
    final report = SipDiagnosticReport(
      reportId: 'diag_test',
      startedAt: now,
      finishedAt: now,
      overallStatus: SipDiagnosticStatus.failed,
      accountId: 'acc_test',
      engine: 'test',
      checks: [
        SipDiagnosticCheck(
          id: 'provider.registration',
          title: 'Registration',
          status: SipDiagnosticStatus.failed,
          owner: SipDiagnosticOwner.provider,
          summary: 'Rejected',
          recommendation: 'Verify credentials',
          startedAt: now,
          durationMs: 10,
          evidence: const {
            'responseCode': 403,
            'password': 'do-not-share',
            'nested': {'authorizationHeader': 'Bearer secret'},
            'responseReason':
                'Forbidden authorization: Basic abc123 token=leak password=hunter2',
            'digestHeader':
                'Authorization: Digest username=alice,response=deadbeef',
            'nativeReason':
                'Digest username=alice, realm=provider, nonce=abc, response=feedface',
            'multilineReason': 'SIP/2.0 403 Forbidden\r\nVia: hidden-route',
          },
        ),
      ],
    );

    final json = report.toPrettyJson();
    expect(json, contains('"responseCode": 403'));
    expect(json, isNot(contains('do-not-share')));
    expect(json, isNot(contains('Bearer secret')));
    expect(json, isNot(contains('abc123')));
    expect(json, isNot(contains('leak')));
    expect(json, isNot(contains('hunter2')));
    expect(json, isNot(contains('deadbeef')));
    expect(json, isNot(contains('feedface')));
    expect(json, isNot(contains('hidden-route')));
    expect(json, contains('[REDACTED]'));
  });

  test('report exposes provider-owned failures', () {
    final now = DateTime.utc(2026, 8, 28);
    final report = SipDiagnosticReport(
      reportId: 'diag_test',
      startedAt: now,
      finishedAt: now,
      overallStatus: SipDiagnosticStatus.failed,
      accountId: 'acc_test',
      engine: 'test',
      checks: [
        SipDiagnosticCheck(
          id: 'provider.registration',
          title: 'Registration',
          status: SipDiagnosticStatus.failed,
          owner: SipDiagnosticOwner.provider,
          summary: 'Rejected',
          recommendation: 'Check the account',
          startedAt: now,
          durationMs: 1,
        ),
      ],
    );
    expect(report.hasProviderAction, isTrue);
  });
}
