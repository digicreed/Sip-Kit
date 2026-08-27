import 'package:flutter_test/flutter_test.dart';
import 'package:sipkit_flutter/sipkit_flutter.dart';

void main() {
  group('SipKitAccountConfig native SIP defaults', () {
    const config = SipKitAccountConfig(
      username: 'alice',
      password: 'secret',
      domain: 'pbx.example.test',
    );

    test('uses UDP and the domain registrar by default', () {
      expect(config.transport, SipTransport.udp);
      expect(config.resolvedRegistrar, 'pbx.example.test');
      expect(config.resolvedSipPort, 5060);
    });

    test('uses secure default TLS port', () {
      const tls = SipKitAccountConfig(
        username: 'alice',
        password: 'secret',
        domain: 'pbx.example.test',
        transport: SipTransport.tls,
      );
      expect(tls.resolvedSipPort, 5061);
      expect(tls.verifyTls, isTrue);
    });

    test('keeps explicit native SIP options', () {
      const explicit = SipKitAccountConfig(
        username: 'alice',
        password: 'secret',
        domain: 'pbx.example.test',
        registrar: 'registrar.example.test',
        sipPort: 5081,
        transport: SipTransport.tcp,
        outboundProxy: 'sip:edge.example.test;lr',
        verifyTls: false,
        tlsCaCertPath: '/secure/provider-ca.pem',
        codecPreferences: ['opus', 'PCMU'],
        keepAliveInterval: 45,
      );
      expect(explicit.resolvedRegistrar, 'registrar.example.test');
      expect(explicit.resolvedSipPort, 5081);
      expect(explicit.codecPreferences, ['opus', 'PCMU']);
      expect(explicit.keepAliveInterval, 45);
    });
  });
}
