package com.sipkit.sipkit_flutter

import android.os.Build
import android.telecom.Connection
import android.telecom.ConnectionRequest
import android.telecom.ConnectionService
import android.telecom.PhoneAccountHandle
import android.telecom.TelecomManager
import androidx.annotation.RequiresApi

// ---------------------------------------------------------------------------
// SipKitConnectionService — Android ConnectionService stub
// ---------------------------------------------------------------------------
// Registered in AndroidManifest.xml as a <service> with
// BIND_TELECOM_CONNECTION_SERVICE permission so the system can present the
// native incoming-call screen and integrate with Bluetooth headsets, the
// system call log, and Do Not Disturb rules.
//
// Full implementation:
//   1. Inject this class into the PJSIP incoming-call callback:
//        telecomManager.addNewIncomingCall(phoneAccountHandle, extras)
//   2. Override onCreateIncomingConnection() to build a Connection object
//      that proxies audio/video to PJSUA2 media streams.
//   3. Override onCreateOutgoingConnection() similarly.
//
// All call state changes must be forwarded to the system via:
//   connection.setActive()  / connection.setOnHold()  / connection.setDisconnected()
// ---------------------------------------------------------------------------

@RequiresApi(Build.VERSION_CODES.M)
class SipKitConnectionService : ConnectionService() {

    override fun onCreateIncomingConnection(
        connectionManagerPhoneAccount: PhoneAccountHandle?,
        request: ConnectionRequest?
    ): Connection {
        // Stub: return a disconnected placeholder.
        // Replace with a real SipKitConnection that bridges to PJSUA2.
        return object : Connection() {
            init {
                setConnectionCapabilities(
                    CAPABILITY_HOLD or CAPABILITY_SUPPORT_HOLD or
                    CAPABILITY_MUTE or CAPABILITY_RESPOND_VIA_TEXT
                )
                setCallerDisplayName(
                    request?.extras?.getString("displayName") ?: "Unknown",
                    TelecomManager.PRESENTATION_ALLOWED
                )
                setInitialized()
            }
        }
    }

    override fun onCreateOutgoingConnection(
        connectionManagerPhoneAccount: PhoneAccountHandle?,
        request: ConnectionRequest?
    ): Connection {
        // Stub: return an initializing placeholder.
        return object : Connection() {
            init {
                setConnectionCapabilities(
                    CAPABILITY_HOLD or CAPABILITY_SUPPORT_HOLD or CAPABILITY_MUTE
                )
                setDialing()
            }
        }
    }
}
