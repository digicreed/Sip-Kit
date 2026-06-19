import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sipkit_flutter/sipkit_flutter.dart';

import '../softphone_state.dart';

/// Screen 3: Dialer — enter a SIP URI and place audio/video calls.
class DialerScreen extends StatefulWidget {
  const DialerScreen({super.key});

  @override
  State<DialerScreen> createState() => _DialerScreenState();
}

class _DialerScreenState extends State<DialerScreen> {
  final _targetCtrl = TextEditingController();
  String? _selectedAccountId;
  String? _error;

  Future<void> _call({bool video = false}) async {
    final state = context.read<SoftphoneState>();
    if (_selectedAccountId == null) {
      setState(() => _error = 'Select a registered account first.');
      return;
    }
    final target = _targetCtrl.text.trim();
    if (target.isEmpty) {
      setState(() => _error = 'Enter a SIP URI or phone number.');
      return;
    }
    setState(() => _error = null);
    try {
      await state.makeCall(_selectedAccountId!, target, video: video);
    } on NotEntitledError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  void _appendDigit(String digit) {
    _targetCtrl.text += digit;
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<SoftphoneState>();
    final registeredAccounts = state.accounts
        .where((a) => a.currentStatus == AccountStatus.registered)
        .toList();
    final canVideo = state.entitlement?.hasFeature('video') ?? false;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Account picker
          DropdownButtonFormField<String>(
            value: _selectedAccountId,
            decoration: const InputDecoration(
              labelText: 'From account',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.person),
            ),
            hint: const Text('Select registered account'),
            onChanged: (v) => setState(() => _selectedAccountId = v),
            items: registeredAccounts
                .map((a) => DropdownMenuItem(
                      value: a.id,
                      child: Text(
                          '${a.config.displayName ?? a.config.username}@${a.config.domain}',
                          overflow: TextOverflow.ellipsis),
                    ))
                .toList(),
          ),
          const SizedBox(height: 12),
          // Target URI
          TextField(
            controller: _targetCtrl,
            decoration: const InputDecoration(
              labelText: 'SIP URI / Number',
              hintText: 'sip:bob@pbx.provider.com',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.dialpad),
            ),
          ),
          const SizedBox(height: 8),
          if (_error != null)
            Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
          const SizedBox(height: 8),
          // DTMF keypad
          _DtmfKeypad(onDigit: _appendDigit),
          const Spacer(),
          // Call buttons
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: registeredAccounts.isEmpty ? null : () => _call(video: false),
                  icon: const Icon(Icons.call),
                  label: const Text('Audio Call'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.green,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: (registeredAccounts.isEmpty || !canVideo)
                      ? null
                      : () => _call(video: true),
                  icon: const Icon(Icons.videocam),
                  label: Text(canVideo ? 'Video Call' : 'Video (locked)'),
                  style: FilledButton.styleFrom(
                    backgroundColor: canVideo ? Colors.blue : Colors.grey,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
          if (!canVideo)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Video calling is not enabled in your current entitlement.',
                style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _targetCtrl.dispose();
    super.dispose();
  }
}

class _DtmfKeypad extends StatelessWidget {
  const _DtmfKeypad({required this.onDigit});
  final void Function(String) onDigit;

  static const _keys = [
    ['1', '2', '3'],
    ['4', '5', '6'],
    ['7', '8', '9'],
    ['*', '0', '#'],
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: _keys.map((row) => Row(
        children: row.map((digit) => Expanded(
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: OutlinedButton(
              onPressed: () => onDigit(digit),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: Text(digit,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
            ),
          ),
        )).toList(),
      )).toList(),
    );
  }
}
