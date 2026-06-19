import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../softphone_state.dart';

/// Screen 7: Event log — prints all SDK events in reverse-chronological order.
class EventLogScreen extends StatelessWidget {
  const EventLogScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<SoftphoneState>();
    final log = state.log;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Text('${log.length} events',
                  style: Theme.of(context).textTheme.bodySmall),
              const Spacer(),
              TextButton.icon(
                onPressed: () {
                  state.log.clear();
                  (context as Element).markNeedsBuild();
                },
                icon: const Icon(Icons.clear_all, size: 16),
                label: const Text('Clear'),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: log.isEmpty
              ? const Center(
                  child: Text('No events yet.',
                      style: TextStyle(color: Colors.grey)))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: log.length,
                  itemBuilder: (context, i) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Text(
                      log[i],
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: log[i].contains('fail') || log[i].contains('error')
                            ? Colors.red[700]
                            : log[i].contains('Activat')
                                ? Colors.green[700]
                                : Colors.black87,
                      ),
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}
