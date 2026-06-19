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
import java.util.UUID

/**
 * SipKitFirebaseMessagingService
 *
 * Receives FCM data messages when the app is in the background or terminated.
 * A data-only message (no "notification" block) is always delivered to this
 * service, bypassing the system notification tray, which allows us to present
 * a native call screen instead.
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
 *  4. Starts SipKitForegroundService so the PJSIP engine is alive and can
 *     negotiate the SIP dialog when the user taps Answer.
 *
 * To receive background FCM messages on Android 13+ the app needs
 * POST_NOTIFICATIONS permission (requested at runtime from Flutter).
 *
 * Registration:
 *   Declare this service in the *host app's* AndroidManifest.xml, and add
 *   google-services.json + the Firebase Messaging dependency.  The plugin's
 *   own manifest stubs the service so it compiles; the host app overrides it.
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

        val callId      = data["callId"]      ?: UUID.randomUUID().toString()
        val remoteUri   = data["remoteUri"]   ?: "sip:unknown@unknown"
        val displayName = data["displayName"] ?: remoteUri
        val accountId   = data["accountId"]   ?: ""

        reportIncomingCall(callId, remoteUri, displayName, accountId)
    }

    // ─── Native call screen via TelecomManager ────────────────────────────
    private fun reportIncomingCall(
        callId: String,
        remoteUri: String,
        displayName: String,
        accountId: String,
    ) {
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
            putBoolean(TelecomManager.EXTRA_START_CALL_WITH_SPEAKERPHONE, false)
        }

        // Bootstrap the PJSIP engine before surfacing the call.
        // In a terminated-state wakeup the engine has never been started;
        // SipKitForegroundService must initialize it so the SIP dialog can
        // be negotiated when the user taps Answer in the system call screen.
        //
        // PJSUA2 stub — replace the foreground-service onStartCommand with:
        //   Endpoint.instance().libCreate()
        //   Endpoint.instance().libInit(EpConfig())
        //   Endpoint.instance().libStart()
        //   // Re-register all accounts from persisted credentials
        //   restoreAccountRegistrations()
        SipKitForegroundService.start(this)

        try {
            @Suppress("MissingPermission")
            telecomManager.addNewIncomingCall(handle, extras)
        } catch (e: Exception) {
            android.util.Log.e("SipKitFCM", "addNewIncomingCall failed: ${e.message}")
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
