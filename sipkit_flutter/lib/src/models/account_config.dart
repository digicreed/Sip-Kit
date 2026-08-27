import 'package:equatable/equatable.dart';
import 'ice_server.dart';

/// Network transport used by the native [PjsipEngine].
///
/// The WebRTC engine always uses the secure WebSocket URL in [SipKitAccountConfig.wsUrl]
/// instead of this value.
enum SipTransport {
  udp,
  tcp,
  tls;

  String get wireName => name;
}

/// Configuration supplied by the VoIP provider when adding a SIP account.
///
/// SIP credentials are **not** part of the SipKit entitlement — the provider
/// supplies their own username/password/domain.  If you later act as the SIP
/// carrier, slot token-supplied credentials here without changing the API
/// shape (override [username]/[password] from the entitlement JWT).
class SipKitAccountConfig extends Equatable {
  const SipKitAccountConfig({
    required this.username,
    required this.password,
    required this.domain,
    this.wsUrl,
    this.registrar,
    this.sipPort,
    this.transport = SipTransport.udp,
    this.outboundProxy,
    this.verifyTls = true,
    this.tlsCaCertPath,
    this.codecPreferences = const [],
    this.keepAliveInterval = 30,
    this.displayName,
    this.authUsername,
    this.iceServers = const [],
    this.registerOnAdd = true,
    this.registrationExpiry = 600,
    this.userAgent,
  }) : assert(sipPort == null || (sipPort > 0 && sipPort <= 65535)),
       assert(registrationExpiry > 0),
       assert(keepAliveInterval >= 0);

  /// SIP username (e.g. `"alice"`).
  final String username;

  /// SIP password.
  final String password;

  /// SIP domain / registrar hostname (e.g. `"pbx.provider.com"`).
  final String domain;

  /// WebSocket URL used by [WebrtcEngine]
  /// (e.g. `"wss://pbx.provider.com:8089/ws"`).
  ///
  /// This is optional for [PjsipEngine], which uses [registrar], [sipPort], and
  /// [transport]. It remains required at runtime when using [WebrtcEngine].
  final String? wsUrl;

  /// SIP registrar hostname. Defaults to [domain].
  final String? registrar;

  /// SIP registrar port. Defaults to 5061 for TLS and 5060 otherwise.
  final int? sipPort;

  /// UDP, TCP, or TLS transport used by [PjsipEngine].
  final SipTransport transport;

  /// Optional outbound proxy URI, such as `"sip:proxy.example.com;lr"`.
  final String? outboundProxy;

  /// Verify the remote certificate and hostname for TLS transports.
  final bool verifyTls;

  /// Optional path to an additional PEM CA bundle for TLS.
  final String? tlsCaCertPath;

  /// Preferred codec names in priority order (for example `["opus", "PCMU"]`).
  final List<String> codecPreferences;

  /// SIP keepalive interval in seconds. Set to zero to use the PJSIP default.
  final int keepAliveInterval;

  /// Human-readable display name shown in call headers.
  final String? displayName;

  /// Auth username if different from [username].
  final String? authUsername;

  /// ICE/STUN/TURN servers for WebRTC media.
  final List<IceServer> iceServers;

  /// If `true`, the account will register immediately after [SipKitClient.addAccount].
  final bool registerOnAdd;

  /// Registration expiry in seconds (default 600 s).
  final int registrationExpiry;

  /// Override User-Agent header in SIP messages.
  final String? userAgent;

  /// Effective registrar hostname used by the native engine.
  String get resolvedRegistrar => registrar ?? domain;

  /// Effective registrar port used by the native engine.
  int get resolvedSipPort =>
      sipPort ?? (transport == SipTransport.tls ? 5061 : 5060);

  @override
  List<Object?> get props => [
    username,
    password,
    domain,
    wsUrl,
    registrar,
    sipPort,
    transport,
    outboundProxy,
    verifyTls,
    tlsCaCertPath,
    codecPreferences,
    keepAliveInterval,
    displayName,
    authUsername,
    iceServers,
    registerOnAdd,
    registrationExpiry,
    userAgent,
  ];
}
