import 'dart:convert';
import 'dart:async';

enum SipDiagnosticStatus { passed, warning, failed, skipped }

enum SipDiagnosticOwner { sipkit, device, network, provider, unknown }

class SipDiagnosticCancellationToken {
  final Completer<void> _cancelled = Completer<void>();

  bool get isCancelled => _cancelled.isCompleted;
  Future<void> get whenCancelled => _cancelled.future;

  void cancel() {
    if (!_cancelled.isCompleted) _cancelled.complete();
  }
}

extension SipDiagnosticStatusName on SipDiagnosticStatus {
  String get wireName => name;
}

extension SipDiagnosticOwnerName on SipDiagnosticOwner {
  String get wireName => name;
}

class SipDiagnosticCheck {
  const SipDiagnosticCheck({
    required this.id,
    required this.title,
    required this.status,
    required this.owner,
    required this.summary,
    required this.recommendation,
    required this.startedAt,
    required this.durationMs,
    this.evidence = const {},
  });

  final String id;
  final String title;
  final SipDiagnosticStatus status;
  final SipDiagnosticOwner owner;
  final String summary;
  final String recommendation;
  final DateTime startedAt;
  final int durationMs;
  final Map<String, Object?> evidence;

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'status': status.wireName,
    'owner': owner.wireName,
    'summary': summary,
    'recommendation': recommendation,
    'startedAt': startedAt.toUtc().toIso8601String(),
    'durationMs': durationMs,
    'evidence': _redact(evidence),
  };
}

class SipDiagnosticReport {
  const SipDiagnosticReport({
    required this.reportId,
    required this.startedAt,
    required this.finishedAt,
    required this.overallStatus,
    required this.accountId,
    required this.engine,
    required this.checks,
    this.sdkVersion = '0.1.0',
    this.platform = 'unknown',
  });

  final String reportId;
  final DateTime startedAt;
  final DateTime finishedAt;
  final SipDiagnosticStatus overallStatus;
  final String accountId;
  final String engine;
  final List<SipDiagnosticCheck> checks;
  final String sdkVersion;
  final String platform;

  Map<String, Object?> toJson() => {
    'schemaVersion': 1,
    'reportId': reportId,
    'startedAt': startedAt.toUtc().toIso8601String(),
    'finishedAt': finishedAt.toUtc().toIso8601String(),
    'overallStatus': overallStatus.wireName,
    'accountId': accountId,
    'engine': engine,
    'sdkVersion': sdkVersion,
    'platform': platform,
    'checks': checks.map((check) => check.toJson()).toList(),
  };

  String toPrettyJson() => const JsonEncoder.withIndent('  ').convert(toJson());

  bool get hasProviderAction => checks.any(
    (check) =>
        check.status == SipDiagnosticStatus.failed &&
        check.owner == SipDiagnosticOwner.provider,
  );
}

Map<String, Object?> _redact(Map<String, Object?> source) {
  const sensitiveParts = [
    'password',
    'secret',
    'token',
    'private',
    'credential',
    'authorization',
    'auth',
    'header',
    'payload',
  ];
  final result = <String, Object?>{};
  for (final entry in source.entries) {
    final key = entry.key.toLowerCase();
    if (sensitiveParts.any(key.contains)) {
      result[entry.key] = '[REDACTED]';
    } else {
      result[entry.key] = _redactValue(entry.value);
    }
  }
  return result;
}

Object? _redactValue(Object? value) {
  if (value is Map) {
    return _redact(value.map((key, value) => MapEntry(key.toString(), value)));
  }
  if (value is Iterable) return value.map(_redactValue).toList();
  if (value is String) return _sanitizeString(value);
  return value;
}

String _sanitizeString(String value) {
  if (value.contains('\r') || value.contains('\n')) return '[REDACTED]';
  if (RegExp(
    r'\b(authorization|proxy-authorization|www-authenticate|proxy-authenticate)\s*:',
    caseSensitive: false,
  ).hasMatch(value)) {
    return '[REDACTED]';
  }
  if (RegExp(
    r'\b(Digest|Bearer|Basic)\s+',
    caseSensitive: false,
  ).hasMatch(value)) {
    return '[REDACTED]';
  }
  var sanitized = value.replaceAll(RegExp(r'[\r\n]+'), ' ');
  sanitized = sanitized.replaceAllMapped(
    RegExp(r'\b(Bearer|Basic)\s+[A-Za-z0-9._~+/=-]+', caseSensitive: false),
    (match) => '${match.group(1)} [REDACTED]',
  );
  sanitized = sanitized.replaceAllMapped(
    RegExp(
      r'\b(password|passwd|pwd|token|secret|credential|authorization|proxy-authorization|private[ _-]?key)\b\s*[:=]\s*("[^"]*"|[^,;\s]+)',
      caseSensitive: false,
    ),
    (match) => '${match.group(1)}=[REDACTED]',
  );
  if (sanitized.length > 512) {
    sanitized = '${sanitized.substring(0, 512)}…';
  }
  return sanitized;
}
