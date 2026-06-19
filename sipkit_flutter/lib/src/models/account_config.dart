import 'package:equatable/equatable.dart';
import 'ice_server.dart';

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
    required this.wsUrl,
    this.displayName,
    this.authUsername,
    this.iceServers = const [],
    this.registerOnAdd = true,
    this.registrationExpiry = 600,
    this.userAgent,
  });

  /// SIP username (e.g. `"alice"`).
  final String username;

  /// SIP password.
  final String password;

  /// SIP domain / registrar hostname (e.g. `"pbx.provider.com"`).
  final String domain;

  /// WebSocket URL for SIP transport (e.g. `"wss://pbx.provider.com:8089/ws"`).
  final String wsUrl;

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

  @override
  List<Object?> get props => [
        username,
        password,
        domain,
        wsUrl,
        displayName,
        authUsername,
        iceServers,
        registerOnAdd,
        registrationExpiry,
        userAgent,
      ];
}
