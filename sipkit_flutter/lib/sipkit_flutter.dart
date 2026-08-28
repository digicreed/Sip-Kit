/// SipKit Flutter SDK — Token-licensed SIP/VoIP SDK for Flutter.
///
/// Usage:
/// ```dart
/// import 'package:sipkit_flutter/sipkit_flutter.dart';
/// ```
library sipkit_flutter;

// Errors
export 'src/errors.dart';

// Models
export 'src/models/account_config.dart';
export 'src/models/account_status.dart';
export 'src/models/activation_state.dart';
export 'src/models/call_state.dart';
export 'src/models/call_direction.dart';
export 'src/models/conference.dart';
export 'src/models/entitlement.dart';
export 'src/models/ice_server.dart';
export 'src/models/diagnostic_report.dart';

// Licensing — exported so providers can supply a custom public key (pinning)
// and access the verifier and cache from their own code.
export 'src/licensing/entitlement.dart' show EntitlementVerifier, EntitlementChecks;
export 'src/licensing/entitlement_cache.dart'
    show EntitlementCache, CachedEntitlement;
export 'src/licensing/activation.dart' show ActivationService;

// Engine seam (public extension point)
export 'src/engine/sip_engine.dart';
export 'src/engine/webrtc_engine.dart';
export 'src/engine/pjsip_engine.dart';

// Client layer
export 'src/client/sipkit_client.dart';
export 'src/client/sipkit_account.dart';
export 'src/client/sipkit_call.dart';
