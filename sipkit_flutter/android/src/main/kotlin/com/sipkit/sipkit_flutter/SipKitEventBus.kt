package com.sipkit.sipkit_flutter

import io.flutter.plugin.common.EventChannel

/**
 * SipKitEventBus
 *
 * A process-level singleton that decouples background services
 * (SipKitFirebaseMessagingService, SipKitConnectionService) from the Flutter
 * EventChannel sink, which is only available after the Flutter engine attaches.
 *
 * Background services call [emit] at any time; SipKitPlugin registers the
 * active [EventChannel.EventSink] via [setSink].  Events queued before the
 * sink is ready are replayed in order when the sink is connected.
 */
object SipKitEventBus {

    private var sink: EventChannel.EventSink? = null
    private val pending = ArrayDeque<Map<String, Any>>()

    fun setSink(newSink: EventChannel.EventSink?) {
        sink = newSink
        if (newSink != null) {
            drainPending(newSink)
        }
    }

    fun emit(event: Map<String, Any>) {
        val s = sink
        if (s != null) {
            android.os.Handler(android.os.Looper.getMainLooper()).post {
                s.success(event)
            }
        } else {
            synchronized(pending) { pending.addLast(event) }
        }
    }

    private fun drainPending(s: EventChannel.EventSink) {
        val handler = android.os.Handler(android.os.Looper.getMainLooper())
        handler.post {
            synchronized(pending) {
                val iter = pending.iterator()
                while (iter.hasNext()) {
                    s.success(iter.next())
                    iter.remove()
                }
            }
        }
    }
}
