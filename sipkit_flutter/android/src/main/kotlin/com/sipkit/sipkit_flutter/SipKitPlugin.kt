package com.sipkit.sipkit_flutter

import android.Manifest
import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.telecom.PhoneAccount
import android.telecom.PhoneAccountHandle
import android.telecom.TelecomManager
import androidx.annotation.NonNull
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.util.UUID

// ---------------------------------------------------------------------------
// SipKitPlugin — Android native host for PjsipEngine
// ---------------------------------------------------------------------------
// Bridges Flutter platform channels to PJSUA2 (PJSIP) via Android AAR and
// TelecomManager / ConnectionService for native call UI.
//
// Method channel:  com.sipkit.sipkit_flutter/pjsip
// Event channel:   com.sipkit.sipkit_flutter/pjsip_events
//
// Dependencies (android/build.gradle):
//   implementation 'org.pjsip:pjsua2-android:2.14.0@aar'
//
// When the PJSIP AAR is available, replace every "PJSUA2 stub" comment with
// the corresponding PJSUA2 API call as indicated in the comment text.
// ---------------------------------------------------------------------------

class SipKitPlugin : FlutterPlugin, MethodCallHandler, ActivityAware,
    EventChannel.StreamHandler {

    private lateinit var context: Context
    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel

    private var eventSink: EventChannel.EventSink? = null
    private var activityBinding: ActivityPluginBinding? = null

    // Maps SipKit accountId -> PJSUA2 account ID (Int)
    private val accountIds = mutableMapOf<String, Int>()
    // Maps SipKit callId -> UUID (for TelecomManager correlation)
    private val callUUIDs = mutableMapOf<String, String>()

    // ─── FlutterPlugin ────────────────────────────────────────────────────
    override fun onAttachedToEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext

        methodChannel = MethodChannel(
            binding.binaryMessenger,
            "com.sipkit.sipkit_flutter/pjsip"
        )
        methodChannel.setMethodCallHandler(this)

        eventChannel = EventChannel(
            binding.binaryMessenger,
            "com.sipkit.sipkit_flutter/pjsip_events"
        )
        eventChannel.setStreamHandler(this)
    }

    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
    }

    // ─── ActivityAware ────────────────────────────────────────────────────
    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
    }
    override fun onDetachedFromActivityForConfigChanges() {}
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activityBinding = binding
    }
    override fun onDetachedFromActivity() { activityBinding = null }

    // ─── EventChannel.StreamHandler ───────────────────────────────────────
    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        SipKitEventBus.setSink(events)
    }
    override fun onCancel(arguments: Any?) {
        eventSink = null
        SipKitEventBus.setSink(null)
    }

    // ─── MethodCallHandler ────────────────────────────────────────────────
    override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
        when (call.method) {
            "init"             -> handleInit(result)
            "dispose"          -> handleDispose(result)
            "registerAccount"  -> registerAccount(call, result)
            "unregister"       -> unregister(call, result)
            "makeCall"         -> makeCall(call, result)
            "answer"           -> answerCall(call, result)
            "hangup"           -> hangupCall(call, result)
            "hold"             -> holdCall(call, result, hold = true)
            "unhold"           -> holdCall(call, result, hold = false)
            "mute"             -> muteCall(call, result)
            "sendDtmf"         -> sendDtmf(call, result)
            "blindTransfer"    -> blindTransfer(call, result)
            "attendedTransfer" -> attendedTransfer(call, result)
            "enableVideo"      -> enableVideo(call, result)
            else               -> result.notImplemented()
        }
    }

    // ─── Lifecycle ────────────────────────────────────────────────────────
    private fun handleInit(result: Result) {
        // PJSUA2 stub: Endpoint.instance().libCreate() + libInit() + libStart()
        // SipKitForegroundService.start(context)
        result.success(null)
    }

    private fun handleDispose(result: Result) {
        // PJSUA2 stub: Endpoint.instance().libDestroy()
        // SipKitForegroundService.stop(context)
        result.success(null)
    }

    // ─── Account management ───────────────────────────────────────────────
    private fun registerAccount(call: MethodCall, result: Result) {
        val accountId    = call.argument<String>("accountId")       ?: return result.error("INVALID_ARGS", "Missing accountId", null)
        val username     = call.argument<String>("username")        ?: return result.error("INVALID_ARGS", "Missing username", null)
        val password     = call.argument<String>("password")        ?: return result.error("INVALID_ARGS", "Missing password", null)
        val domain       = call.argument<String>("domain")          ?: return result.error("INVALID_ARGS", "Missing domain", null)
        val wsUrl        = call.argument<String>("wsUrl")           ?: return result.error("INVALID_ARGS", "Missing wsUrl", null)
        val displayName  = call.argument<String>("displayName")     ?: username
        val authUsername = call.argument<String>("authUsername")    ?: username
        val expiry       = call.argument<Int>("registrationExpiry") ?: 600

        // PJSUA2 stub — replace with:
        //   val cfg = AccountConfig()
        //   cfg.idUri = "sip:$username@$domain"
        //   cfg.regConfig.registrarUri = "sip:$domain"
        //   cfg.sipConfig.proxies.add("<sip:$domain;transport=ws>")
        //   cfg.regConfig.timeoutSec = expiry
        //   val acc = MyAccount(); acc.create(cfg); accountIds[accountId] = acc.id

        accountIds[accountId] = (1..1000).random()
        emitEvent(mapOf(
            "type"      to "accountStatus",
            "accountId" to accountId,
            "status"    to "registered",
            "reason"    to "stub registration succeeded"
        ))
        result.success(null)
    }

    private fun unregister(call: MethodCall, result: Result) {
        val accountId = call.argument<String>("accountId")
            ?: return result.error("INVALID_ARGS", "Missing accountId", null)
        // PJSUA2 stub: acc.setRegistration(false)
        accountIds.remove(accountId)
        emitEvent(mapOf("type" to "accountStatus", "accountId" to accountId, "status" to "unregistered"))
        result.success(null)
    }

    // ─── Outbound calls ───────────────────────────────────────────────────
    private fun makeCall(call: MethodCall, result: Result) {
        val accountId = call.argument<String>("accountId") ?: return result.error("INVALID_ARGS", "Missing accountId", null)
        val target    = call.argument<String>("target")    ?: return result.error("INVALID_ARGS", "Missing target", null)
        val video     = call.argument<Boolean>("video")    ?: false

        val callId = "call_${UUID.randomUUID().toString().take(8)}"
        val uuid   = UUID.randomUUID().toString()
        callUUIDs[callId] = uuid

        // TelecomManager: register phone account on first call if not done.
        ensurePhoneAccountRegistered()

        // PJSUA2 stub: acc.makeCall("sip:$target", CallOpParam())
        emitEvent(mapOf("type" to "callState", "callId" to callId, "state" to "connecting"))
        result.success(callId)
    }

    private fun answerCall(call: MethodCall, result: Result) {
        val callId = call.argument<String>("callId") ?: return result.error("INVALID_ARGS", "Missing callId", null)
        // PJSUA2 stub: sipCall.answer(CallOpParam(statusCode = SipStatusCode.OK))
        emitEvent(mapOf("type" to "callState", "callId" to callId, "state" to "established"))
        result.success(null)
    }

    private fun hangupCall(call: MethodCall, result: Result) {
        val callId = call.argument<String>("callId") ?: return result.error("INVALID_ARGS", "Missing callId", null)
        // PJSUA2 stub: sipCall.hangup(CallOpParam())
        callUUIDs.remove(callId)
        emitEvent(mapOf("type" to "callState", "callId" to callId, "state" to "terminated"))
        result.success(null)
    }

    private fun holdCall(call: MethodCall, result: Result, hold: Boolean) {
        val callId = call.argument<String>("callId") ?: return result.error("INVALID_ARGS", "Missing callId", null)
        // PJSUA2 stub: sipCall.setHold(hold)
        emitEvent(mapOf("type" to "callState", "callId" to callId,
            "state" to if (hold) "held" else "established"))
        result.success(null)
    }

    private fun muteCall(call: MethodCall, result: Result) {
        val callId = call.argument<String>("callId") ?: return result.error("INVALID_ARGS", "Missing callId", null)
        // PJSUA2 stub: audioMedia.adjustTxLevel(if (muted) 0f else 1f)
        result.success(null)
    }

    private fun sendDtmf(call: MethodCall, result: Result) {
        val callId = call.argument<String>("callId") ?: return result.error("INVALID_ARGS", "Missing callId", null)
        val digits = call.argument<String>("digits")  ?: return result.error("INVALID_ARGS", "Missing digits", null)
        // PJSUA2 stub: sipCall.dialDtmf(digits)
        result.success(null)
    }

    private fun blindTransfer(call: MethodCall, result: Result) {
        val callId    = call.argument<String>("callId")    ?: return result.error("INVALID_ARGS", "Missing callId", null)
        val targetUri = call.argument<String>("targetUri") ?: return result.error("INVALID_ARGS", "Missing targetUri", null)
        // PJSUA2 stub: sipCall.xfer("sip:$targetUri", CallOpParam())
        result.success(null)
    }

    private fun attendedTransfer(call: MethodCall, result: Result) {
        val callId      = call.argument<String>("callId")      ?: return result.error("INVALID_ARGS", "Missing callId", null)
        val otherCallId = call.argument<String>("otherCallId") ?: return result.error("INVALID_ARGS", "Missing otherCallId", null)
        // PJSUA2 stub: callA.xferReplaces(callB, CallOpParam())
        result.success(null)
    }

    private fun enableVideo(call: MethodCall, result: Result) {
        val callId  = call.argument<String>("callId")  ?: return result.error("INVALID_ARGS", "Missing callId", null)
        val enabled = call.argument<Boolean>("enabled") ?: false
        // PJSUA2 stub: vid stream add/remove via CallVideoStream
        result.success(null)
    }

    // ─── Incoming call (called from PJSUA2 onIncomingCall callback) ───────
    fun onIncomingCall(
        callId: String,
        accountId: String,
        remoteUri: String,
        displayName: String
    ) {
        // TelecomManager: notify system of inbound call for native call screen.
        if (hasTelecomPermission()) {
            val telecomManager =
                context.getSystemService(Context.TELECOM_SERVICE) as TelecomManager
            val extras = android.os.Bundle().apply {
                putString("callId", callId)
                putString("remoteUri", remoteUri)
                putString("displayName", displayName)
            }
            // Full impl: telecomManager.addNewIncomingCall(phoneAccountHandle, extras)
        }
        emitEvent(mapOf(
            "type"        to "incomingCall",
            "callId"      to callId,
            "accountId"   to accountId,
            "remoteUri"   to remoteUri,
            "displayName" to displayName,
            "hasVideo"    to false
        ))
    }

    // ─── TelecomManager helpers ───────────────────────────────────────────
    private fun ensurePhoneAccountRegistered() {
        if (!hasTelecomPermission()) return
        val telecomManager =
            context.getSystemService(Context.TELECOM_SERVICE) as TelecomManager
        val handle = phoneAccountHandle()
        if (telecomManager.getPhoneAccount(handle) == null) {
            val account = PhoneAccount.builder(handle, "SipKit")
                .setCapabilities(PhoneAccount.CAPABILITY_CALL_PROVIDER)
                .build()
            telecomManager.registerPhoneAccount(account)
        }
    }

    private fun phoneAccountHandle(): PhoneAccountHandle {
        val component =
            ComponentName(context, SipKitConnectionService::class.java)
        return PhoneAccountHandle(component, "SipKit")
    }

    private fun hasTelecomPermission(): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
            ContextCompat.checkSelfPermission(
                context, Manifest.permission.MANAGE_OWN_CALLS
            ) == PackageManager.PERMISSION_GRANTED
        else true

    private fun emitEvent(event: Map<String, Any>) {
        android.os.Handler(android.os.Looper.getMainLooper()).post {
            eventSink?.success(event)
        }
    }
}
