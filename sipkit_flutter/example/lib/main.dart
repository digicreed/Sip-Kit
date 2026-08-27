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
  final _sipPort = TextEditingController(text: '5061');
  final _target = TextEditingController();
  final _transferTarget = TextEditingController();

  late final SipKitClient _client = SipKitClient(engine: PjsipEngine());
  StreamSubscription<SipKitCall>? _incomingSubscription;
  StreamSubscription<AccountStatus>? _accountSubscription;
  StreamSubscription<CallState>? _callSubscription;
  StreamSubscription<CallState>? _consultationSubscription;
  SipKitAccount? _account;
  SipKitCall? _call;
  SipKitCall? _consultationCall;
  String _status = 'Not initialized';
  bool _busy = false;
  bool _muted = false;
  SipTransport _transport = SipTransport.tls;

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
          transport: _transport,
          sipPort: int.tryParse(_sipPort.text.trim()),
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

  Future<void> _startConsultationCall() async {
    final account = _account;
    if (account == null) {
      _setStatus('Register an account first');
      return;
    }
    final target = _transferTarget.text.trim();
    if (target.isEmpty) {
      _setStatus('Enter a transfer target first');
      return;
    }
    await _run(() async {
      final consultation = await _client.makeCall(account.id, target);
      await _consultationSubscription?.cancel();
      _consultationSubscription = consultation.state.listen(
        (state) => _setStatus('Consultation: ${state.name}'),
      );
      setState(() => _consultationCall = consultation);
      _setStatus('Consultation call started; answer it before transferring');
    });
  }

  Future<void> _blindTransfer() async {
    final call = _call;
    final target = _transferTarget.text.trim();
    if (call == null || target.isEmpty) {
      _setStatus('Select a call and enter a transfer target first');
      return;
    }
    await _run(() => call.blindTransfer(target));
  }

  Future<void> _attendedTransfer() async {
    final call = _call;
    final consultation = _consultationCall;
    if (call == null || consultation == null) {
      _setStatus('Start a consultation call first');
      return;
    }
    await _run(() => call.attendedTransfer(consultation));
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
    _consultationSubscription?.cancel();
    _client.dispose();
    for (final controller in [
      _licenseKey,
      _baseUrl,
      _username,
      _password,
      _domain,
      _registrar,
      _sipPort,
      _target,
      _transferTarget,
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
          DropdownButtonFormField<SipTransport>(
            value: _transport,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Native SIP transport',
            ),
            items: SipTransport.values
                .map(
                  (transport) => DropdownMenuItem(
                    value: transport,
                    child: Text(transport.name.toUpperCase()),
                  ),
                )
                .toList(),
            onChanged: _busy
                ? null
                : (transport) {
                    if (transport != null) {
                      setState(() => _transport = transport);
                    }
                  },
          ),
          const SizedBox(height: 12),
          _field(_sipPort, 'SIP port (5060 UDP/TCP, 5061 TLS)'),
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
          const SizedBox(height: 12),
          _field(_transferTarget, 'Transfer target number or SIP URI'),
          OutlinedButton(
            onPressed: _busy ? null : _startConsultationCall,
            child: const Text('Start consultation call'),
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
                  onPressed: _busy
                      ? null
                      : () {
                          call.mute(!_muted);
                          setState(() => _muted = !_muted);
                          _setStatus(
                            _muted ? 'Microphone muted' : 'Microphone unmuted',
                          );
                        },
                  child: Text(_muted ? 'Unmute' : 'Mute'),
                ),
                OutlinedButton(
                  onPressed: () => call.sendDtmf('123#'),
                  child: const Text('DTMF 123#'),
                ),
                OutlinedButton(
                  onPressed: _busy ? null : _blindTransfer,
                  child: const Text('Blind transfer'),
                ),
                OutlinedButton(
                  onPressed: _busy ? null : _attendedTransfer,
                  child: const Text('Attended transfer'),
                ),
                FilledButton.tonal(
                  onPressed: () => _run(call.hangup),
                  child: const Text('Hang up'),
                ),
              ],
            ),
          ],
          if (_consultationCall != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Consultation leg: ${_consultationCall!.currentState.name}',
              ),
            ),
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
