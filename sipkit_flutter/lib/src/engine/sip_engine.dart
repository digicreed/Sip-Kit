import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../models/account_config.dart';
import '../models/account_status.dart';
import '../models/call_direction.dart';
import '../models/call_state.dart';
import '../models/diagnostic_report.dart';

// ---------------------------------------------------------------------------
// SipEngine — PUBLIC STABLE EXTENSION POINT
// ---------------------------------------------------------------------------
//
// `SipEngine` is the adapter seam between the SipKit public API and the
// underlying SIP transport/media stack.  SipKit ships two built-in engines:
//
//   • WebrtcEngine  — sip_ua + flutter_webrtc.  Works on all Flutter targets
//                     (iOS, Android, macOS, Windows, Linux) in the foreground.
//                     No native code required.
//
//   • PjsipEngine   — PJSUA2 via Flutter platform channels.  Enables true
//                     background calling, CallKit (iOS), and ConnectionService
//                     (Android).  Requires the bundled Swift/Kotlin plugin.
//
// PROVIDERS MAY IMPLEMENT THEIR OWN ENGINE by subclassing `SipEngine`.  This
// lets you plug in a proprietary SIP stack, a cloud CPaaS SDK, or a custom
// transport without changing a single line of provider-facing API.
//
//   class MyCpaasSipEngine extends SipEngine {
//     @override Future<void> init() async { /* ... */ }
//     // ... implement all abstract members
//   }
//
//   final client = SipKitClient(engine: MyCpaasSipEngine());
//
// IMPORTANT — LICENSING:
//   Token gating is applied by `SipKitClient` before any engine method is
//   called, so custom engines do not duplicate those checks in an unmodified
//   SDK. GPL recipients may modify the covered source.
//
// STREAM CONTRACTS:
//   All broadcast streams must remain open for the lifetime of the engine
//   instance.  `dispose()` must close all stream controllers.
// ---------------------------------------------------------------------------

/// Event emitted when the account registration status changes.
class AccountStatusEvent {
  const AccountStatusEvent({
    required this.accountId,
    required this.status,
    this.reason,
  });

  final String accountId;
  final AccountStatus status;
  final String? reason;
}

/// Event emitted when a call's state changes.
class CallStateEvent {
  const CallStateEvent({
    required this.callId,
    required this.state,
    this.reason,
    this.code,
  });

  final String callId;
  final CallState state;
  final String? reason;
  final int? code;
}

/// Event emitted when an incoming call arrives.
class IncomingCallEvent {
  const IncomingCallEvent({
    required this.callId,
    required this.accountId,
    required this.remoteUri,
    required this.displayName,
    this.hasVideo = false,
  });

  final String callId;
  final String accountId;
  final String remoteUri;
  final String displayName;
  final bool hasVideo;
}

/// Abstract adapter between [SipKitClient] and a concrete SIP/media stack.
///
/// All methods are guarded by licensing checks in [SipKitClient] before they
/// are dispatched here — engines must not perform their own entitlement checks.
abstract class SipEngine {
  // ─── Lifecycle ─────────────────────────────────────────────────────────────

  /// Initialise the engine.  Called once by [SipKitClient] before any account
  /// or call operations.
  Future<void> init();

  /// Release all resources held by the engine.  After this call the engine
  /// must not emit further events.
  Future<void> dispose();

  // ─── Account management ────────────────────────────────────────────────────

  /// Register a SIP account described by [config].  The engine must use
  /// [accountId] as the stable identifier for subsequent calls.
  Future<void> registerAccount(String accountId, SipKitAccountConfig config);

  /// Send a REGISTER with `expires=0` for [accountId].
  Future<void> unregister(String accountId);

  // ─── Call management ───────────────────────────────────────────────────────

  /// Place an outbound call from [accountId] to [target] (a full SIP URI or
  /// phone number).  Returns a stable [callId] for the new call.
  Future<String> makeCall(
    String accountId,
    String target, {
    bool video = false,
  });

  /// Answer an incoming call identified by [callId].
  Future<void> answer(String callId, {bool video = false});

  /// Terminate a call (BYE / CANCEL depending on state).
  Future<void> hangup(String callId);

  /// Put the call on hold (`a=inactive` / `sendonly`).
  Future<void> hold(String callId);

  /// Resume a held call.
  Future<void> unhold(String callId);

  /// Mute or unmute the local microphone.
  Future<void> mute(String callId, {required bool muted});

  /// Send one or more DTMF digits via RFC 2833 INFO.
  Future<void> sendDtmf(String callId, String digits);

  /// Initiate a blind (unattended) transfer to [targetUri].
  Future<void> blindTransfer(String callId, String targetUri);

  /// Initiate an attended transfer: [callId] is transferred to [otherCallId].
  Future<void> attendedTransfer(String callId, String otherCallId);

  /// Enable or disable the video track on an established call.
  /// Throws if the engine does not support video for the current platform.
  Future<void> enableVideo(String callId, {required bool enabled});

  /// Run opt-in provider troubleshooting checks.
  ///
  /// Implementations may add native evidence through
  /// [diagnosticSnapshot]. The optional [testTarget] places one real
  /// controlled call and waits for its signaling result.
  Future<SipDiagnosticReport> runDiagnostics(
    String accountId,
    SipKitAccountConfig config, {
    String? testTarget,
    Duration timeout = const Duration(seconds: 15),
    SipDiagnosticCancellationToken? cancellationToken,
  }) async {
    final startedAt = DateTime.now().toUtc();
    final checks = <SipDiagnosticCheck>[];

    _addDiagnostic(
      checks,
      id: 'sdk.account_config',
      title: 'Account configuration',
      owner: SipDiagnosticOwner.sipkit,
      passed:
          config.username.trim().isNotEmpty &&
          config.password.isNotEmpty &&
          config.domain.trim().isNotEmpty,
      summary:
          config.username.trim().isNotEmpty &&
              config.password.isNotEmpty &&
              config.domain.trim().isNotEmpty
          ? 'Required SIP account fields are present.'
          : 'A required SIP account field is missing.',
      recommendation:
          'Check the SIP username, password, and domain supplied by the provider.',
      startedAt: startedAt,
      evidence: {
        'accountId': accountId,
        'domain': config.domain,
        'transport': config.transport.wireName,
        'registrar': _safeSipEndpoint(config.resolvedRegistrar),
        'sipPort': config.resolvedSipPort,
        'tlsVerification': config.verifyTls,
      },
    );

    final tlsPolicySafe =
        config.transport != SipTransport.tls || config.verifyTls;
    _addDiagnostic(
      checks,
      id: 'network.tls_policy',
      title: 'TLS verification policy',
      owner: SipDiagnosticOwner.network,
      passed: tlsPolicySafe,
      status: tlsPolicySafe
          ? SipDiagnosticStatus.passed
          : SipDiagnosticStatus.warning,
      summary: config.transport != SipTransport.tls
          ? 'TLS is not selected for this SIP transport.'
          : config.verifyTls
          ? 'Server certificate verification is enabled.'
          : 'Server certificate verification is disabled.',
      recommendation: tlsPolicySafe
          ? 'No action required.'
          : 'Enable TLS verification and install the provider CA chain if it is not publicly trusted.',
      startedAt: startedAt,
      evidence: {
        'transport': config.transport.wireName,
        'verifyServerCertificate': config.verifyTls,
        'customCaConfigured': config.tlsCaCertPath?.isNotEmpty == true,
      },
    );

    if (diagnosticEngineName == 'WebrtcEngine') {
      _addDiagnostic(
        checks,
        id: 'network.websocket_url',
        title: 'SIP WebSocket configuration',
        owner: SipDiagnosticOwner.provider,
        passed: config.wsUrl?.trim().isNotEmpty == true,
        summary: config.wsUrl?.trim().isNotEmpty == true
            ? 'The SIP WebSocket URL is configured.'
            : 'The WebRTC engine has no SIP WebSocket URL.',
        recommendation:
            'Ask the provider for the correct secure SIP WebSocket URL and port.',
        startedAt: startedAt,
        evidence: {
          'scheme': config.wsUrl == null
              ? null
              : Uri.tryParse(config.wsUrl!)?.scheme,
        },
      );
    }

    Map<String, Object?> snapshot = const {};
    try {
      snapshot = await diagnosticSnapshot(accountId);
      _addNativeChecks(checks, snapshot, startedAt);
    } catch (error) {
      _addDiagnostic(
        checks,
        id: 'sipkit.native_diagnostics',
        title: 'Native diagnostic bridge',
        owner: SipDiagnosticOwner.sipkit,
        passed: false,
        summary: 'SipKit could not collect native SIP diagnostics.',
        recommendation:
            'Confirm that the native PJSIP artifact is bundled and that the account was initialized before running diagnostics.',
        startedAt: startedAt,
        evidence: {'errorType': error.runtimeType.toString()},
      );
    }

    if (cancellationToken?.isCancelled == true) {
      _addDiagnostic(
        checks,
        id: 'session.cancelled',
        title: 'Diagnostic session',
        owner: SipDiagnosticOwner.unknown,
        passed: true,
        status: SipDiagnosticStatus.skipped,
        summary: 'The diagnostic session was cancelled before the test call.',
        recommendation:
            'Run a new opt-in session when the account is ready for testing.',
        startedAt: startedAt,
      );
    } else if (testTarget != null && testTarget.trim().isNotEmpty) {
      checks.addAll(
        await _runControlledCall(
          accountId,
          testTarget.trim(),
          timeout,
          cancellationToken,
        ),
      );
    } else {
      _addDiagnostic(
        checks,
        id: 'call.controlled_test',
        title: 'Controlled test call',
        owner: SipDiagnosticOwner.unknown,
        passed: true,
        status: SipDiagnosticStatus.skipped,
        summary: 'No test destination was supplied.',
        recommendation:
            'Run diagnostics again with a provider echo, voicemail, or test destination to verify call signaling and media.',
        startedAt: startedAt,
      );
    }

    final finishedAt = DateTime.now().toUtc();
    final overallStatus =
        checks.any((c) => c.status == SipDiagnosticStatus.failed)
        ? SipDiagnosticStatus.failed
        : checks.any((c) => c.status == SipDiagnosticStatus.warning)
        ? SipDiagnosticStatus.warning
        : SipDiagnosticStatus.passed;
    return SipDiagnosticReport(
      reportId: 'diag_${finishedAt.millisecondsSinceEpoch}',
      startedAt: startedAt,
      finishedAt: finishedAt,
      overallStatus: overallStatus,
      accountId: accountId,
      engine: diagnosticEngineName,
      platform: snapshot['platform'] as String? ?? 'unknown',
      checks: List.unmodifiable(checks),
    );
  }

  /// Native engines override this to return safe, structured SIP evidence.
  Future<Map<String, Object?>> diagnosticSnapshot(String accountId) async => {};

  /// Native engines may expose safe, post-INVITE state for a controlled call.
  Future<Map<String, Object?>> diagnosticCallSnapshot(String callId) async =>
      {};

  String get diagnosticEngineName => runtimeType.toString();

  void _addNativeChecks(
    List<SipDiagnosticCheck> checks,
    Map<String, Object?> snapshot,
    DateTime startedAt,
  ) {
    final nativeAvailable = snapshot['nativeAvailable'];
    if (nativeAvailable is bool) {
      _addDiagnostic(
        checks,
        id: 'sipkit.native_artifact',
        title: 'Native SIP engine',
        owner: SipDiagnosticOwner.sipkit,
        passed: nativeAvailable,
        summary: nativeAvailable
            ? 'The native SIP engine is available.'
            : 'The native SIP engine is unavailable.',
        recommendation: nativeAvailable
            ? 'No action required.'
            : 'Bundle the PJSIP AAR/XCFramework built from the SipKit instructions.',
        startedAt: startedAt,
        evidence: {'available': nativeAvailable},
      );
    }
    if (snapshot['accountPresent'] is bool) {
      final present = snapshot['accountPresent'] as bool;
      _addDiagnostic(
        checks,
        id: 'sip.account_present',
        title: 'Native SIP account',
        owner: present
            ? SipDiagnosticOwner.sipkit
            : SipDiagnosticOwner.provider,
        passed: present,
        summary: present
            ? 'The native SIP account is loaded.'
            : 'The native SIP account is not loaded.',
        recommendation: present
            ? 'No action required.'
            : 'Initialize the account before running provider diagnostics.',
        startedAt: startedAt,
      );
    }
    if (snapshot['transport'] is String) {
      _addDiagnostic(
        checks,
        id: 'network.transport_config',
        title: 'SIP transport configuration',
        owner: SipDiagnosticOwner.network,
        passed: true,
        summary: 'The ${snapshot['transport']} transport is configured.',
        recommendation: 'No action required.',
        startedAt: startedAt,
        evidence: {
          'transport': snapshot['transport'],
          'registrar': _safeSipEndpoint(snapshot['registrar']),
          'sipPort': snapshot['sipPort'],
        },
      );
    }
    final registrationCode = snapshot['registrationCode'];
    final registrationActive = snapshot['registrationActive'] == true;
    if (registrationCode is num || snapshot['registrationReason'] != null) {
      final code = registrationCode is num ? registrationCode.toInt() : 0;
      final passed = registrationActive || (code >= 200 && code < 300);
      final providerFailure = code >= 300 && code < 700;
      _addDiagnostic(
        checks,
        id: 'network.registrar_reachability',
        title: 'Registrar DNS and reachability',
        owner: SipDiagnosticOwner.network,
        passed: code > 0,
        status: code > 0
            ? SipDiagnosticStatus.passed
            : SipDiagnosticStatus.warning,
        summary: code > 0
            ? 'A SIP response was received from the registrar path.'
            : 'No SIP response is available to prove registrar reachability.',
        recommendation: code > 0
            ? 'No action required.'
            : 'Verify DNS, the registrar port and transport, firewall rules, and the device network.',
        startedAt: startedAt,
        evidence: {'sipResponseObserved': code > 0},
      );
      _addDiagnostic(
        checks,
        id: 'provider.registration',
        title: 'SIP registration',
        owner: passed
            ? SipDiagnosticOwner.provider
            : providerFailure
            ? SipDiagnosticOwner.provider
            : SipDiagnosticOwner.network,
        passed: passed,
        status: passed
            ? SipDiagnosticStatus.passed
            : code == 0
            ? SipDiagnosticStatus.warning
            : SipDiagnosticStatus.failed,
        summary: passed
            ? 'The provider accepted SIP registration.'
            : code == 0
            ? 'No final SIP registration response has been observed yet.'
            : 'The provider returned SIP registration code $code.',
        recommendation: passed
            ? 'No action required.'
            : code == 401 || code == 403
            ? 'Verify the SIP username, authentication username, password, and provider authentication policy.'
            : code == 404
            ? 'Verify the SIP domain and registrar address with the provider.'
            : code >= 500
            ? 'Ask the provider to inspect registrar availability and account service status.'
            : 'Check the registrar hostname, port, transport, firewall, and NAT path.',
        startedAt: startedAt,
        durationMs: snapshot['registrationDurationMs'] is num
            ? (snapshot['registrationDurationMs'] as num).toInt()
            : null,
        evidence: {
          'responseCode': code,
          'responseReason': snapshot['registrationReason'],
          'active': registrationActive,
        },
      );
    }
    if (snapshot['audioAvailable'] is bool) {
      final available = snapshot['audioAvailable'] as bool;
      _addDiagnostic(
        checks,
        id: 'device.audio',
        title: 'Audio device readiness',
        owner: SipDiagnosticOwner.device,
        passed: available,
        summary: available
            ? 'The native audio device is available.'
            : 'The native audio device is unavailable.',
        recommendation: available
            ? 'No action required.'
            : 'Grant microphone permission, connect an audio route, and retry on a physical device.',
        startedAt: startedAt,
      );
    }
    if (snapshot['microphonePermission'] is bool) {
      final granted = snapshot['microphonePermission'] as bool;
      _addDiagnostic(
        checks,
        id: 'device.microphone_permission',
        title: 'Microphone permission',
        owner: SipDiagnosticOwner.device,
        passed: granted,
        summary: granted
            ? 'The operating system granted microphone access.'
            : 'The operating system has not granted microphone access.',
        recommendation: granted
            ? 'No action required.'
            : 'Grant microphone permission in the app or system settings, then rerun diagnostics.',
        startedAt: startedAt,
      );
    }
    if (snapshot['telecomPermission'] is bool) {
      final granted = snapshot['telecomPermission'] as bool;
      _addDiagnostic(
        checks,
        id: 'device.telecom_permission',
        title: 'Android Telecom permission',
        owner: SipDiagnosticOwner.device,
        passed: granted,
        summary: granted
            ? 'Android allows SipKit to place self-managed calls.'
            : 'Android Telecom permission is missing.',
        recommendation: granted
            ? 'No action required.'
            : 'Grant MANAGE_OWN_CALLS before placing the controlled test call.',
        startedAt: startedAt,
      );
    }
  }

  Future<List<SipDiagnosticCheck>> _runControlledCall(
    String accountId,
    String target,
    Duration timeout,
    SipDiagnosticCancellationToken? cancellationToken,
  ) async {
    final startedAt = DateTime.now().toUtc();
    String? callId;
    CallState? finalState;
    String? finalReason;
    int? finalCode;
    var establishedObserved = false;
    final finished = Completer<void>();
    final terminated = Completer<void>();
    final earlyEvents = <CallStateEvent>[];
    void accept(CallStateEvent event) {
      finalState = event.state;
      finalReason = event.reason;
      finalCode = event.code;
      if (event.state == CallState.established) establishedObserved = true;
      if (event.state == CallState.terminated && !terminated.isCompleted) {
        terminated.complete();
      }
      if (event.state == CallState.established ||
          event.state == CallState.terminated) {
        if (!finished.isCompleted) finished.complete();
      }
    }

    final subscription = callStateChanged.listen((event) {
      if (callId == null) {
        earlyEvents.add(event);
      } else if (event.callId == callId) {
        accept(event);
      }
    });
    try {
      callId = await makeCall(accountId, target);
      for (final event in earlyEvents) {
        if (event.callId == callId) accept(event);
      }
      if (cancellationToken == null) {
        await finished.future.timeout(timeout);
      } else {
        await Future.any<void>([
          finished.future.timeout(timeout),
          cancellationToken.whenCancelled.then(
            (_) => throw const _SipDiagnosticCancelled(),
          ),
        ]);
      }
      final passed = establishedObserved;
      final signaling = _check(
        id: 'call.controlled_test',
        title: 'Controlled test call',
        status: passed
            ? SipDiagnosticStatus.passed
            : SipDiagnosticStatus.failed,
        owner: passed
            ? SipDiagnosticOwner.provider
            : SipDiagnosticOwner.provider,
        summary: passed
            ? 'The call reached the established state.'
            : 'The call did not reach the established state.',
        recommendation: passed
            ? 'Registration and basic call signaling reached the provider.'
            : 'Ask the provider to inspect INVITE routing, destination permissions, trunk status, and the final SIP response.',
        startedAt: startedAt,
        evidence: {
          'targetKind': _targetKind(target),
          'finalState': finalState?.name,
          'finalReason': finalReason,
          'responseCode': finalCode,
        },
      );
      if (!passed || callId == null) return [signaling];
      try {
        final callSnapshot = await diagnosticCallSnapshot(callId);
        final audioActive = callSnapshot['audioMediaActive'] == true;
        return [
          signaling,
          _check(
            id: 'media.audio_path',
            title: 'Negotiated audio media',
            status: audioActive
                ? SipDiagnosticStatus.passed
                : SipDiagnosticStatus.warning,
            owner: audioActive
                ? SipDiagnosticOwner.provider
                : SipDiagnosticOwner.provider,
            summary: audioActive
                ? 'PJSIP reports an active negotiated audio stream.'
                : 'The call connected, but an active audio stream was not observed.',
            recommendation: audioActive
                ? 'Confirm audible two-way media on the physical device.'
                : 'Check SDP codec overlap, RTP firewall/NAT rules, and the provider media relay.',
            startedAt: startedAt,
            evidence: callSnapshot,
          ),
        ];
      } catch (error) {
        return [
          signaling,
          _check(
            id: 'media.audio_path',
            title: 'Negotiated audio media',
            status: SipDiagnosticStatus.warning,
            owner: SipDiagnosticOwner.sipkit,
            summary:
                'The call connected, but media state could not be collected.',
            recommendation:
                'Confirm two-way audio manually and attach native logs if media is silent.',
            startedAt: startedAt,
            evidence: {'errorType': error.runtimeType.toString()},
          ),
        ];
      }
    } on _SipDiagnosticCancelled {
      return [
        _check(
          id: 'session.cancelled',
          title: 'Diagnostic session',
          status: SipDiagnosticStatus.skipped,
          owner: SipDiagnosticOwner.unknown,
          summary: 'The controlled test call was cancelled.',
          recommendation:
              'Run a new opt-in session if provider call evidence is still needed.',
          startedAt: startedAt,
          evidence: {'targetKind': _targetKind(target)},
        ),
      ];
    } on TimeoutException {
      return [
        _check(
          id: 'call.controlled_test',
          title: 'Controlled test call',
          status: SipDiagnosticStatus.failed,
          owner: SipDiagnosticOwner.network,
          summary:
              'No established or terminated result arrived before the timeout.',
          recommendation:
              'Check firewall/NAT behavior and ask the provider for the INVITE transaction and response code.',
          startedAt: startedAt,
          evidence: {
            'targetKind': _targetKind(target),
            'timeoutSeconds': timeout.inSeconds,
          },
        ),
      ];
    } catch (error) {
      return [
        _check(
          id: 'call.controlled_test',
          title: 'Controlled test call',
          status: SipDiagnosticStatus.failed,
          owner: SipDiagnosticOwner.sipkit,
          summary: 'SipKit could not start the controlled test call.',
          recommendation:
              'Resolve the displayed SDK/device error before asking the provider to investigate call routing.',
          startedAt: startedAt,
          evidence: {
            'targetKind': _targetKind(target),
            'errorType': error.runtimeType.toString(),
          },
        ),
      ];
    } finally {
      if (callId != null && finalState != CallState.terminated) {
        try {
          await hangup(callId);
        } catch (_) {}
        try {
          await terminated.future.timeout(const Duration(seconds: 2));
        } on TimeoutException {
          // Bound cleanup so a broken native callback cannot stall diagnostics.
        }
      }
      await subscription.cancel();
    }
  }

  static SipDiagnosticCheck _check({
    required String id,
    required String title,
    required SipDiagnosticStatus status,
    required SipDiagnosticOwner owner,
    required String summary,
    required String recommendation,
    required DateTime startedAt,
    Map<String, Object?> evidence = const {},
    int? durationMs,
  }) => SipDiagnosticCheck(
    id: id,
    title: title,
    status: status,
    owner: owner,
    summary: summary,
    recommendation: recommendation,
    startedAt: startedAt,
    durationMs:
        durationMs ??
        DateTime.now().toUtc().difference(startedAt).inMilliseconds,
    evidence: evidence,
  );

  static void _addDiagnostic(
    List<SipDiagnosticCheck> checks, {
    required String id,
    required String title,
    required SipDiagnosticOwner owner,
    required bool passed,
    required String summary,
    required String recommendation,
    required DateTime startedAt,
    SipDiagnosticStatus? status,
    Map<String, Object?> evidence = const {},
    int? durationMs,
  }) {
    checks.add(
      _check(
        id: id,
        title: title,
        status:
            status ??
            (passed ? SipDiagnosticStatus.passed : SipDiagnosticStatus.failed),
        owner: owner,
        summary: summary,
        recommendation: recommendation,
        startedAt: startedAt,
        evidence: evidence,
        durationMs: durationMs,
      ),
    );
  }

  static String _targetKind(String target) =>
      target.startsWith('sip:') || target.startsWith('sips:')
      ? 'sipUri'
      : 'dialString';

  static String _safeSipEndpoint(Object? value) {
    if (value == null) return '';
    var endpoint = value.toString().trim();
    endpoint = endpoint.replaceFirst(RegExp(r'^sips?:'), '');
    endpoint = endpoint.split('@').last;
    return endpoint.split(';').first;
  }

  // ─── Streams ───────────────────────────────────────────────────────────────

  /// Emits [IncomingCallEvent] for every incoming call.
  Stream<IncomingCallEvent> get incomingCall;

  /// Emits [CallStateEvent] whenever a call's state changes.
  Stream<CallStateEvent> get callStateChanged;

  /// Emits [AccountStatusEvent] whenever an account's registration status
  /// changes.
  Stream<AccountStatusEvent> get accountStatusChanged;

  /// Emits the local [MediaStream] when it becomes available for [callId].
  Stream<(String callId, MediaStream stream)> get localStream;

  /// Emits the remote [MediaStream] when it becomes available for [callId].
  Stream<(String callId, MediaStream stream)> get remoteStream;
}

class _SipDiagnosticCancelled implements Exception {
  const _SipDiagnosticCancelled();
}
