package com.sipkit.sipkit_flutter

/**
 * Deliberately non-simulating build.  A missing native AAR must never produce
 * a plausible registration or call state, since that loses calls in release.
 */
internal class PjSipEngine : SipEngine {
    private fun unavailable(): Nothing =
        throw IllegalStateException("PJSIP_UNAVAILABLE: android/libs/pjsua2-2.14.aar is not bundled")
    override fun init() = unavailable()
    override fun dispose() = Unit
    override fun register(options: Map<String, Any?>) = unavailable()
    override fun unregister(accountId: String) = unavailable()
    override fun makeCall(accountId: String, target: String): SipCall = unavailable()
    override fun startPreparedCall(callId: String) = unavailable()
    override fun cancelPreparedCall(callId: String) = unavailable()
    override fun canReceive(accountId: String): Boolean = false
    override fun answer(callId: String) = unavailable()
    override fun hangup(callId: String) = unavailable()
    override fun hold(callId: String, enabled: Boolean) = unavailable()
    override fun mute(callId: String, muted: Boolean) = unavailable()
    override fun dtmf(callId: String, digits: String) = unavailable()
    override fun blindTransfer(callId: String, target: String) = unavailable()
    override fun attendedTransfer(callId: String, otherCallId: String) = unavailable()
    override fun diagnostics(accountId: String): Map<String, Any?> = mapOf(
        "nativeAvailable" to false,
        "accountPresent" to false,
        "audioAvailable" to false,
    )
    override fun callDiagnostics(callId: String): Map<String, Any?> = unavailable()
}