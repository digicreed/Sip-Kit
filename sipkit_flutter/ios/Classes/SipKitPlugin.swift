import Flutter
import UIKit
import CallKit
import PushKit
import AVFoundation

// ---------------------------------------------------------------------------
// SipKitPlugin — iOS native host for PjsipEngine
// ---------------------------------------------------------------------------
// Bridges Flutter platform channels to PJSUA2 (PJSIP) and CallKit.
//
// Method channel:  com.sipkit.sipkit_flutter/pjsip
// Event channel:   com.sipkit.sipkit_flutter/pjsip_events
//
// Build ios/Frameworks/PJSIP.xcframework before pod install. The podspec
// conditionally activates this bridge only when that artifact exists.
//
// Required Info.plist keys:
//   NSMicrophoneUsageDescription
//   UIBackgroundModes: [ audio, voip ]
//
// Required Entitlement (to receive VoIP pushes):
//   aps-environment: development | production
// ---------------------------------------------------------------------------

public class SipKitPlugin: NSObject, FlutterPlugin {

    // ─── Flutter channels ──────────────────────────────────────────────────
    private var methodChannel: FlutterMethodChannel?
    private var eventChannel: FlutterEventChannel?
    private var eventSink: FlutterEventSink?

    // ─── CallKit ───────────────────────────────────────────────────────────
    private let callKitProvider: CXProvider
    private let callKitController = CXCallController()

    // ─── PushKit ───────────────────────────────────────────────────────────
    private var pushRegistry: PKPushRegistry?
    private let pjsip = SKPJSIPBridge()

    // ─── State ────────────────────────────────────────────────────────────
    /// Maps SipKit callId → CXCall UUID (for CallKit correlation).
    private var callUUIDs: [String: UUID] = [:]
    /// Push notifications can reach CallKit before the corresponding INVITE.
    private var pendingPushes: [String: (uuid: UUID, accountId: String, remoteUri: String)] = [:]
    private var pendingPushOrder: [String] = []
    private var pendingPushTimeouts: [String: DispatchWorkItem] = [:]
    private var pendingAnswerActions: [String: CXAnswerCallAction] = [:]
    private var pendingOutbound: [String: (accountId: String, target: String, result: FlutterResult)] = [:]
    private var didSetupVoipPushRegistry = false

    // ─── Registration ──────────────────────────────────────────────────────
    public static func register(with registrar: FlutterPluginRegistrar) {
        let messenger = registrar.messenger()
        let instance = SipKitPlugin()

        instance.methodChannel = FlutterMethodChannel(
            name: "com.sipkit.sipkit_flutter/pjsip",
            binaryMessenger: messenger)
        instance.methodChannel?.setMethodCallHandler(instance.handle)

        instance.eventChannel = FlutterEventChannel(
            name: "com.sipkit.sipkit_flutter/pjsip_events",
            binaryMessenger: messenger)
        instance.eventChannel?.setStreamHandler(instance)

        registrar.addApplicationDelegate(instance)
    }

    // ─── Init ──────────────────────────────────────────────────────────────
    override init() {
        let config = CXProviderConfiguration()
        config.localizedName = "SipKit"
        config.supportsVideo = false // PJSUA2 bridge intentionally exposes audio only.
        config.supportedHandleTypes = [.phoneNumber, .generic]
        config.maximumCallGroups = 2
        config.maximumCallsPerCallGroup = 5
        callKitProvider = CXProvider(configuration: config)
        super.init()
        pjsip.delegate = self
        callKitProvider.setDelegate(self, queue: DispatchQueue.main)
        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setCategory(
            .playAndRecord,
            mode: .voiceChat,
            options: [.allowBluetooth]
        )
    }

    // ─── Method channel handler ────────────────────────────────────────────
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.handle(call, result: result) }
            return
        }
        guard let args = call.arguments as? [String: Any] else {
            if call.method == "init" || call.method == "dispose" {
                handleLifecycle(call.method, result: result)
                return
            }
            result(FlutterError(code: "INVALID_ARGS", message: "Expected map arguments", details: nil))
            return
        }

        switch call.method {
        case "init":
            handleLifecycle("init", result: result)
        case "dispose":
            handleLifecycle("dispose", result: result)
        case "registerAccount":
            registerAccount(args: args, result: result)
        case "unregister":
            unregister(args: args, result: result)
        case "makeCall":
            makeCall(args: args, result: result)
        case "answer":
            answerCall(args: args, result: result)
        case "hangup":
            hangupCall(args: args, result: result)
        case "hold":
            holdCall(args: args, muted: true, result: result)
        case "unhold":
            holdCall(args: args, muted: false, result: result)
        case "mute":
            muteCall(args: args, result: result)
        case "sendDtmf":
            sendDtmf(args: args, result: result)
        case "blindTransfer":
            blindTransfer(args: args, result: result)
        case "attendedTransfer":
            attendedTransfer(args: args, result: result)
        case "enableVideo":
            enableVideo(args: args, result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // ─── Lifecycle ─────────────────────────────────────────────────────────
    private func handleLifecycle(_ method: String, result: FlutterResult) {
        var error: NSError?
        let ok = method == "init" ? pjsip.start(&error) : pjsip.stop(&error)
        if !ok { fail(error, result); return }
        if method == "dispose" {
            callUUIDs.removeAll()
            deactivateVoipPushRegistry()
        }
        result(nil)
    }

    // ─── Account management ────────────────────────────────────────────────
    private func registerAccount(args: [String: Any], result: FlutterResult) {
        guard let accountId = args["accountId"] as? String,
              let username  = args["username"]  as? String,
              let password  = args["password"]  as? String,
              let domain    = args["domain"]    as? String else {
            result(FlutterError(code: "INVALID_ARGS", message: "Missing account args", details: nil))
            return
        }

        _ = username; _ = password; _ = domain
        var error: NSError?
        guard pjsip.registerAccount(args, error: &error) else { fail(error, result); return }
        setupVoipPushRegistry()
        result(nil) // registration status is emitted by Account::onRegState.
    }

    private func unregister(args: [String: Any], result: FlutterResult) {
        guard let accountId = args["accountId"] as? String else {
            result(FlutterError(code: "INVALID_ARGS", message: "Missing accountId", details: nil))
            return
        }
        var error: NSError?
        guard pjsip.unregisterAccount(accountId, error: &error) else { fail(error, result); return }
        if !pjsip.hasReceivingAccounts() { deactivateVoipPushRegistry() }
        result(nil)
    }

    // ─── Outbound calls ────────────────────────────────────────────────────
    private func makeCall(args: [String: Any], result: FlutterResult) {
        guard let accountId = args["accountId"] as? String,
              let target    = args["target"]    as? String else {
            result(FlutterError(code: "INVALID_ARGS", message: "Missing makeCall args", details: nil))
            return
        }
        guard !(args["video"] as? Bool ?? false) else {
            result(FlutterError(code: "VIDEO_UNSUPPORTED", message: "PJSIP iOS bridge supports audio calls only", details: nil)); return
        }
        let callId = UUID().uuidString
        let uuid   = UUID()
        callUUIDs[callId] = uuid
        pendingOutbound[callId] = (accountId, target, result)

        let handle = CXHandle(type: .generic, value: target)
        let startAction = CXStartCallAction(call: uuid, handle: handle)
        startAction.isVideo = false

        let transaction = CXTransaction(action: startAction)
        callKitController.request(transaction) { [weak self] error in
            DispatchQueue.main.async {
                if let error, let reservation = self?.pendingOutbound.removeValue(forKey: callId) {
                    self?.callUUIDs.removeValue(forKey: callId)
                    reservation.result(FlutterError(code: "CALLKIT_ERROR", message: error.localizedDescription, details: nil))
                }
            }
        }
    }

    // ─── Inbound call answer ───────────────────────────────────────────────
    private func answerCall(args: [String: Any], result: FlutterResult) {
        guard let callId = args["callId"] as? String,
              let uuid   = callUUIDs[callId] else {
            result(FlutterError(code: "INVALID_ARGS", message: "Unknown callId", details: nil))
            return
        }
        guard !(args["video"] as? Bool ?? false) else { result(FlutterError(code: "VIDEO_UNSUPPORTED", message: "Audio only", details: nil)); return }

        let action = CXAnswerCallAction(call: uuid)
        let transaction = CXTransaction(action: action)
        callKitController.request(transaction) { [weak self] error in
            if let error { self?.fail(error as NSError, result) } else { result(nil) }
        }
    }

    private func hangupCall(args: [String: Any], result: FlutterResult) {
        guard let callId = args["callId"] as? String,
              let uuid   = callUUIDs[callId] else {
            result(FlutterError(code: "INVALID_ARGS", message: "Unknown callId", details: nil))
            return
        }
        let action = CXEndCallAction(call: uuid)
        let transaction = CXTransaction(action: action)
        callKitController.request(transaction) { [weak self] error in
            if let error { self?.fail(error as NSError, result) } else { result(nil) }
        }
    }

    private func holdCall(args: [String: Any], muted: Bool, result: FlutterResult) {
        guard let callId = args["callId"] as? String,
              let uuid   = callUUIDs[callId] else {
            result(FlutterError(code: "INVALID_ARGS", message: "Unknown callId", details: nil))
            return
        }
        let action = CXSetHeldCallAction(call: uuid, onHold: muted)
        callKitController.request(CXTransaction(action: action)) { [weak self] error in
            if let error { self?.fail(error as NSError, result) } else { result(nil) }
        }
    }

    private func muteCall(args: [String: Any], result: FlutterResult) {
        guard let callId = args["callId"] as? String,
              let uuid   = callUUIDs[callId] else {
            result(FlutterError(code: "INVALID_ARGS", message: "Unknown callId", details: nil))
            return
        }
        let muted = args["muted"] as? Bool ?? false
        let action = CXSetMutedCallAction(call: uuid, muted: muted)
        callKitController.request(CXTransaction(action: action)) { [weak self] error in
            if let error { self?.fail(error as NSError, result) } else { result(nil) }
        }
    }

    private func sendDtmf(args: [String: Any], result: FlutterResult) {
        guard let callId = args["callId"] as? String,
              let digits = args["digits"] as? String,
              let uuid   = callUUIDs[callId] else {
            result(FlutterError(code: "INVALID_ARGS", message: "Unknown callId/digits", details: nil))
            return
        }
        let action = CXPlayDTMFCallAction(call: uuid, digits: digits, type: .singleTone)
        callKitController.request(CXTransaction(action: action)) { [weak self] error in
            if let error { self?.fail(error as NSError, result) } else { result(nil) }
        }
    }

    private func blindTransfer(args: [String: Any], result: FlutterResult) {
        guard let callId    = args["callId"]    as? String,
              let targetUri = args["targetUri"] as? String else {
            result(FlutterError(code: "INVALID_ARGS", message: "Missing transfer args", details: nil))
            return
        }
        var error: NSError?
        guard pjsip.blindTransfer(callId, target: targetUri, error: &error) else { fail(error, result); return }
        result(nil)
    }

    private func attendedTransfer(args: [String: Any], result: FlutterResult) {
        guard let callId      = args["callId"]      as? String,
              let otherCallId = args["otherCallId"] as? String else {
            result(FlutterError(code: "INVALID_ARGS", message: "Missing attended transfer args", details: nil))
            return
        }
        var error: NSError?
        guard pjsip.attendedTransfer(callId, otherCall: otherCallId, error: &error) else { fail(error, result); return }
        result(nil)
    }

    private func enableVideo(args: [String: Any], result: FlutterResult) {
        guard let callId  = args["callId"]  as? String,
              let enabled = args["enabled"] as? Bool else {
            result(FlutterError(code: "INVALID_ARGS", message: "Missing enableVideo args", details: nil))
            return
        }
        _ = callId; _ = enabled
        result(FlutterError(code: "VIDEO_UNSUPPORTED", message: "PJSIP iOS bridge supports audio calls only", details: nil))
    }

    // ─── Incoming call reported by the PJSUA2 account callback ─────────────
    func onIncomingCall(callId: String, accountId: String, remoteUri: String, displayName: String) {
        let uuid = UUID()
        callUUIDs[callId] = uuid

        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .generic, value: remoteUri)
        update.localizedCallerName = displayName
        update.hasVideo = false

        callKitProvider.reportNewIncomingCall(with: uuid, update: update) { [weak self] error in
            guard error == nil else { return }
            self?.emitEvent([
                "type": "incomingCall",
                "callId": callId,
                "accountId": accountId,
                "remoteUri": remoteUri,
                "displayName": displayName,
                "hasVideo": false
            ])
        }
    }

    // ─── VoIP push (PKPushRegistry + PKPushRegistryDelegate) ──────────────
    //
    // The OS calls pushRegistry(_:didReceiveIncomingPushWith:) when a VoIP
    // push lands, even when the app is fully terminated.  We MUST call
    // CXProvider.reportNewIncomingCall before the completion handler returns
    // (within ~2 seconds), or iOS will terminate the process.
    //
    // Payload format sent by the server push-worker:
    // {
    //   "aps": { "alert": { "title": "Incoming Call", "body": "<callerName>" } },
    //   "callId":      "<uuid>",
    //   "remoteUri":   "sip:alice@example.com",
    //   "displayName": "Alice",
    //   "accountId":   "<accountId>"
    // }
    private func setupVoipPushRegistry() {
        guard pjsip.isAvailable else { return }
        guard !didSetupVoipPushRegistry else { return }
        didSetupVoipPushRegistry = true
        let registry = PKPushRegistry(queue: .main)
        registry.delegate = self
        registry.desiredPushTypes = [.voIP]
        pushRegistry = registry
    }

    private func deactivateVoipPushRegistry() {
        pushRegistry?.desiredPushTypes = []
        pushRegistry = nil
        didSetupVoipPushRegistry = false
    }

    // ─── Event emission ───────────────────────────────────────────────────
    private func emitEvent(_ event: [String: Any]) {
        DispatchQueue.main.async { [weak self] in
            self?.eventSink?(event)
        }
    }

    private func expirePendingPush(
        _ callId: String,
        code: String,
        reason: String
    ) {
        pendingPushTimeouts.removeValue(forKey: callId)?.cancel()
        pendingAnswerActions.removeValue(forKey: callId)?.fail()
        guard let pending = pendingPushes.removeValue(forKey: callId) else { return }
        pendingPushOrder.removeAll { $0 == callId }
        callUUIDs.removeValue(forKey: callId)
        callKitProvider.reportCall(with: pending.uuid, endedAt: Date(), reason: .failed)
        emitEvent(["type": "pjsipError", "code": code, "callId": callId, "reason": reason])
    }

    private func fail(_ error: NSError?, _ result: FlutterResult) {
        result(FlutterError(code: error?.localizedDescription.hasPrefix("PJSIP_UNAVAILABLE") == true ? "PJSIP_UNAVAILABLE" : "PJSIP_ERROR",
                            message: error?.localizedDescription ?? "PJSIP operation failed", details: nil))
    }
}
// ─── PKPushRegistryDelegate ───────────────────────────────────────────────────
extension SipKitPlugin: PKPushRegistryDelegate {

    /// Called when PushKit issues a new device token.
    /// Upload this token to POST /api/v1/push-token so the server can reach
    /// this device for cold-start wakeup.
    public func pushRegistry(
        _ registry: PKPushRegistry,
        didUpdate pushCredentials: PKPushCredentials,
        for type: PKPushType
    ) {
        guard type == .voIP else { return }
        let tokenData = pushCredentials.token
        let tokenString = tokenData.map { String(format: "%02x", $0) }.joined()
        emitEvent([
            "type":     "voipPushToken",
            "platform": "apns",
            "token":    tokenString
        ])
    }

    /// PushKit is activated only after a native account exists. Every accepted
    /// push is reported to CallKit before this completion handler returns.
    public func pushRegistry(
        _ registry: PKPushRegistry,
        didReceiveIncomingPushWith payload: PKPushPayload,
        for type: PKPushType,
        completion: @escaping () -> Void
    ) {
        guard type == .voIP else {
            completion()
            return
        }
        guard pjsip.isAvailable else {
            emitEvent(["type": "pjsipError", "code": "PJSIP_UNAVAILABLE",
                       "reason": "Cannot create a SIP call without PJSIP.xcframework"])
            completion()
            return
        }
        let dict = payload.dictionaryPayload
        guard let callId = dict["callId"] as? String, !callId.isEmpty,
              let accountId = dict["accountId"] as? String, !accountId.isEmpty else {
            emitEvent(["type": "pjsipError", "code": "INVALID_PUSH",
                       "reason": "VoIP push requires SIP Call-ID and accountId"])
            completion()
            return
        }
        let remoteUri = dict["remoteUri"] as? String ?? "sip:unknown@unknown"
        let displayName = dict["displayName"] as? String ?? remoteUri

        var startError: NSError?
        guard pjsip.start(&startError) else {
            emitEvent(["type": "pjsipError", "code": "PJSIP_ERROR",
                       "reason": startError?.localizedDescription ?? "Unable to start PJSIP for VoIP push"])
            completion()
            return
        }
        guard pjsip.canReceiveAccount(accountId) else {
            emitEvent(["type": "pjsipError", "code": "ACCOUNT_NOT_READY",
                       "callId": callId, "accountId": accountId,
                       "reason": "Restore the native SIP account before accepting a VoIP push"])
            completion()
            return
        }
        guard pendingPushes[callId] == nil && callUUIDs[callId] == nil else {
            emitEvent(["type": "pjsipError", "code": "DUPLICATE_PUSH",
                       "callId": callId, "reason": "Duplicate SIP Call-ID in VoIP push"])
            completion()
            return
        }

        let uuid = UUID()
        if pendingPushOrder.count >= 32 {
            let expired = pendingPushOrder.removeFirst()
            expirePendingPush(
                expired,
                code: "PUSH_CORRELATION_EXPIRED",
                reason: "VoIP push could not be correlated to a SIP INVITE"
            )
        }
        callUUIDs[callId] = uuid
        pendingPushes[callId] = (uuid, accountId, remoteUri)
        pendingPushOrder.append(callId)

        let update = CXCallUpdate()
        update.remoteHandle    = CXHandle(type: .generic, value: remoteUri)
        update.localizedCallerName = displayName
        update.hasVideo        = false

        // Must reach CallKit before completion() or within ~2 s after push delivery.
        callKitProvider.reportNewIncomingCall(with: uuid, update: update) { [weak self] error in
            DispatchQueue.main.async {
                guard let self else { completion(); return }
                if let error {
                    self.expirePendingPush(
                        callId,
                        code: "PUSH_PROVIDER_REJECTED",
                        reason: "CallKit rejected the VoIP push: \(error.localizedDescription)"
                    )
                } else {
                    self.emitEvent([
                        "type": "incomingCall", "callId": callId,
                        "accountId": accountId, "remoteUri": remoteUri,
                        "displayName": displayName, "hasVideo": false
                    ])
                    let timeout = DispatchWorkItem { [weak self] in
                        self?.expirePendingPush(
                            callId,
                            code: "PUSH_CORRELATION_TIMEOUT",
                            reason: "Matching SIP INVITE did not arrive within 20 seconds"
                        )
                    }
                    self.pendingPushTimeouts[callId] = timeout
                    DispatchQueue.main.asyncAfter(
                        deadline: .now() + 20,
                        execute: timeout
                    )
                }
                completion()
            }
        }
    }

    public func pushRegistry(
        _ registry: PKPushRegistry,
        didInvalidatePushTokenFor type: PKPushType
    ) {
        guard type == .voIP else { return }
        emitEvent(["type": "voipPushTokenInvalidated", "platform": "apns"])
    }
}

// ─── CXProviderDelegate ───────────────────────────────────────────────────────
extension SipKitPlugin: CXProviderDelegate {

    public func providerDidReset(_ provider: CXProvider) {
        pendingAnswerActions.values.forEach { $0.fail() }
        pendingAnswerActions.removeAll()
        pendingPushes.removeAll()
        pendingPushOrder.removeAll()
        pendingPushTimeouts.values.forEach { $0.cancel() }
        pendingPushTimeouts.removeAll()
        pendingOutbound.values.forEach {
            $0.result(FlutterError(code: "CALLKIT_RESET",
                                   message: "CallKit reset before the SIP INVITE could start", details: nil))
        }
        pendingOutbound.removeAll()
        callUUIDs.removeAll()
    }

    public func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        let callId = callUUIDs.first(where: { $0.value == action.callUUID })?.key ?? ""
        if pendingPushes[callId] != nil {
            // Do not fulfill until an INVITE has been correlated and answered.
            pendingAnswerActions[callId] = action
            return
        }
        var error: NSError?
        guard pjsip.answer(callId, error: &error) else { action.fail(); emitEvent(["type":"callState", "callId":callId, "state":"terminated", "reason":error?.localizedDescription ?? "answer failed"]); return }
        action.fulfill()
    }

    public func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        let callId = callUUIDs.first(where: { $0.value == action.callUUID })?.key ?? ""
        if let pending = pendingAnswerActions.removeValue(forKey: callId) {
            pending.fail()
            pendingPushes.removeValue(forKey: callId)
            pendingPushOrder.removeAll { $0 == callId }
            callUUIDs.removeValue(forKey: callId)
            action.fulfill()
            return
        }
        var error: NSError?
        guard pjsip.hangup(callId, error: &error) else { action.fail(); return }
        callUUIDs.removeValue(forKey: callId)
        action.fulfill()
    }

    public func provider(_ provider: CXProvider, perform action: CXSetHeldCallAction) {
        let callId = callUUIDs.first(where: { $0.value == action.callUUID })?.key ?? ""
        var error: NSError?
        guard pjsip.setHold(action.isOnHold, callId: callId, error: &error) else { action.fail(); return }
        action.fulfill()
    }

    public func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        let callId = callUUIDs.first(where: { $0.value == action.callUUID })?.key ?? ""
        var error: NSError?
        guard pjsip.setMuted(action.isMuted, callId: callId, error: &error) else { action.fail(); return }
        action.fulfill()
    }

    public func provider(_ provider: CXProvider, perform action: CXPlayDTMFCallAction) {
        let callId = callUUIDs.first(where: { $0.value == action.callUUID })?.key ?? ""
        var error: NSError?
        guard pjsip.sendDTMF(action.digits, callId: callId, error: &error) else { action.fail(); return }
        action.fulfill()
    }

    public func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        let callId = callUUIDs.first(where: { $0.value == action.callUUID })?.key ?? ""
        guard let reservation = pendingOutbound.removeValue(forKey: callId) else {
            action.fail()
            emitEvent(["type":"callState", "callId":callId, "state":"terminated",
                       "reason":"Missing outbound reservation; restore the SIP account and retry"])
            return
        }
        var error: NSError?
        guard pjsip.makeCall(forAccount: reservation.accountId, target: reservation.target,
                             preferredCallId: callId, error: &error) else {
            action.fail()
            callUUIDs.removeValue(forKey: callId)
            emitEvent(["type":"callState", "callId":callId, "state":"terminated",
                       "reason":error?.localizedDescription ?? "PJSIP failed to send INVITE"])
            reservation.result(FlutterError(code: "PJSIP_ERROR",
                                            message: error?.localizedDescription ?? "PJSIP failed to send INVITE",
                                            details: nil))
            return
        }
        provider.reportOutgoingCall(with: action.callUUID, startedConnectingAt: nil)
        action.fulfill()
        reservation.result(callId)
    }

    public func provider(_ provider: CXProvider,
                         didActivate audioSession: AVAudioSession) {
        pjsip.setAudioActive(true)
    }

    public func provider(_ provider: CXProvider,
                         didDeactivate audioSession: AVAudioSession) { pjsip.setAudioActive(false) }
}

extension SipKitPlugin: SKPJSIPBridgeDelegate {
    public func pjsipBridgeDidEmitEvent(_ event: [String : Any]) {
        if event["type"] as? String == "incomingCall",
           let callId = event["callId"] as? String,
           let remote = event["remoteUri"] as? String {
            let account = event["accountId"] as? String ?? ""
            // Prefer matching the native Call-ID if supplied by the push
            // server; otherwise correlate its account and remote URI.
            if let pending = pendingPushes.removeValue(forKey: callId) {
                let pushKey = callId
                pendingPushTimeouts.removeValue(forKey: pushKey)?.cancel()
                pendingPushOrder.removeAll { $0 == pushKey }
                callUUIDs.removeValue(forKey: pushKey)
                callUUIDs[callId] = pending.uuid
                if let answer = pendingAnswerActions.removeValue(forKey: pushKey) {
                    var error: NSError?
                    if pjsip.answer(callId, error: &error) { answer.fulfill() }
                    else { answer.fail(); emitEvent(["type":"callState", "callId":callId, "state":"terminated", "reason":error?.localizedDescription ?? "answer failed"]) }
                }
                emitEvent(event)
                return
            }
            onIncomingCall(callId: callId, accountId: event["accountId"] as? String ?? "",
                           remoteUri: remote, displayName: event["displayName"] as? String ?? remote)
        } else {
            if event["type"] as? String == "callState",
               let callId = event["callId"] as? String, let uuid = callUUIDs[callId] {
                switch event["state"] as? String {
                case "established": callKitProvider.reportOutgoingCall(with: uuid, connectedAt: Date())
                case "terminated":
                    callKitProvider.reportCall(with: uuid, endedAt: Date(), reason: .remoteEnded)
                    callUUIDs.removeValue(forKey: callId)
                default: break
                }
            }
            emitEvent(event)
        }
    }
}

// ─── FlutterStreamHandler ─────────────────────────────────────────────────────
extension SipKitPlugin: FlutterStreamHandler {

    public func onListen(withArguments arguments: Any?,
                         eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self.eventSink = nil
        return nil
    }
}
