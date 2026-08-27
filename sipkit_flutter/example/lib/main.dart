import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sipkit_flutter/sipkit_flutter.dart';

void main() => runApp(const ProviderExampleApp());

class ProviderExampleApp extends StatelessWidget {
  const ProviderExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: const ProviderCallPage(),
    );
  }
}

class ProviderCallPage extends StatefulWidget {
  const ProviderCallPage({super.key});

  @override
  State<ProviderCallPage> createState() => _ProviderCallPageState();
}

class _ProviderCallPageState extends State<ProviderCallPage> {
  final _licenseKey = TextEditingController();
  final _baseUrl = TextEditingController(text: 'https://license.example.com');
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _domain = TextEditingController();
  final _registrar = TextEditingController();
  final _target = TextEditingController();

  late final SipKitClient _client = SipKitClient(engine: PjsipEngine());
  StreamSubscription<SipKitCall>? _incomingSubscription;
  StreamSubscription<AccountStatus>? _accountSubscription;
  StreamSubscription<CallState>? _callSubscription;
  SipKitAccount? _account;
  SipKitCall? _call;
  String _status = 'Not initialized';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _incomingSubscription = _client.incomingCalls.listen((call) {
      _attachCall(call);
      _setStatus('Incoming call from ${call.remoteUri}');
    });
  }

  Future<void> _activateAndRegister() async {
    await _run(() async {
      await _client.activate(
        licenseKey: _licenseKey.text.trim(),
        baseUrl: _baseUrl.text.trim(),
        appId: 'com.sipkit.nativeProviderExample',
        deviceId: 'replace-with-a-stable-device-id',
      );
      final account = await _client.addAccount(
        SipKitAccountConfig(
          username: _username.text.trim(),
          password: _password.text,
          domain: _domain.text.trim(),
          registrar: _registrar.text.trim().isEmpty
              ? null
              : _registrar.text.trim(),
          transport: SipTransport.tls,
          sipPort: 5061,
          verifyTls: true,
          registerOnAdd: true,
        ),
      );
      await _accountSubscription?.cancel();
      _accountSubscription = account.status.listen(
        (status) => _setStatus('Registration: ${status.name}'),
      );
      setState(() => _account = account);
      _setStatus('REGISTER sent; waiting for provider callback');
    });
  }

  Future<void> _placeCall() async {
    final account = _account;
    if (account == null) {
      _setStatus('Register an account first');
      return;
    }
    await _run(() async {
      final call = await _client.makeCall(account.id, _target.text.trim());
      _attachCall(call);
    });
  }

  void _attachCall(SipKitCall call) {
    _callSubscription?.cancel();
    _callSubscription = call.state.listen(
      (state) => _setStatus('Call: ${state.name}'),
    );
    setState(() => _call = call);
  }

  Future<void> _run(Future<void> Function() operation) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await operation();
    } catch (error) {
      _setStatus('Error: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _setStatus(String value) {
    if (mounted) setState(() => _status = value);
  }

  @override
  void dispose() {
    _incomingSubscription?.cancel();
    _accountSubscription?.cancel();
    _callSubscription?.cancel();
    _client.dispose();
    for (final controller in [
      _licenseKey,
      _baseUrl,
      _username,
      _password,
      _domain,
      _registrar,
      _target,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final call = _call;
    return Scaffold(
      appBar: AppBar(title: const Text('SipKit native provider test')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(_status, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          _field(_licenseKey, 'License key', secret: true),
          _field(_baseUrl, 'License service URL'),
          const Divider(height: 32),
          _field(_username, 'SIP username'),
          _field(_password, 'SIP password', secret: true),
          _field(_domain, 'SIP domain'),
          _field(_registrar, 'Registrar (optional)'),
          FilledButton(
            onPressed: _busy ? null : _activateAndRegister,
            child: const Text('Activate & register'),
          ),
          const Divider(height: 32),
          _field(_target, 'Destination number or SIP URI'),
          FilledButton(
            onPressed: _busy ? null : _placeCall,
            child: const Text('Place audio call'),
          ),
          if (call != null) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (call.direction == CallDirection.inbound)
                  OutlinedButton(
                    onPressed: () => _run(() => call.answer()),
                    child: const Text('Answer'),
                  ),
                OutlinedButton(
                  onPressed: () => _run(call.hold),
                  child: const Text('Hold'),
                ),
                OutlinedButton(
                  onPressed: () => _run(call.unhold),
                  child: const Text('Resume'),
                ),
                OutlinedButton(
                  onPressed: () => call.sendDtmf('123#'),
                  child: const Text('DTMF 123#'),
                ),
                FilledButton.tonal(
                  onPressed: () => _run(call.hangup),
                  child: const Text('Hang up'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    bool secret = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        obscureText: secret,
        autocorrect: false,
        decoration: InputDecoration(
          border: const OutlineInputBorder(),
          labelText: label,
        ),
      ),
    );
  }
}