package com.sipkit.sipkit_flutter

import android.content.Context
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build
import android.telecom.CallAudioState
import android.telecom.Connection
import android.telecom.ConnectionRequest
import android.telecom.ConnectionService
import android.telecom.DisconnectCause
import android.telecom.PhoneAccountHandle
import android.telecom.TelecomManager
import androidx.annotation.RequiresApi

@RequiresApi(Build.VERSION_CODES.M)
class SipKitConnectionService : ConnectionService() {

    override fun onCreateIncomingConnection(
        connectionManagerPhoneAccount: PhoneAccountHandle?,
        request: ConnectionRequest?
    ): Connection {
        return SipConnection(this, request?.extras?.getString("callId") ?: "",
            request?.extras?.getString("displayName") ?: "Unknown", true,
            request?.extras?.getBoolean("sipReady", false) ?: false)
    }

    override fun onCreateOutgoingConnection(
        connectionManagerPhoneAccount: PhoneAccountHandle?,
        request: ConnectionRequest?
    ): Connection {
        val sipkit = request?.extras?.getBundle("sipkit")
        val connection = SipConnection(this, sipkit?.getString("callId") ?: "",
            sipkit?.getString("displayName") ?: "Sip call", false, true)
        connection.startOutgoing()
        return connection
    }

    override fun onCreateOutgoingConnectionFailed(
        connectionManagerPhoneAccount: PhoneAccountHandle?,
        request: ConnectionRequest?,
    ) {
        request?.extras?.getBundle("sipkit")?.getString("callId")?.let {
            runCatching { SipKitCallController.cancelPreparedCall(it) }
        }
    }

    private class SipConnection(
        context: Context,
        override val callId: String,
        displayName: String,
        incoming: Boolean,
        private var sipReady: Boolean,
    ) : Connection(), SipKitConnection {
        private val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        private val mainHandler = android.os.Handler(android.os.Looper.getMainLooper())
        private var answerPending = false
        private val correlationTimeout = Runnable {
            if (!sipReady) {
                setDisconnected(DisconnectCause(
                    DisconnectCause.ERROR,
                    "Matching SIP INVITE did not arrive",
                ))
                SipKitCallController.untrack(callId)
                destroy()
            }
        }
        init {
            setConnectionCapabilities(CAPABILITY_HOLD or CAPABILITY_SUPPORT_HOLD or CAPABILITY_MUTE)
            setAudioModeIsVoip(true)
            setCallerDisplayName(displayName, TelecomManager.PRESENTATION_ALLOWED)
            if (incoming) setRinging() else setDialing()
            SipKitCallController.track(this)
            if (incoming && !sipReady) {
                mainHandler.postDelayed(correlationTimeout, 20_000)
            }
        }
        fun startOutgoing() = perform { SipKitCallController.startPreparedCall(callId) }
        override fun onAnswer() {
            if (!sipReady) {
                answerPending = true
                return
            }
            perform { SipKitCallController.answer(callId) }
        }
        override fun onDisconnect() = perform { SipKitCallController.hangup(callId) }
        override fun onHold() = perform { SipKitCallController.hold(callId, true) }
        override fun onUnhold() = perform { SipKitCallController.hold(callId, false) }
        override fun onMuteStateChanged(isMuted: Boolean) =
            perform { SipKitCallController.mute(callId, isMuted) }
        override fun onCallAudioStateChanged(state: CallAudioState) {
            super.onCallAudioStateChanged(state)
            audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val wantedType = when (state.route) {
                    CallAudioState.ROUTE_SPEAKER -> AudioDeviceInfo.TYPE_BUILTIN_SPEAKER
                    CallAudioState.ROUTE_EARPIECE -> AudioDeviceInfo.TYPE_BUILTIN_EARPIECE
                    CallAudioState.ROUTE_BLUETOOTH -> AudioDeviceInfo.TYPE_BLUETOOTH_SCO
                    CallAudioState.ROUTE_WIRED_HEADSET -> AudioDeviceInfo.TYPE_WIRED_HEADSET
                    else -> null
                }
                wantedType?.let { type ->
                    runCatching {
                        audioManager.availableCommunicationDevices
                            .firstOrNull { it.type == type }
                            ?.let { audioManager.setCommunicationDevice(it) }
                    }
                }
            } else {
                @Suppress("DEPRECATION")
                run { audioManager.isSpeakerphoneOn = state.route == CallAudioState.ROUTE_SPEAKER }
            }
        }

        private inline fun perform(operation: () -> Unit) {
            try {
                operation()
            } catch (error: Exception) {
                setDisconnected(DisconnectCause(
                    DisconnectCause.ERROR,
                    error.message ?: "Native SIP operation failed",
                ))
                SipKitCallController.untrack(callId)
                destroy()
            }
        }
        override fun applySipState(state: String) = when (state) {
            "ringing" -> setRinging()
            "established" -> setActive()
            "held" -> setOnHold()
            "terminated" -> {
                setDisconnected(DisconnectCause(DisconnectCause.REMOTE))
                SipKitCallController.untrack(callId)
                destroy()
            }
            else -> setDialing()
        }
        override fun markSipReady() {
            if (sipReady) return
            sipReady = true
            mainHandler.removeCallbacks(correlationTimeout)
            if (answerPending) {
                answerPending = false
                perform { SipKitCallController.answer(callId) }
            }
        }
    }
}
