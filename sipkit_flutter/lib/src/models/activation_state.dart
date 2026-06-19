/// The lifecycle state of the SipKit client's licensing activation.
enum ActivationState {
  /// [SipKitClient.activate] has not been called yet.
  unactivated,

  /// [SipKitClient.activate] is in flight — contacting the licensing backend.
  activating,

  /// A valid entitlement JWT is held (or within the offline grace window).
  /// All SIP operations are unlocked.
  active,

  /// The entitlement JWT has expired and no cached token covers the grace
  /// window.  The client will attempt a refresh; if it fails, it transitions
  /// to [locked].
  expired,

  /// The entitlement is revoked or the grace window has elapsed.  All SIP
  /// operations throw [ActivationError] until [SipKitClient.activate] is
  /// called again with a valid key.
  locked,
}
