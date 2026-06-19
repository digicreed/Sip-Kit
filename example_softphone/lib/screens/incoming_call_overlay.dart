import 'package:flutter/material.dart';
import 'package:sipkit_flutter/sipkit_flutter.dart';

/// Overlay shown over any screen when an incoming call arrives.
/// Dismisses itself when the call terminates.
class IncomingCallOverlay extends StatelessWidget {
  const IncomingCallOverlay({super.key, required this.call});
  final SipKitCall call;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withOpacity(0.7),
        child: Center(
          child: Card(
            margin: const EdgeInsets.symmetric(horizontal: 32),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircleAvatar(
                    radius: 36,
                    backgroundColor: Colors.green,
                    child: Icon(Icons.call, color: Colors.white, size: 36),
                  ),
                  const SizedBox(height: 16),
                  Text('Incoming Call',
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(
                    call.displayName.isNotEmpty
                        ? call.displayName
                        : call.remoteUri,
                    style: Theme.of(context).textTheme.bodyLarge,
                    textAlign: TextAlign.center,
                  ),
                  Text(
                    call.remoteUri,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // Reject
                      Column(children: [
                        FloatingActionButton(
                          heroTag: 'reject_${call.id}',
                          backgroundColor: Colors.red,
                          onPressed: call.hangup,
                          child: const Icon(Icons.call_end, color: Colors.white),
                        ),
                        const SizedBox(height: 8),
                        const Text('Reject', style: TextStyle(fontSize: 12)),
                      ]),
                      // Answer audio
                      Column(children: [
                        FloatingActionButton(
                          heroTag: 'answer_audio_${call.id}',
                          backgroundColor: Colors.green,
                          onPressed: () => call.answer(video: false),
                          child: const Icon(Icons.call, color: Colors.white),
                        ),
                        const SizedBox(height: 8),
                        const Text('Audio', style: TextStyle(fontSize: 12)),
                      ]),
                      // Answer video
                      Column(children: [
                        FloatingActionButton(
                          heroTag: 'answer_video_${call.id}',
                          backgroundColor: Colors.blue,
                          onPressed: () => call.answer(video: true),
                          child: const Icon(Icons.videocam, color: Colors.white),
                        ),
                        const SizedBox(height: 8),
                        const Text('Video', style: TextStyle(fontSize: 12)),
                      ]),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
