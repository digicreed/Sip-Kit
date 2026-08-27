package com.sipkit.sipkit_flutter

import android.content.ComponentName
import android.content.Context
import android.os.Bundle
import android.telecom.PhoneAccountHandle
import android.telecom.TelecomManager
import android.telecom.DisconnectCause
import android.os.Handler
import android.os.Looper
/** Common surface deliberately free of PJSUA2 types. */
internal interface SipEngine {
    fun init()
    fun dispose()
    fun register(options: Map<String, Any?>)
    fun unregister(accountId: String)
    fun makeCall(accountId: String, target: String): SipCall
    fun startPreparedCall(callId: String)
    fun cancelPreparedCall(callId: String)
    fun canReceive(accountId: String): Boolean
    fun answer(callId: String)
    fun hangup(callId: String)
    fun hold(callId: String, enabled: Boolean)
    fun mute(callId: String, muted: Boolean)
    fun dtmf(callId: String, digits: String)
    fun blindTransfer(callId: String, target: String)
    fun attendedTransfer(callId: String, otherCallId: String)
}
internal data class SipCall(val id: String, val targetUri: String)
internal interface SipKitConnection {
    val callId: String
    fun applySipState(state: String)
    fun markSipReady()
}

/** ConnectionService and PJSUA callbacks meet here without retaining an Activity. */
internal object SipKitCallController {
    var engine: SipEngine? = null
    private var appContext: Context? = null
    private val connections = mutableMapOf<String, SipKitConnection>()
    fun attach(context: Context) { appContext = context.applicationContext }
    fun answer(id: String) = requireNotNull(engine) { "SIP engine unavailable" }.answer(id)
    fun hangup(id: String) = requireNotNull(engine) { "SIP engine unavailable" }.hangup(id)
    fun hold(id: String, held: Boolean) = requireNotNull(engine) { "SIP engine unavailable" }.hold(id, held)
    fun mute(id: String, muted: Boolean) = requireNotNull(engine) { "SIP engine unavailable" }.mute(id, muted)
    fun startPreparedCall(id: String) = requireNotNull(engine) { "SIP engine unavailable" }.startPreparedCall(id)
    fun cancelPreparedCall(id: String) = requireNotNull(engine) { "SIP engine unavailable" }.cancelPreparedCall(id)
    fun canReceive(accountId: String) = engine?.canReceive(accountId) == true
    fun track(connection: SipKitConnection) { synchronized(connections) { connections[connection.callId] = connection } }
    fun untrack(id: String) { synchronized(connections) { connections.remove(id) } }
    fun callState(id: String, state: String) {
        val connection = synchronized(connections) { connections[id] } ?: return
        Handler(Looper.getMainLooper()).post { connection.applySipState(state) }
    }
    fun incoming(id: String, displayName: String) {
        val existing = synchronized(connections) { connections[id] }
        if (existing != null) {
            Handler(Looper.getMainLooper()).post { existing.markSipReady() }
            return
        }
        val context = appContext ?: return
        val handle = PhoneAccountHandle(ComponentName(context, SipKitConnectionService::class.java), "SipKit")
        val extras = Bundle().apply {
            putString("callId", id)
            putString("displayName", displayName)
            putBoolean("sipReady", true)
        }
        try {
            (context.getSystemService(Context.TELECOM_SERVICE) as TelecomManager).addNewIncomingCall(handle, extras)
        } catch (e: Exception) {
            emitSipEvent(mapOf("type" to "telecomError", "callId" to id, "reason" to (e.message ?: "Unable to surface incoming call")))
        }
    }
}

internal fun emitSipEvent(event: Map<String, Any>) = SipKitEventBus.emit(event)