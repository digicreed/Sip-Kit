package com.sipkit.sipkit_flutter

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

// ---------------------------------------------------------------------------
// SipKitForegroundService — keeps the PJSIP socket alive in the background
// ---------------------------------------------------------------------------
// Android terminates background processes aggressively.  A foreground service
// with `foregroundServiceType="phoneCall"` (declared in AndroidManifest.xml)
// keeps the app process alive so PJSIP can maintain the WebSocket SIP
// connection and receive incoming calls while the screen is off.
//
// Full implementation:
//   • Call start() from SipKitPlugin.handleInit()
//   • Call stop()  from SipKitPlugin.handleDispose()
//   • Wire the notification tap to bring the softphone UI to the foreground.
// ---------------------------------------------------------------------------

class SipKitForegroundService : Service() {

    companion object {
        private const val CHANNEL_ID = "sipkit_channel"
        private const val NOTIFICATION_ID = 1001

        fun start(context: Context) {
            val intent = Intent(context, SipKitForegroundService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            val intent = Intent(context, SipKitForegroundService::class.java)
            context.stopService(intent)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForeground(NOTIFICATION_ID, buildNotification())
        // PJSUA2 stub: Endpoint.instance() is already initialised by
        // SipKitPlugin.handleInit(); the socket is kept alive by this service.
        return START_STICKY
    }

    override fun onDestroy() {
        stopForeground(true)
        super.onDestroy()
    }

    private fun buildNotification(): Notification {
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("SipKit")
            .setContentText("VoIP service active")
            .setSmallIcon(android.R.drawable.ic_menu_call)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "SipKit VoIP",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Keeps VoIP connection alive in background"
            }
            val manager =
                getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }
}
