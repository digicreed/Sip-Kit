import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:provider/provider.dart';
import 'package:sipkit_flutter/sipkit_flutter.dart';

import '../softphone_state.dart';

/// Screen 4: Active calls — per-call cards with Hold/Mute/DTMF/Transfer + video tiles.
class ActiveCallsScreen extends StatelessWidget {
  const ActiveCallsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<SoftphoneState>();
    final calls = state.calls;

    if (calls.isEmpty) {
      return const Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.call_end, size: 56, color: Colors.grey),
          SizedBox(height: 12),
          Text('No active calls', style: TextStyle(color: Colors.grey)),
        ]),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: calls.length,
      itemBuilder: (context, i) => _CallCard(call: calls[i]),
    );
  }
}

class _CallCard extends StatefulWidget {
  const _CallCard({required this.call});
  final SipKitCall call;

  @override
  State<_CallCard> createState() => _CallCardState();
}

class _CallCardState extends State<_CallCard> {
  bool _muted = false;
  bool _dtmfOpen = false;
  final _dtmfCtrl = TextEditingController();
  final _transferCtrl = TextEditingController();
  bool _videoEnabled = false;
  String? _error;

  Future<void> _toggleVideo() async {
    final state = context.read<SoftphoneState>();
    if (!_videoEnabled && !(state.entitlement?.hasFeature('video') ?? false)) {
      setState(() => _error = 'Video not enabled in your entitlement.');
      return;
    }
    try {
      await widget.call.enableVideo(!_videoEnabled);
      if (mounted) setState(() { _videoEnabled = !_videoEnabled; _error = null; });
    } on NotEntitledError catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _blindTransfer() async {
    final target = _transferCtrl.text.trim();
    if (target.isEmpty) return;
    try {
      await widget.call.blindTransfer(target);
      _transferCtrl.clear();
      if (mounted) Navigator.of(context).pop();
    } on NotEntitledError catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  void _showTransferDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Blind Transfer'),
        content: TextField(
          controller: _transferCtrl,
          decoration: const InputDecoration(
            labelText: 'Target SIP URI',
            hintText: 'sip:carol@pbx.provider.com',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(onPressed: _blindTransfer, child: const Text('Transfer')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final call = widget.call;
    return StreamBuilder<CallState>(
      stream: call.state,
      initialData: call.currentState,
      builder: (context, snap) {
        final state = snap.data ?? CallState.connecting;
        final isEstablished = state == CallState.established;
        final isHeld = state == CallState.held;

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(children: [
                  CircleAvatar(
                    backgroundColor: _stateColor(state).withOpacity(0.15),
                    child:
                        Icon(_dirIcon(call.direction), color: _stateColor(state)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          call.displayName.isNotEmpty
                              ? call.displayName
                              : call.remoteUri,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(call.remoteUri,
                            style: const TextStyle(
                                fontSize: 11, color: Colors.grey),
                            overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  _StateBadge(state: state),
                ]),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(_error!,
                        style: const TextStyle(
                            color: Colors.red, fontSize: 12)),
                  ),
                const SizedBox(height: 12),
                // Video tiles (when video enabled)
                if (_videoEnabled) _VideoTiles(call: call),
                // Action buttons
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _ActionButton(
                      icon: Icons.call_end,
                      label: 'Hang up',
                      color: Colors.red,
                      onPressed: call.hangup,
                    ),
                    if (isEstablished)
                      _ActionButton(
                        icon: Icons.pause,
                        label: 'Hold',
                        onPressed: call.hold,
                      ),
                    if (isHeld)
                      _ActionButton(
                        icon: Icons.play_arrow,
                        label: 'Resume',
                        onPressed: call.unhold,
                      ),
                    _ActionButton(
                      icon: _muted ? Icons.mic_off : Icons.mic,
                      label: _muted ? 'Unmute' : 'Mute',
                      onPressed: () {
                        setState(() => _muted = !_muted);
                        call.mute(_muted);
                      },
                    ),
                    if (isEstablished)
                      _ActionButton(
                        icon: Icons.dialpad,
                        label: 'DTMF',
                        onPressed: () =>
                            setState(() => _dtmfOpen = !_dtmfOpen),
                      ),
                    if (isEstablished)
                      _ActionButton(
                        icon: Icons.call_split,
                        label: 'Transfer',
                        onPressed: _showTransferDialog,
                      ),
                    _ActionButton(
                      icon: _videoEnabled
                          ? Icons.videocam_off
                          : Icons.videocam,
                      label: _videoEnabled ? 'Stop Video' : 'Video',
                      onPressed: _toggleVideo,
                    ),
                  ],
                ),
                // Inline DTMF keypad
                if (_dtmfOpen) ...[
                  const SizedBox(height: 8),
                  _InlineDtmf(
                    ctrl: _dtmfCtrl,
                    onDigit: (d) {
                      try {
                        call.sendDtmf(d);
                        _dtmfCtrl.text += d;
                      } on NotEntitledError catch (e) {
                        setState(() => _error = e.message);
                      }
                    },
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Color _stateColor(CallState s) {
    if (s == CallState.established) return Colors.green;
    if (s == CallState.ringing) return Colors.orange;
    if (s == CallState.held) return Colors.blue;
    if (s == CallState.terminated) return Colors.grey;
    return Colors.indigo;
  }

  IconData _dirIcon(CallDirection d) =>
      d == CallDirection.inbound ? Icons.call_received : Icons.call_made;

  @override
  void dispose() {
    _dtmfCtrl.dispose();
    _transferCtrl.dispose();
    super.dispose();
  }
}

// ─── Video tiles (StatefulWidget to manage RTCVideoRenderer lifecycle) ────────

class _VideoTiles extends StatefulWidget {
  const _VideoTiles({required this.call});
  final SipKitCall call;

  @override
  State<_VideoTiles> createState() => _VideoTilesState();
}

class _VideoTilesState extends State<_VideoTiles> {
  RTCVideoRenderer? _localRenderer;
  RTCVideoRenderer? _remoteRenderer;
  StreamSubscription<(String, dynamic)>? _localSub;
  StreamSubscription<(String, dynamic)>? _remoteSub;

  @override
  void initState() {
    super.initState();
    _initRenderers();
  }

  Future<void> _initRenderers() async {
    // If streams are already attached to the call, use them now.
    final local = widget.call.localStream;
    final remote = widget.call.remoteStream;

    if (local != null) await _setLocal(local);
    if (remote != null) await _setRemote(remote);
  }

  Future<void> _setLocal(dynamic stream) async {
    final r = RTCVideoRenderer();
    await r.initialize();
    r.srcObject = stream as MediaStream;
    if (!mounted) {
      await r.dispose();
      return;
    }
    await _localRenderer?.dispose();
    setState(() => _localRenderer = r);
  }

  Future<void> _setRemote(dynamic stream) async {
    final r = RTCVideoRenderer();
    await r.initialize();
    r.srcObject = stream as MediaStream;
    if (!mounted) {
      await r.dispose();
      return;
    }
    await _remoteRenderer?.dispose();
    setState(() => _remoteRenderer = r);
  }

  @override
  void dispose() {
    _localSub?.cancel();
    _remoteSub?.cancel();
    _localRenderer?.dispose();
    _remoteRenderer?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          _tile(_localRenderer, Icons.videocam, mirror: true),
          const SizedBox(width: 8),
          _tile(_remoteRenderer, Icons.person),
        ],
      ),
    );
  }

  Widget _tile(
    RTCVideoRenderer? renderer,
    IconData placeholder, {
    bool mirror = false,
  }) {
    return Expanded(
      child: Container(
        height: 120,
        decoration: BoxDecoration(
          color:
              renderer != null ? Colors.black87 : Colors.black.withOpacity(0.4),
          borderRadius: BorderRadius.circular(8),
        ),
        child: renderer != null
            ? RTCVideoView(renderer, mirror: mirror)
            : Center(
                child: Icon(placeholder,
                    color: Colors.white.withOpacity(0.38), size: 36)),
      ),
    );
  }
}

// ─── Supporting widgets ───────────────────────────────────────────────────────

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.color,
  });
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      style: ElevatedButton.styleFrom(
        foregroundColor: color ?? Colors.black87,
        backgroundColor: color?.withOpacity(0.1),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}

class _StateBadge extends StatelessWidget {
  const _StateBadge({required this.state});
  final CallState state;

  @override
  Widget build(BuildContext context) {
    final map = {
      CallState.connecting: ('CONNECTING', Colors.indigo),
      CallState.ringing: ('RINGING', Colors.orange),
      CallState.earlyMedia: ('EARLY', Colors.amber),
      CallState.established: ('ACTIVE', Colors.green),
      CallState.held: ('HELD', Colors.blue),
      CallState.terminated: ('ENDED', Colors.grey),
    };
    final (label, color) = map[state] ?? ('UNKNOWN', Colors.grey);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color)),
      child: Text(label,
          style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.bold, color: color)),
    );
  }
}

class _InlineDtmf extends StatelessWidget {
  const _InlineDtmf({required this.ctrl, required this.onDigit});
  final TextEditingController ctrl;
  final void Function(String) onDigit;

  static const _keys = [
    '1', '2', '3', '4', '5', '6', '7', '8', '9', '*', '0', '#'
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: ctrl,
          readOnly: true,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            isDense: true,
            labelText: 'DTMF sent',
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: _keys
              .map((d) => SizedBox(
                    width: 44,
                    height: 36,
                    child: OutlinedButton(
                      onPressed: () => onDigit(d),
                      style: OutlinedButton.styleFrom(
                          padding: EdgeInsets.zero),
                      child:
                          Text(d, style: const TextStyle(fontSize: 15)),
                    ),
                  ))
              .toList(),
        ),
      ],
    );
  }
}
