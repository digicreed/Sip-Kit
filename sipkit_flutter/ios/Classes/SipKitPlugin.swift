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
// Dependencies (add to Podfile):
//   pod 'pjsip', '~> 2.14'   # or use the prebuilt xcframework
//
// Required Info.plist keys:
//   NSMicrophoneUsageDescription
//   NSCameraUsageDescription       (video calls)
//   UIBackgroundModes: [ voip ]
//   com.apple.developer.networking.voip: YES   (entitlement)
// ---------------------------------------------------------------------------

public class SipKitPlugin: NSObject, FlutterPlugin {

    // ─── Flutter channels ──────────────────────────────────────────────────
    private var methodChannel: FlutterMethodChannel?
    private var eventChannel: FlutterEventChannel?
    private var eventSink: FlutterEventSink?

    // ─── CallKit ───────────────────────────────────────────────────────────
    private let callKitProvider: CXProvider
    private let callKitController = CXCallController()

    // ─── State ────────────────────────────────────────────────────────────
    /// Maps accountId → PJSUA2 account ID (int).  Full PJSUA2 integration
    /// requires the pjsip pod; replace stubs below with real PJSUA2 calls.
    private var accountIds: [String: Int] = [:]
    /// Maps SipKit callId → CXCall UUID (for CallKit correlation).
    private var callUUIDs: [String: UUID] = [:]
    /// Maps SipKit callId → answer block (deferred until CallKit reports answered).
    private var pendingAnswers: [String: () -> Void] = [:]

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
        config.supportsVideo = true
        config.supportedHandleTypes = [.phoneNumber, .generic]
        config.maximumCallGroups = 2
        config.maximumCallsPerCallGroup = 5
        callKitProvider = CXProvider(configuration: config)
        super.init()
        callKitProvider.setDelegate(self, queue: nil)
    }

    // ─── Method channel handler ────────────────────────────────────────────
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
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
        if method == "init" {
            // PJSUA2: Ep.instance().libCreate() + libInit + libStart
            // Register VoIP push socket via PKPushRegistry (APNs wakeup stub).
            setupVoipPushStub()
            result(nil)
        } else {
            // PJSUA2: Ep.instance().libDestroy()
            callKitProvider.invalidate()
            result(nil)
        }
    }

    // ─── Account management ────────────────────────────────────────────────
    private func registerAccount(args: [String: Any], result: FlutterResult) {
        guard let accountId = args["accountId"] as? String,
              let username  = args["username"]  as? String,
              let password  = args["password"]  as? String,
              let domain    = args["domain"]    as? String,
              let wsUrl     = args["wsUrl"]     as? String else {
            result(FlutterError(code: "INVALID_ARGS", message: "Missing account args", details: nil))
            return
        }

        // PJSUA2 stub — replace with:
        //   let cfg = AccountConfig()
        //   cfg.idUri = "sip:\(username)@\(domain)"
        //   cfg.regConfig.registrarUri = "sip:\(domain)"
        //   let acc = MyAccount(); try acc.create(cfg); accountIds[accountId] = acc.getId()

        let displayName = args["displayName"] as? String ?? username
        _ = wsUrl // used in PJSUA2 transport config

        accountIds[accountId] = Int.random(in: 1..<1000)
        emitEvent([
            "type": "accountStatus",
            "accountId": accountId,
            "status": "registered",
            "reason": "stub registration succeeded"
        ])
        result(nil)
    }

    private func unregister(args: [String: Any], result: FlutterResult) {
        guard let accountId = args["accountId"] as? String else {
            result(FlutterError(code: "INVALID_ARGS", message: "Missing accountId", details: nil))
            return
        }
        // PJSUA2 stub — acc.setRegistration(false)
        accountIds.removeValue(forKey: accountId)
        emitEvent(["type": "accountStatus", "accountId": accountId, "status": "unregistered"])
        result(nil)
    }

    // ─── Outbound calls ────────────────────────────────────────────────────
    private func makeCall(args: [String: Any], result: FlutterResult) {
        guard let accountId = args["accountId"] as? String,
              let target    = args["target"]    as? String else {
            result(FlutterError(code: "INVALID_ARGS", message: "Missing makeCall args", details: nil))
            return
        }
        let video = args["video"] as? Bool ?? false

        let callId = "call_\(UUID().uuidString.prefix(8))"
        let uuid   = UUID()
        callUUIDs[callId] = uuid

        let handle = CXHandle(type: .generic, value: target)
        let startAction = CXStartCallAction(call: uuid, handle: handle)
        startAction.isVideo = video

        let transaction = CXTransaction(action: startAction)
        callKitController.request(transaction) { [weak self] error in
            if let error = error {
                self?.emitEvent([
                    "type": "callState", "callId": callId,
                    "state": "terminated", "reason": error.localizedDescription
                ])
            } else {
                // PJSUA2 stub: acc.makeCall(dst: target); callUUIDs[callId] = ...
                self?.emitEvent(["type": "callState", "callId": callId, "state": "connecting"])
            }
        }
        result(callId)
    }

    // ─── Inbound call answer ───────────────────────────────────────────────
    private func answerCall(args: [String: Any], result: FlutterResult) {
        guard let callId = args["callId"] as? String,
              let uuid   = callUUIDs[callId] else {
            result(FlutterError(code: "INVALID_ARGS", message: "Unknown callId", details: nil))
            return
        }
        let video = args["video"] as? Bool ?? false
        _ = video

        let action = CXAnswerCallAction(call: uuid)
        let transaction = CXTransaction(action: action)
        callKitController.request(transaction) { _ in }
        result(nil)
    }

    private func hangupCall(args: [String: Any], result: FlutterResult) {
        guard let callId = args["callId"] as? String,
              let uuid   = callUUIDs[callId] else {
            result(FlutterError(code: "INVALID_ARGS", message: "Unknown callId", details: nil))
            return
        }
        let action = CXEndCallAction(call: uuid)
        let transaction = CXTransaction(action: action)
        callKitController.request(transaction) { [weak self] _ in
            self?.callUUIDs.removeValue(forKey: callId)
        }
        result(nil)
    }

    private func holdCall(args: [String: Any], muted: Bool, result: FlutterResult) {
        guard let callId = args["callId"] as? String,
              let uuid   = callUUIDs[callId] else {
            result(FlutterError(code: "INVALID_ARGS", message: "Unknown callId", details: nil))
            return
        }
        let action = CXSetHeldCallAction(call: uuid, onHold: muted)
        callKitController.request(CXTransaction(action: action)) { _ in }
        result(nil)
    }

    private func muteCall(args: [String: Any], result: FlutterResult) {
        guard let callId = args["callId"] as? String,
              let uuid   = callUUIDs[callId] else {
            result(FlutterError(code: "INVALID_ARGS", message: "Unknown callId", details: nil))
            return
        }
        let muted = args["muted"] as? Bool ?? false
        let action = CXSetMutedCallAction(call: uuid, muted: muted)
        callKitController.request(CXTransaction(action: action)) { _ in }
        result(nil)
    }

    private func sendDtmf(args: [String: Any], result: FlutterResult) {
        guard let callId = args["callId"] as? String,
              let digits = args["digits"] as? String,
              let uuid   = callUUIDs[callId] else {
            result(FlutterError(code: "INVALID_ARGS", message: "Unknown callId/digits", details: nil))
            return
        }
        let action = CXPlayDTMFCallAction(call: uuid, digits: digits, type: .singleTone)
        callKitController.request(CXTransaction(action: action)) { _ in }
        // PJSUA2 stub: call.dialDtmf(digits)
        result(nil)
    }

    private func blindTransfer(args: [String: Any], result: FlutterResult) {
        guard let callId    = args["callId"]    as? String,
              let targetUri = args["targetUri"] as? String else {
            result(FlutterError(code: "INVALID_ARGS", message: "Missing transfer args", details: nil))
            return
        }
        _ = callId; _ = targetUri
        // PJSUA2 stub: call.xfer(dst: targetUri, msgData: nil)
        result(nil)
    }

    private func attendedTransfer(args: [String: Any], result: FlutterResult) {
        guard let callId      = args["callId"]      as? String,
              let otherCallId = args["otherCallId"] as? String else {
            result(FlutterError(code: "INVALID_ARGS", message: "Missing attended transfer args", details: nil))
            return
        }
        _ = callId; _ = otherCallId
        // PJSUA2 stub: callA.xferReplaces(callB, msgData: nil)
        result(nil)
    }

    private func enableVideo(args: [String: Any], result: FlutterResult) {
        guard let callId  = args["callId"]  as? String,
              let enabled = args["enabled"] as? Bool else {
            result(FlutterError(code: "INVALID_ARGS", message: "Missing enableVideo args", details: nil))
            return
        }
        _ = callId; _ = enabled
        // PJSUA2 stub: call.vidSetStream(.PJSUA_VID_REQ_OP_ADD/REMOVE, ...)
        result(nil)
    }

    // ─── Simulated incoming call (called from PJSUA2 onIncomingCall) ───────
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

    // ─── VoIP push stub (PKPushRegistry) ──────────────────────────────────
    private func setupVoipPushStub() {
        // Full APNs push wakeup requires a server-side APNs integration — see ROADMAP.
        // Stub: register PKPushRegistry so the entitlement is available at runtime.
        // let registry = PKPushRegistry(queue: .main)
        // registry.delegate = self
        // registry.desiredPushTypes = [.voIP]
    }

    // ─── Event emission ───────────────────────────────────────────────────
    private func emitEvent(_ event: [String: Any]) {
        DispatchQueue.main.async { [weak self] in
            self?.eventSink?(event)
        }
    }
}

// ─── CXProviderDelegate ───────────────────────────────────────────────────────
extension SipKitPlugin: CXProviderDelegate {

    public func providerDidReset(_ provider: CXProvider) {
        callUUIDs.removeAll()
    }

    public func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        // PJSUA2 stub: call.answer(200)
        let callId = callUUIDs.first(where: { $0.value == action.callUUID })?.key ?? ""
        emitEvent(["type": "callState", "callId": callId, "state": "established"])
        action.fulfill()
    }

    public func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        let callId = callUUIDs.first(where: { $0.value == action.callUUID })?.key ?? ""
        // PJSUA2 stub: call.hangup()
        emitEvent(["type": "callState", "callId": callId, "state": "terminated"])
        action.fulfill()
    }

    public func provider(_ provider: CXProvider, perform action: CXSetHeldCallAction) {
        let callId = callUUIDs.first(where: { $0.value == action.callUUID })?.key ?? ""
        emitEvent([
            "type": "callState",
            "callId": callId,
            "state": action.isOnHold ? "held" : "established"
        ])
        action.fulfill()
    }

    public func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        action.fulfill()
    }

    public func provider(_ provider: CXProvider, perform action: CXPlayDTMFCallAction) {
        action.fulfill()
    }

    public func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        let callId = callUUIDs.first(where: { $0.value == action.callUUID })?.key ?? ""
        provider.reportOutgoingCall(with: action.callUUID, startedConnectingAt: nil)
        emitEvent(["type": "callState", "callId": callId, "state": "ringing"])
        action.fulfill()
    }

    public func provider(_ provider: CXProvider,
                         didActivate audioSession: AVAudioSession) {
        // PJSUA2 stub: AudDevManager.instance().setActiveDev(...)
    }

    public func provider(_ provider: CXProvider,
                         didDeactivate audioSession: AVAudioSession) {}
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

// ─── FlutterApplicationLifeCycleDelegate ─────────────────────────────────────
extension SipKitPlugin: FlutterApplicationLifeCycleDelegate {

    public func application(_ application: UIApplication,
                            didFinishLaunchingWithOptions launchOptions: [AnyHashable: Any]?) -> Bool {
        return true
    }
}
