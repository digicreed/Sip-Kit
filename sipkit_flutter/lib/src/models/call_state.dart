/// State of an individual [SipKitCall].
enum CallState {
  /// Outgoing call being set up (INVITE sent / not yet ringing).
  connecting,

  /// Remote side is ringing (180 Ringing received).
  ringing,

  /// Early media is flowing (183 Session Progress).
  earlyMedia,

  /// Call is fully established (200 OK / ACK exchanged).
  established,

  /// Call is on hold (local or remote).
  held,

  /// Call has ended (BYE, CANCEL, or error).
  terminated,
}
