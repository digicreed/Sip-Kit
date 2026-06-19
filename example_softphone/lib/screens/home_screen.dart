import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sipkit_flutter/sipkit_flutter.dart';

import '../softphone_state.dart';
import 'account_setup_screen.dart';
import 'dialer_screen.dart';
import 'active_calls_screen.dart';
import 'event_log_screen.dart';
import 'incoming_call_overlay.dart';

/// Main tab host shown after successful activation.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  static const _labels = [
    'Accounts',
    'Dialer',
    'Calls',
    'Log',
  ];

  static const _icons = [
    Icons.people,
    Icons.dialpad,
    Icons.call,
    Icons.list_alt,
  ];

  List<Widget> _screens() => [
        const AccountSetupScreen(),
        const DialerScreen(),
        const ActiveCallsScreen(),
        const EventLogScreen(),
      ];

  @override
  Widget build(BuildContext context) {
    final state = context.watch<SoftphoneState>();
    final hasIncoming = state.incomingCalls.isNotEmpty;

    return Stack(
      children: [
        Scaffold(
          appBar: AppBar(
            title: const Text('SipKit Demo'),
            actions: [
              _EntitlementChip(entitlement: state.entitlement),
              const SizedBox(width: 4),
              IconButton(
                icon: Icon(state.useWebrtcEngine
                    ? Icons.web_rounded
                    : Icons.phone_android),
                tooltip: 'Engine: ${state.useWebrtcEngine ? "WebRTC" : "PJSIP"}',
                onPressed: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text('Switch engine?'),
                      content: const Text(
                          'This will disconnect all accounts and calls.'),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Cancel')),
                        FilledButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Switch')),
                      ],
                    ),
                  );
                  if (confirmed == true && context.mounted) {
                    context.read<SoftphoneState>().toggleEngine();
                  }
                },
              ),
            ],
          ),
          body: _screens()[_selectedIndex],
          bottomNavigationBar: NavigationBar(
            selectedIndex: _selectedIndex,
            onDestinationSelected: (i) => setState(() => _selectedIndex = i),
            destinations: List.generate(
              _labels.length,
              (i) => NavigationDestination(
                icon: Icon(_icons[i]),
                label: _labels[i],
              ),
            ),
          ),
          floatingActionButton: state.calls.length >= 2
              ? FloatingActionButton.extended(
                  onPressed: () => context.read<SoftphoneState>().mergeActiveCalls(),
                  icon: const Icon(Icons.call_merge),
                  label: const Text('Conference'),
                  backgroundColor: state.entitlement?.hasFeature('conference') == true
                      ? null
                      : Colors.grey,
                )
              : null,
        ),
        if (hasIncoming)
          IncomingCallOverlay(call: state.incomingCalls.first),
      ],
    );
  }
}

class _EntitlementChip extends StatelessWidget {
  const _EntitlementChip({required this.entitlement});
  final Entitlement? entitlement;

  @override
  Widget build(BuildContext context) {
    if (entitlement == null) return const SizedBox.shrink();
    final expired = entitlement!.isExpired;
    return Chip(
      avatar: Icon(
        expired ? Icons.warning_amber : Icons.verified,
        size: 16,
        color: expired ? Colors.orange : Colors.green,
      ),
      label: Text(
        expired ? 'EXPIRED' : 'ACTIVE',
        style: TextStyle(
          fontSize: 11,
          color: expired ? Colors.orange[800] : Colors.green[800],
          fontWeight: FontWeight.bold,
        ),
      ),
      backgroundColor:
          expired ? Colors.orange[50] : Colors.green[50],
      side: BorderSide(color: expired ? Colors.orange : Colors.green),
      padding: EdgeInsets.zero,
    );
  }
}
