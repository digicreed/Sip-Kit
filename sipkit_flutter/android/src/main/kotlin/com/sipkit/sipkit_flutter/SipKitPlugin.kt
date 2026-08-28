package com.sipkit.sipkit_flutter

import android.Manifest
import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
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

/** Flutter channel host. SIP work is owned by [PjSipEngine], never an Activity. */
class SipKitPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware,
    EventChannel.StreamHandler {
    private lateinit var context: Context
    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private var engine: SipEngine? = null

    override fun onAttachedToEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        SipKitCallController.attach(context)
        methodChannel = MethodChannel(binding.binaryMessenger, "com.sipkit.sipkit_flutter/pjsip")
        eventChannel = EventChannel(binding.binaryMessenger, "com.sipkit.sipkit_flutter/pjsip_events")
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)
    }
    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null); eventChannel.setStreamHandler(null)
        engine?.dispose(); engine = null; SipKitCallController.engine = null
    }
    override fun onAttachedToActivity(binding: ActivityPluginBinding) = Unit
    override fun onDetachedFromActivityForConfigChanges() = Unit
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) = Unit
    override fun onDetachedFromActivity() = Unit
    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) = SipKitEventBus.setSink(events)
    override fun onCancel(arguments: Any?) = SipKitEventBus.setSink(null)

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "init" -> {
                    check(engine == null) { "Already initialized" }
                    engine = PjSipEngine().also { it.init() }
                    SipKitCallController.engine = engine
                    ensurePhoneAccountRegistered()
                    SipKitForegroundService.start(context)
                    result.success(null)
                }
                "dispose" -> { engine?.dispose(); engine = null; SipKitCallController.engine = null; SipKitForegroundService.stop(context); result.success(null) }
                "registerAccount" -> register(call, result)
                "unregister" -> withEngine(result) { unregister(required(call, "accountId")); result.success(null) }
                "makeCall" -> makeCall(call, result)
                "answer" -> withEngine(result) { answer(required(call, "callId")); result.success(null) }
                "hangup" -> withEngine(result) { hangup(required(call, "callId")); result.success(null) }
                "hold" -> withEngine(result) { hold(required(call, "callId"), true); result.success(null) }
                "unhold" -> withEngine(result) { hold(required(call, "callId"), false); result.success(null) }
                "mute" -> withEngine(result) { mute(required(call, "callId"), call.argument<Boolean>("muted") ?: true); result.success(null) }
                "sendDtmf" -> withEngine(result) { dtmf(required(call, "callId"), required(call, "digits")); result.success(null) }
                "blindTransfer" -> withEngine(result) { blindTransfer(required(call, "callId"), required(call, "targetUri")); result.success(null) }
                "attendedTransfer" -> withEngine(result) { attendedTransfer(required(call, "callId"), required(call, "otherCallId")); result.success(null) }
                "diagnostics" -> withEngine(result) {
                    val report = diagnostics(required(call, "accountId")).toMutableMap()
                    report["platform"] = "android"
                    report["microphonePermission"] =
                        ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED
                    report["telecomPermission"] = hasTelecomPermission()
                    result.success(report)
                }
                "callDiagnostics" -> withEngine(result) { result.success(callDiagnostics(required(call, "callId"))) }
                "enableVideo" -> result.error("VIDEO_UNSUPPORTED", "Video is out of scope on Android", null)
                else -> result.notImplemented()
            }
        } catch (e: IllegalArgumentException) { result.error("INVALID_ARGS", e.message, null) }
        catch (e: IllegalStateException) { result.error(if (e.message?.startsWith("PJSIP_UNAVAILABLE") == true) "PJSIP_UNAVAILABLE" else "SIP_STATE_ERROR", e.message, null) }
        catch (e: Exception) { result.error("PJSIP_ERROR", e.message ?: e.javaClass.simpleName, null) }
    }

    private fun register(call: MethodCall, result: MethodChannel.Result) = withEngine(result) {
        val values = listOf("accountId", "username", "password", "domain").associateWith { call.argument<Any>(it) ?: throw IllegalArgumentException("Missing $it") }.toMutableMap()
        listOf("registrar", "sipPort", "transport", "outboundProxy", "verifyTls", "tlsCaCertPath",
            "codecPreferences", "keepAliveInterval", "displayName", "authUsername", "registrationExpiry").forEach {
            values[it] = call.argument<Any>(it)
        }
        register(values); result.success(null)
    }
    private fun makeCall(call: MethodCall, result: MethodChannel.Result) = withEngine(result) {
        val sipCall = makeCall(required(call, "accountId"), required(call, "target"))
        val id = sipCall.id
        ensurePhoneAccountRegistered()
        if (!hasTelecomPermission()) {
            cancelPreparedCall(id)
            throw IllegalStateException("Telecom permission is required to place a call")
        }
        val extras = Bundle().apply { putString("callId", id); putString("displayName", sipCall.targetUri) }
        try {
            (context.getSystemService(Context.TELECOM_SERVICE) as TelecomManager).placeCall(
                android.net.Uri.parse(sipCall.targetUri),
                Bundle().apply { putParcelable(TelecomManager.EXTRA_PHONE_ACCOUNT_HANDLE, phoneAccountHandle()); putBundle("sipkit", extras) })
        } catch (error: Exception) {
            cancelPreparedCall(id)
            throw error
        }
        result.success(id)
    }
    private fun required(call: MethodCall, key: String): String =
        call.argument<String>(key) ?: throw IllegalArgumentException("Missing $key")
    private inline fun withEngine(result: MethodChannel.Result, block: SipEngine.() -> Unit) {
        val value = engine ?: return result.error("SIP_NOT_INITIALIZED", "Call init before using SIP", null)
        value.block()
    }
    private fun ensurePhoneAccountRegistered() {
        if (!hasTelecomPermission()) return
        val manager = context.getSystemService(Context.TELECOM_SERVICE) as TelecomManager
        if (manager.getPhoneAccount(phoneAccountHandle()) == null)
            manager.registerPhoneAccount(PhoneAccount.builder(phoneAccountHandle(), "SipKit")
                .setCapabilities(PhoneAccount.CAPABILITY_CALL_PROVIDER).build())
    }
    private fun phoneAccountHandle() = PhoneAccountHandle(ComponentName(context, SipKitConnectionService::class.java), "SipKit")
    private fun hasTelecomPermission() = Build.VERSION.SDK_INT < Build.VERSION_CODES.M ||
        ContextCompat.checkSelfPermission(context, Manifest.permission.MANAGE_OWN_CALLS) == PackageManager.PERMISSION_GRANTED
}