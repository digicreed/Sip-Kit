import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sipkit_flutter/sipkit_flutter.dart';

import '../softphone_state.dart';

/// Screen 2: Add/remove SIP accounts and view registration status.
class AccountSetupScreen extends StatefulWidget {
  const AccountSetupScreen({super.key});

  @override
  State<AccountSetupScreen> createState() => _AccountSetupScreenState();
}

class _AccountSetupScreenState extends State<AccountSetupScreen> {
  bool _showAddForm = false;
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _domain = TextEditingController();
  final _wsUrl = TextEditingController();
  final _displayName = TextEditingController();
  bool _saving = false;
  String? _addError;

  Future<void> _addAccount() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _addError = null;
    });
    try {
      final wsUrl = _wsUrl.text.trim().isNotEmpty
          ? _wsUrl.text.trim()
          : 'wss://${_domain.text.trim()}:8089/ws';
      await context.read<SoftphoneState>().addAccount(
            SipKitAccountConfig(
              username: _username.text.trim(),
              password: _password.text.trim(),
              domain: _domain.text.trim(),
              wsUrl: wsUrl,
              displayName: _displayName.text.trim().isNotEmpty
                  ? _displayName.text.trim()
                  : null,
              registerOnAdd: true,
            ),
          );
      if (mounted) {
        setState(() {
          _showAddForm = false;
          _saving = false;
        });
        _clearForm();
      }
    } on NotEntitledError catch (e) {
      setState(() {
        _addError = e.message;
        _saving = false;
      });
    } catch (e) {
      setState(() {
        _addError = e.toString();
        _saving = false;
      });
    }
  }

  void _clearForm() {
    _username.clear();
    _password.clear();
    _domain.clear();
    _wsUrl.clear();
    _displayName.clear();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<SoftphoneState>();
    final maxAccounts = state.entitlement?.maxAccounts ?? 0;
    final current = state.accounts.length;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Text('Accounts ($current/$maxAccounts)',
                style: Theme.of(context).textTheme.titleMedium),
            const Spacer(),
            if (!_showAddForm)
              FilledButton.icon(
                onPressed: current >= maxAccounts
                    ? null
                    : () => setState(() => _showAddForm = true),
                icon: const Icon(Icons.add),
                label: const Text('Add'),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (_showAddForm) _buildAddForm(),
        ...state.accounts.map((acc) => _AccountTile(account: acc)),
        if (state.accounts.isEmpty && !_showAddForm)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(
              child: Column(children: [
                Icon(Icons.people_outline, size: 48, color: Colors.grey),
                SizedBox(height: 8),
                Text(
                  'No accounts yet. Tap Add to register a SIP extension.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              ]),
            ),
          ),
      ],
    );
  }

  Widget _buildAddForm() {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Add SIP Account',
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 12),
              _field(_username, 'Username', 'alice'),
              _field(_password, 'Password', '••••••••', obscure: true),
              _field(_domain, 'Domain', 'pbx.provider.com'),
              _field(_wsUrl, 'WSS URL (optional)',
                  'wss://pbx.provider.com:8089/ws',
                  required: false),
              _field(_displayName, 'Display name (optional)', 'Alice',
                  required: false),
              if (_addError != null) ...[
                const SizedBox(height: 8),
                Text(_addError!,
                    style:
                        const TextStyle(color: Colors.red, fontSize: 13)),
              ],
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => setState(() {
                      _showAddForm = false;
                      _addError = null;
                    }),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: _saving ? null : _addAccount,
                    child: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Text('Register'),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController ctrl,
    String label,
    String hint, {
    bool obscure = false,
    bool required = true,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        controller: ctrl,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        obscureText: obscure,
        validator: required
            ? (v) => (v == null || v.isEmpty) ? 'Required' : null
            : null,
      ),
    );
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _domain.dispose();
    _wsUrl.dispose();
    _displayName.dispose();
    super.dispose();
  }
}

class _AccountTile extends StatelessWidget {
  const _AccountTile({required this.account});
  final SipKitAccount account;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AccountStatus>(
      stream: account.status,
      initialData: account.currentStatus,
      builder: (context, snap) {
        final status = snap.data ?? AccountStatus.unregistered;
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: _statusColor(status).withOpacity(0.15),
              child: Icon(Icons.person, color: _statusColor(status)),
            ),
            title: Text(
                '${account.config.displayName ?? account.config.username}@${account.config.domain}'),
            subtitle: Text(
              account.config.wsUrl ??
                  'Native SIP (${account.config.transport.name.toUpperCase()})',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _StatusBadge(status: status),
                const SizedBox(width: 4),
                PopupMenuButton<String>(
                  onSelected: (v) {
                    if (v == 'unregister') account.unregister();
                    if (v == 'register') account.register();
                    if (v == 'remove') {
                      context
                          .read<SoftphoneState>()
                          .removeAccount(account.id);
                    }
                  },
                  itemBuilder: (_) => [
                    if (status != AccountStatus.registered)
                      const PopupMenuItem(
                          value: 'register', child: Text('Register')),
                    if (status == AccountStatus.registered)
                      const PopupMenuItem(
                          value: 'unregister', child: Text('Unregister')),
                    const PopupMenuItem(
                        value: 'remove', child: Text('Remove')),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Color _statusColor(AccountStatus s) {
    switch (s) {
      case AccountStatus.registered:
        return Colors.green;
      case AccountStatus.registering:
        return Colors.orange;
      case AccountStatus.failed:
        return Colors.red;
      case AccountStatus.unregistered:
        return Colors.grey;
    }
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});
  final AccountStatus status;

  @override
  Widget build(BuildContext context) {
    final labels = {
      AccountStatus.registered: ('REGISTERED', Colors.green),
      AccountStatus.registering: ('REGISTERING', Colors.orange),
      AccountStatus.failed: ('FAILED', Colors.red),
      AccountStatus.unregistered: ('OFFLINE', Colors.grey),
    };
    final (label, color) = labels[status]!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: color)),
    );
  }
}
