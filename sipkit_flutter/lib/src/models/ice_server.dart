import 'package:equatable/equatable.dart';

/// An ICE / STUN / TURN server configuration for WebRTC media establishment.
class IceServer extends Equatable {
  const IceServer({
    required this.url,
    this.username,
    this.credential,
  });

  final String url;
  final String? username;
  final String? credential;

  Map<String, dynamic> toMap() => {
        'url': url,
        if (username != null) 'username': username,
        if (credential != null) 'credential': credential,
      };

  @override
  List<Object?> get props => [url, username, credential];
}
