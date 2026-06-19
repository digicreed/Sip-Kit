/// Registration status of a [SipKitAccount].
enum AccountStatus {
  /// The account has not attempted registration yet.
  unregistered,

  /// A REGISTER request is in flight.
  registering,

  /// Successfully registered with the SIP registrar.
  registered,

  /// The last registration attempt failed (network error, auth failure, etc.).
  failed,
}
