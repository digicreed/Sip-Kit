package com.sipkit.sipkit_flutter

import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.os.SystemClock
import org.pjsip.pjsua2.*
import java.util.UUID
import java.util.concurrent.CountDownLatch

/** PJSIP 2.14 implementation with all externally initiated work serialized. */
internal class PjSipEngine : SipEngine {
    private var endpoint: Endpoint? = null
    private var sipThread: HandlerThread? = null
    private var sipHandler: Handler? = null
    private val accounts = mutableMapOf<String, NativeAccount>()
    private val calls = mutableMapOf<String, NativeCall>()
    private val pendingCalls = mutableMapOf<String, PendingCall>()
    private val transports = mutableMapOf<String, Int>()

    @Volatile
    private var started = false

    override fun init() {
        if (sipHandler != null) return
        val thread = HandlerThread("SipKit-PJSIP").also { it.start() }
        sipThread = thread
        sipHandler = Handler(thread.looper)
        try {
            onSip {
                val nativeEndpoint = Endpoint()
                nativeEndpoint.libCreate()
                nativeEndpoint.libRegisterThread("SipKit-PJSIP")
                val config = EpConfig().apply {
                    logConfig.level = 3
                    logConfig.consoleLevel = 3
                }
                nativeEndpoint.libInit(config)
                nativeEndpoint.libStart()
                endpoint = nativeEndpoint
                started = true
            }
        } catch (error: Throwable) {
            thread.quitSafely()
            sipHandler = null
            sipThread = null
            throw error
        }
    }

    override fun dispose() {
        val thread = sipThread ?: return
        onSip {
            if (started) {
                started = false
                pendingCalls.clear()
                val nativeCalls = calls.values.toList()
                val nativeAccounts = accounts.values.toList()
                calls.clear()
                accounts.clear()
                transports.clear()
                endpoint?.let {
                    runCatching { it.libDestroy() }
                    nativeCalls.forEach { call ->
                        runCatching { call.delete() }
                    }
                    nativeAccounts.forEach { account ->
                        runCatching { account.delete() }
                    }
                    runCatching { it.delete() }
                }
                endpoint = null
            }
        }
        thread.quitSafely()
        if (Thread.currentThread() !== thread) thread.join(5_000)
        sipHandler = null
        sipThread = null
    }

    override fun register(options: Map<String, Any?>) = onSip {
        check(started) { "PJSIP endpoint is not initialized" }
        val id = options.string("accountId")
        accounts[id]?.let { existing ->
            check(calls.values.none { it.account === existing }) {
                "Cannot replace account $id while it has active calls"
            }
            check(pendingCalls.values.none { it.account === existing }) {
                "Cannot replace account $id while it has prepared calls"
            }
            accounts.remove(id)
            existing.closeAccount()
        }
        val transport = options.stringOr("transport", "udp").lowercase()
        val user = options.string("username")
        val domain = options.string("domain")
        val registrar = options.stringOr("registrar", domain)
        val sipPort = options.intOr("sipPort", 5060)
        val config = AccountConfig().apply {
            idUri = "\"${options.stringOr("displayName", user)}\" <sip:$user@$domain>"
            regConfig.registrarUri = registrarUri(registrar, sipPort, transport)
            sipConfig.transportId = createTransport(transport, options)
            regConfig.timeoutSec =
                options.intOr("registrationExpiry", 600).toLong()
            natConfig.udpKaIntervalSec =
                options.intOr("keepAliveInterval", 15).toLong()
            sipConfig.authCreds.add(
                AuthCredInfo(
                    "Digest",
                    "*",
                    options.stringOr("authUsername", user),
                    0,
                    options.string("password"),
                ),
            )
            options.stringOr("outboundProxy", "")
                .takeIf { it.isNotBlank() }
                ?.let { sipConfig.proxies.add(uri(it, transport)) }
        }
        applyCodecs(options["codecPreferences"])
        NativeAccount(id, domain, registrar, sipPort, transport).also {
            it.create(config)
            accounts[id] = it
        }
        Unit
    }

    override fun unregister(accountId: String) = onSip {
        pendingCalls.entries.removeAll { it.value.account.key == accountId }
        check(calls.values.none { it.account.key == accountId }) {
            "Cannot unregister account $accountId while it has active calls"
        }
        val account = accounts.remove(accountId)
            ?: throw IllegalArgumentException("Unknown account $accountId")
        account.closeAccount()
    }

    override fun makeCall(accountId: String, target: String): SipCall = onSip {
        val account = accounts[accountId]
            ?: throw IllegalArgumentException("Unknown account $accountId")
        val id = "call_${UUID.randomUUID()}"
        val targetUri = account.destinationUri(target)
        pendingCalls[id] = PendingCall(account, targetUri)
        SipCall(id, targetUri)
    }

    override fun startPreparedCall(callId: String) = onSip {
        val pending = pendingCalls.remove(callId)
            ?: throw IllegalArgumentException("Unknown pending call $callId")
        val nativeCall = NativeCall(callId, pending.account, -1)
        calls[callId] = nativeCall
        try {
            nativeCall.makeCall(pending.targetUri, CallOpParam(true))
        } catch (error: Exception) {
            calls.remove(callId)
            nativeCall.delete()
            throw error
        }
    }

    override fun cancelPreparedCall(callId: String) = onSip {
        pendingCalls.remove(callId)
        Unit
    }

    override fun canReceive(accountId: String): Boolean {
        if (sipHandler == null) return false
        return onSip { started && accounts.containsKey(accountId) }
    }

    override fun answer(callId: String) = onSip {
        find(callId).answer(
            CallOpParam(true).apply {
                statusCode = pjsip_status_code.PJSIP_SC_OK
            },
        )
    }

    override fun hangup(callId: String) = onSip {
        pendingCalls.remove(callId)?.let { return@onSip }
        find(callId).hangup(CallOpParam())
    }

    override fun hold(callId: String, enabled: Boolean) = onSip {
        val param = CallOpParam()
        if (enabled) {
            find(callId).setHold(param)
        } else {
            param.opt.flag = pjsua_call_flag.PJSUA_CALL_UNHOLD.toLong()
            find(callId).reinvite(param)
        }
    }

    override fun mute(callId: String, muted: Boolean) = onSip {
        find(callId).getAudioMedia(0).adjustTxLevel(if (muted) 0.0f else 1.0f)
    }

    override fun dtmf(callId: String, digits: String) = onSip {
        find(callId).dialDtmf(digits)
    }

    override fun blindTransfer(callId: String, target: String) = onSip {
        val call = find(callId)
        call.xfer(call.account.destinationUri(target), CallOpParam())
    }

    override fun attendedTransfer(callId: String, otherCallId: String) = onSip {
        find(callId).xferReplaces(find(otherCallId), CallOpParam())
    }

    override fun diagnostics(accountId: String): Map<String, Any?> = onSip {
        val account = accounts[accountId]
        val info = account?.let { runCatching { it.info }.getOrNull() }
        mapOf(
            "platform" to "android",
            "nativeAvailable" to started,
            "accountPresent" to (account != null),
            "registrationActive" to (info?.regIsActive == true),
            "registrationCode" to (info?.regStatus ?: 0),
            "registrationReason" to (info?.regStatusText ?: "No account registration state"),
            "registrationDurationMs" to account?.registrationDurationMs,
            "transport" to account?.diagnosticTransport,
            "registrar" to account?.diagnosticRegistrar,
            "sipPort" to account?.diagnosticSipPort,
            "audioAvailable" to runCatching {
                requireNotNull(endpoint).audDevManager().enumDev2().size > 0
            }.getOrDefault(false),
        )
    }

    override fun callDiagnostics(callId: String): Map<String, Any?> = onSip {
        val callInfo = find(callId).info
        val audioMedia = (0 until callInfo.media.size)
            .map { callInfo.media[it] }
            .firstOrNull { it.type == pjmedia_type.PJMEDIA_TYPE_AUDIO }
        mapOf(
            "responseCode" to callInfo.lastStatusCode,
            "responseReason" to callInfo.lastReason,
            "audioMediaActive" to (
                audioMedia?.status == pjsua_call_media_status.PJSUA_CALL_MEDIA_ACTIVE ||
                    audioMedia?.status == pjsua_call_media_status.PJSUA_CALL_MEDIA_REMOTE_HOLD
                ),
            "audioMediaStatus" to audioMedia?.status?.toString(),
        )
    }

    private fun find(id: String) =
        calls[id] ?: throw IllegalArgumentException("Unknown call $id")

    private fun createTransport(
        name: String,
        options: Map<String, Any?>,
    ): Int {
        val key = if (name == "tls") {
            "$name|${options["verifyTls"]}|${options["tlsCaCertPath"]}"
        } else {
            name
        }
        transports[key]?.let { return it }
        val type = when (name) {
            "udp" -> pjsip_transport_type_e.PJSIP_TRANSPORT_UDP
            "tcp" -> pjsip_transport_type_e.PJSIP_TRANSPORT_TCP
            "tls" -> pjsip_transport_type_e.PJSIP_TRANSPORT_TLS
            else -> throw IllegalArgumentException(
                "Unsupported transport $name (use udp, tcp, or tls)",
            )
        }
        val config = TransportConfig().apply {
            port = 0
            if (name == "tls") {
                tlsConfig.verifyServer =
                    options["verifyTls"] as? Boolean ?: true
                (options["tlsCaCertPath"] as? String)
                    ?.takeIf { it.isNotBlank() }
                    ?.let { tlsConfig.caListFile = it }
            }
        }
        return requireNotNull(endpoint)
            .transportCreate(type, config)
            .also { transports[key] = it }
    }

    private fun applyCodecs(value: Any?) {
        val requested = value as? List<*> ?: return
        val nativeEndpoint = requireNotNull(endpoint)
        val available = nativeEndpoint.codecEnum2()
        requested.filterIsInstance<String>().forEachIndexed { index, prefix ->
            for (i in 0 until available.size) {
                val codecId = available[i].codecId
                if (codecId.startsWith(prefix, ignoreCase = true)) {
                    nativeEndpoint.codecSetPriority(
                        codecId,
                        (255 - index).coerceAtLeast(1).toShort(),
                    )
                }
            }
        }
    }

    private fun uri(value: String, transport: String?): String {
        val base = if (
            value.startsWith("sip:") || value.startsWith("sips:")
        ) {
            value
        } else {
            "sip:$value"
        }
        return if (transport != null && !base.contains(";transport=")) {
            "$base;transport=$transport"
        } else {
            base
        }
    }

    private fun registrarUri(
        value: String,
        port: Int,
        transport: String,
    ): String {
        val base = if (
            value.startsWith("sip:") || value.startsWith("sips:")
        ) {
            value
        } else {
            "sip:$value"
        }
        val scheme = if (base.startsWith("sips:")) "sips" else "sip"
        val authority = base.substringAfter(":")
            .substringBefore(";")
            .substringAfterLast("@")
        val host = if (authority.startsWith("[")) {
            authority.substringBefore("]") + "]"
        } else {
            authority.substringBefore(":")
        }
        return "$scheme:$host:$port;transport=$transport"
    }

    private fun postSip(block: () -> Unit) {
        if (!started) return
        sipHandler?.post {
            if (started) block()
        }
    }

    private fun <T> onSip(block: () -> T): T {
        val handler = sipHandler
            ?: throw IllegalStateException("PJSIP endpoint is not initialized")
        if (Looper.myLooper() == handler.looper) return block()
        val latch = CountDownLatch(1)
        var output: T? = null
        var failure: Throwable? = null
        if (!handler.post {
                try {
                    output = block()
                } catch (error: Throwable) {
                    failure = error
                } finally {
                    latch.countDown()
                }
            }
        ) {
            throw IllegalStateException("PJSIP execution thread is unavailable")
        }
        latch.await()
        failure?.let { throw it }
        @Suppress("UNCHECKED_CAST")
        return output as T
    }

    private fun Map<String, Any?>.string(key: String) =
        this[key] as? String ?: throw IllegalArgumentException("Missing $key")

    private fun Map<String, Any?>.stringOr(key: String, default: String) =
        this[key] as? String ?: default

    private fun Map<String, Any?>.intOr(key: String, default: Int) =
        (this[key] as? Number)?.toInt() ?: default

    private data class PendingCall(
        val account: NativeAccount,
        val targetUri: String,
    )

    private inner class NativeAccount(
        val key: String,
        private val domain: String,
        val diagnosticRegistrar: String,
        val diagnosticSipPort: Int,
        val diagnosticTransport: String,
    ) : Account() {
        var registrationDurationMs: Long? = null
            private set
        private var registrationStartedAtMs = 0L

        override fun onRegStarted(prm: OnRegStartedParam) {
            registrationStartedAtMs = SystemClock.elapsedRealtime()
            emitSipEvent(
                mapOf(
                    "type" to "accountStatus",
                    "accountId" to key,
                    "status" to if (prm.renew) {
                        "registering"
                    } else {
                        "unregistering"
                    },
                ),
            )
        }

        override fun onRegState(prm: OnRegStateParam) {
            if (registrationStartedAtMs > 0L) {
                registrationDurationMs =
                    SystemClock.elapsedRealtime() - registrationStartedAtMs
            }
            val accountInfo = info
            val status = when {
                accountInfo.regIsActive &&
                    accountInfo.regStatus in 200..299 -> "registered"
                !accountInfo.regIsActive &&
                    accountInfo.regStatus == 0 &&
                    prm.expiration == 0L -> "unregistered"
                else -> "registrationFailed"
            }
            emitSipEvent(
                mapOf(
                    "type" to "accountStatus",
                    "accountId" to key,
                    "status" to status,
                    "code" to accountInfo.regStatus,
                    "reason" to accountInfo.regStatusText,
                ),
            )
        }

        override fun onIncomingCall(prm: OnIncomingCallParam) {
            val nativeCallId = prm.callId
            postSip {
                if (accounts[key] !== this) return@postSip
                val provisionalId = "call_${UUID.randomUUID()}"
                val call = NativeCall(provisionalId, this, nativeCallId)
                val callInfo = call.info
                val id = callInfo.callIdString.ifBlank { provisionalId }
                call.key = id
                calls[id] = call
                SipKitCallController.incoming(id, callInfo.remoteUri)
                emitSipEvent(
                    mapOf(
                        "type" to "incomingCall",
                        "callId" to id,
                        "accountId" to key,
                        "remoteUri" to callInfo.remoteUri,
                        "displayName" to callInfo.remoteUri,
                        "hasVideo" to false,
                    ),
                )
            }
        }

        fun closeAccount() {
            runCatching { setRegistration(false) }
            runCatching { shutdown() }
            runCatching { delete() }
        }

        fun destinationUri(target: String): String {
            if (target.startsWith("sip:") || target.startsWith("sips:")) {
                return uri(target, diagnosticTransport)
            }
            val host = domain.ifBlank {
                diagnosticRegistrar.substringAfter("sip:")
                    .substringAfter("sips:")
                    .substringBefore(":")
            }
            return uri("sip:$target@$host:$diagnosticSipPort", diagnosticTransport)
        }
    }

    private inner class NativeCall(
        var key: String,
        val account: NativeAccount,
        id: Int,
    ) : Call(account, id) {
        override fun onCallState(prm: OnCallStateParam) {
            val callInfo = info
            val state = when (callInfo.state) {
                pjsip_inv_state.PJSIP_INV_STATE_CALLING -> "connecting"
                pjsip_inv_state.PJSIP_INV_STATE_EARLY -> "ringing"
                pjsip_inv_state.PJSIP_INV_STATE_CONFIRMED -> "established"
                pjsip_inv_state.PJSIP_INV_STATE_DISCONNECTED -> "terminated"
                else -> "connecting"
            }
            emitSipEvent(
                mapOf(
                    "type" to "callState",
                    "callId" to key,
                    "state" to state,
                    "code" to callInfo.lastStatusCode,
                    "reason" to callInfo.lastReason,
                ),
            )
            SipKitCallController.callState(key, state)
            if (state == "terminated") {
                postSip {
                    calls.remove(key)?.let { runCatching { it.delete() } }
                }
            }
        }

        override fun onCallMediaState(prm: OnCallMediaStateParam) {
            val callInfo = info
            for (i in 0 until callInfo.media.size) {
                val media = callInfo.media[i]
                if (
                    media.type == pjmedia_type.PJMEDIA_TYPE_AUDIO &&
                    (
                        media.status ==
                            pjsua_call_media_status.PJSUA_CALL_MEDIA_ACTIVE ||
                            media.status ==
                            pjsua_call_media_status.PJSUA_CALL_MEDIA_REMOTE_HOLD
                    )
                ) {
                    SipKitCallController.callState(
                        key,
                        if (
                            media.status ==
                            pjsua_call_media_status.PJSUA_CALL_MEDIA_REMOTE_HOLD
                        ) {
                            "held"
                        } else {
                            "established"
                        },
                    )
                    val audio = getAudioMedia(i)
                    val devices = requireNotNull(endpoint).audDevManager()
                    devices.captureDevMedia.startTransmit(audio)
                    audio.startTransmit(devices.playbackDevMedia)
                }
            }
        }
    }
}