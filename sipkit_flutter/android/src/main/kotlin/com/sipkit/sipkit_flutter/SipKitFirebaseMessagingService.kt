package com.sipkit.sipkit_flutter

import android.content.ComponentName
import android.content.Context
import android.os.Build
import android.os.Bundle
import android.telecom.PhoneAccount
import android.telecom.PhoneAccountHandle
import android.telecom.TelecomManager
import android.Manifest
import android.content.pm.PackageManager
import androidx.core.content.ContextCompat
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

/**
 * SipKitFirebaseMessagingService
 *
 * Receives FCM data messages while Firebase can deliver them to this process.
 * A Telecom call is surfaced only when the referenced native SIP account is
 * already initialized and ready.
 *
 * Expected FCM data payload (sent by the server push-worker):
 *   callId      – unique identifier for this inbound call
 *   remoteUri   – SIP URI of the caller  (e.g. sip:alice@example.com)
 *   displayName – human-readable caller name
 *   accountId   – SipKit account identifier the call arrived on
 *
 * What this service does:
 *  1. Extracts call metadata from the FCM data map.
 *  2. Ensures the SipKit PhoneAccount is registered with TelecomManager.
 *  3. Calls TelecomManager.addNewIncomingCall so Android surfaces the native
 *     incoming-call UI (lock-screen answer/reject) immediately.
 *  4. Starts SipKitForegroundService to present the ongoing-call notification.
 *     The host must initialize/restore the SIP engine before an FCM wakeup can
 *     answer a dialog.
 *
 * To receive background FCM messages on Android 13+ the app needs
 * POST_NOTIFICATIONS permission (requested at runtime from Flutter).
 *
 * Registration:
 *   Declare this service in the *host app's* AndroidManifest.xml, and add
 *   google-services.json + the Firebase Messaging dependency.
 *
 * Token reporting:
 *   onNewToken is called by Firebase when a fresh FCM registration token is
 *   issued.  We broadcast it over the Flutter EventChannel so the Dart layer
 *   can POST it to /api/v1/push-token.
 */
class SipKitFirebaseMessagingService : FirebaseMessagingService() {

    // ─── Token refresh ────────────────────────────────────────────────────
    override fun onNewToken(token: String) {
        super.onNewToken(token)
        SipKitEventBus.emit(
            mapOf(
                "type"     to "voipPushToken",
                "platform" to "fcm",
                "token"    to token,
            )
        )
    }

    // ─── Inbound data message ─────────────────────────────────────────────
    override fun onMessageReceived(message: RemoteMessage) {
        super.onMessageReceived(message)

        val data = message.data
        if (data.isEmpty()) return

        val callId      = data["callId"]?.takeIf { it.isNotBlank() }
        val remoteUri   = data["remoteUri"]   ?: "sip:unknown@unknown"
        val displayName = data["displayName"] ?: remoteUri
        val accountId   = data["accountId"]?.takeIf { it.isNotBlank() }

        if (callId == null || accountId == null) {
            SipKitEventBus.emit(mapOf(
                "type" to "pjsipError",
                "code" to "INVALID_PUSH",
                "reason" to "FCM call push requires SIP Call-ID and accountId",
            ))
            return
        }
        reportIncomingCall(callId, remoteUri, displayName, accountId)
    }

    // ─── Native call screen via TelecomManager ────────────────────────────
    private fun reportIncomingCall(
        callId: String,
        remoteUri: String,
        displayName: String,
        accountId: String,
    ) {
        if (!SipKitCallController.canReceive(accountId)) {
            SipKitEventBus.emit(mapOf(
                "type" to "voipWakeupError",
                "code" to "ACCOUNT_NOT_READY",
                "accountId" to accountId,
                "callId" to callId,
                "reason" to "Initialize and restore the SIP account before surfacing this push call",
            ))
            return
        }
        if (!hasTelecomPermission()) {
            SipKitEventBus.emit(
                mapOf(
                    "type"        to "incomingCall",
                    "callId"      to callId,
                    "accountId"   to accountId,
                    "remoteUri"   to remoteUri,
                    "displayName" to displayName,
                    "hasVideo"    to false,
                )
            )
            return
        }

        val telecomManager = getSystemService(Context.TELECOM_SERVICE) as TelecomManager

        val handle = PhoneAccountHandle(
            ComponentName(this, SipKitConnectionService::class.java),
            "SipKit"
        )

        ensurePhoneAccountRegistered(telecomManager, handle)

        val extras = Bundle().apply {
            putString("callId",      callId)
            putString("remoteUri",   remoteUri)
            putString("displayName", displayName)
            putString("accountId",   accountId)
            putBoolean("sipReady", false)
            putBoolean(TelecomManager.EXTRA_START_CALL_WITH_SPEAKERPHONE, false)
        }

        // Ensure the ongoing VoIP service notification is present while the
        // app processes a push wakeup. Account restoration remains owned by
        // the host application's normal SIP initialization flow.
        SipKitForegroundService.start(this)

        try {
            @Suppress("MissingPermission")
            telecomManager.addNewIncomingCall(handle, extras)
        } catch (e: Exception) {
            android.util.Log.e("SipKitFCM", "addNewIncomingCall failed: ${e.message}")
            SipKitEventBus.emit(mapOf(
                "type" to "telecomError",
                "callId" to callId,
                "reason" to (e.message ?: "Unable to surface incoming call"),
            ))
            return
        }

        SipKitEventBus.emit(
            mapOf(
                "type"        to "incomingCall",
                "callId"      to callId,
                "accountId"   to accountId,
                "remoteUri"   to remoteUri,
                "displayName" to displayName,
                "hasVideo"    to false,
            )
        )
    }

    private fun ensurePhoneAccountRegistered(
        telecomManager: TelecomManager,
        handle: PhoneAccountHandle,
    ) {
        try {
            @Suppress("MissingPermission")
            if (telecomManager.getPhoneAccount(handle) == null) {
                val account = PhoneAccount.builder(handle, "SipKit")
                    .setCapabilities(PhoneAccount.CAPABILITY_CALL_PROVIDER)
                    .build()
                telecomManager.registerPhoneAccount(account)
            }
        } catch (e: Exception) {
            android.util.Log.e("SipKitFCM", "Phone account registration failed: ${e.message}")
        }
    }

    private fun hasTelecomPermission(): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
            ContextCompat.checkSelfPermission(
                this, Manifest.permission.MANAGE_OWN_CALLS
            ) == PackageManager.PERMISSION_GRANTED
        else true
}
