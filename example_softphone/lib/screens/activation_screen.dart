import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../softphone_state.dart';

/// Screen 1: Enter license key + backend URL → activate.
class ActivationScreen extends StatefulWidget {
  const ActivationScreen({super.key});

  @override
  State<ActivationScreen> createState() => _ActivationScreenState();
}

class _ActivationScreenState extends State<ActivationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _licenseCtrl = TextEditingController();
  final _baseUrlCtrl = TextEditingController(
      text: 'https://your-sipkit-backend.com');
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadSaved();
  }

  Future<void> _loadSaved() async {
    final state = context.read<SoftphoneState>();
    final creds = await state.loadSavedCredentials();
    if (creds['licenseKey'] != null) {
      _licenseCtrl.text = creds['licenseKey']!;
    }
    if (creds['baseUrl'] != null) {
      _baseUrlCtrl.text = creds['baseUrl']!;
    }
  }

  Future<void> _activate() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _loading = true);
    await context.read<SoftphoneState>().activate(
          licenseKey: _licenseCtrl.text.trim(),
          baseUrl: _baseUrlCtrl.text.trim(),
        );
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<SoftphoneState>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('SipKit Demo Softphone'),
        actions: [
          IconButton(
            icon: Icon(state.useWebrtcEngine
                ? Icons.web_rounded
                : Icons.phone_android),
            tooltip: 'Engine: ${state.useWebrtcEngine ? "WebRTC" : "PJSIP"}',
            onPressed: state.toggleEngine,
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.lock_open, size: 64, color: Colors.indigo),
                  const SizedBox(height: 16),
                  Text(
                    'Activate SipKit',
                    style: Theme.of(context).textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Enter your license key and the SipKit backend URL to unlock SIP calling.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.grey[600],
                        ),
                  ),
                  const SizedBox(height: 32),
                  TextFormField(
                    controller: _baseUrlCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Backend URL',
                      hintText: 'https://license.mydomain.com',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.cloud),
                    ),
                    keyboardType: TextInputType.url,
                    validator: (v) =>
                        (v == null || v.isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _licenseCtrl,
                    decoration: const InputDecoration(
                      labelText: 'License Key',
                      hintText: 'pk_live_...',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.vpn_key),
                    ),
                    validator: (v) =>
                        (v == null || v.isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 8),
                  if (state.activationError != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline, color: Colors.red),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              state.activationError!,
                              style: const TextStyle(color: Colors.red),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _loading ? null : _activate,
                    icon: _loading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.lock_open),
                    label: Text(_loading ? 'Activating…' : 'Activate'),
                    style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16)),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Engine: ${state.useWebrtcEngine ? "WebrtcEngine (sip_ua + WebRTC)" : "PjsipEngine (PJSUA2 + CallKit/ConnectionService)"}',
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _licenseCtrl.dispose();
    _baseUrlCtrl.dispose();
    super.dispose();
  }
}
