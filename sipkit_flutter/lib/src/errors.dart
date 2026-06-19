/// Base class for all SipKit errors.
abstract class SipKitError implements Exception {
  const SipKitError(this.message);
  final String message;
  @override
  String toString() => '$runtimeType: $message';
}

/// Thrown when the entitlement JWT is missing, expired, or revoked, and the
/// offline grace window has also elapsed.
class ActivationError extends SipKitError {
  const ActivationError(super.message);
}

/// Thrown when an operation is attempted that the current entitlement does
/// not permit — e.g. [SipKitCall.enableVideo] when `features` lacks `"video"`,
/// or [SipKitClient.addAccount] when `maxAccounts` is reached.
class NotEntitledError extends SipKitError {
  const NotEntitledError(super.message);
}

/// Thrown when [SipKitClient.activate] receives a network or HTTP error.
class NetworkError extends SipKitError {
  const NetworkError(super.message, {this.statusCode});
  final int? statusCode;
}

/// Thrown when a SIP operation fails at the engine level (e.g. registration
/// rejected by the server, call already terminated).
class SipError extends SipKitError {
  const SipError(super.message, {this.code});
  final String? code;
}

/// Thrown when [SipKitClient.mergeCalls] is called but the `"conference"`
/// feature is not present in the current entitlement.
class ConferenceNotEntitledError extends NotEntitledError {
  const ConferenceNotEntitledError()
      : super('Conference is not enabled in your current entitlement. '
            'Contact your SipKit provider to upgrade.');
}
