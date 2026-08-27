#import "PJSIPBridge.h"
#import <AVFoundation/AVFoundation.h>
#include <pjsua2.hpp>
#include <map>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

using namespace pj;

static NSError *SKError(const std::string &message) {
  return [NSError errorWithDomain:@"SipKit.PJSIP" code:2 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithUTF8String:message.c_str()]}];
}

@class SKPJSIPBridge;
class SKAccount;
class SKCall;

@interface SKPJSIPBridge () {
 @public Endpoint *endpoint;
 std::map<std::string, std::shared_ptr<SKAccount> > accounts;
 std::map<std::string, std::shared_ptr<SKCall> > calls;
 std::map<std::string, TransportId> transports;
 std::mutex stateMutex;
 BOOL started;
 BOOL audioActive;
}
- (void)emit:(NSDictionary *)event;
- (void)incoming:(std::shared_ptr<SKCall>)call accountId:(const std::string &)accountId;
- (void)retireCall:(NSString *)callId;
- (void)registerCurrentThread;
@end

class SKCall : public Call, public std::enable_shared_from_this<SKCall> {
public:
  std::string key;
  std::string accountKey;
  std::shared_ptr<SKAccount> accountOwner;
  __weak SKPJSIPBridge *bridge;
  SKCall(Account &account, int id, const std::string &k, const std::string &a, SKPJSIPBridge *b)
    : Call(account, id), key(k), accountKey(a), bridge(b) {}
  void connectAudio() {
    CallInfo ci=getInfo();
    for (unsigned i=0; i<ci.media.size(); ++i) if (ci.media[i].type == PJMEDIA_TYPE_AUDIO &&
        (ci.media[i].status == PJSUA_CALL_MEDIA_ACTIVE || ci.media[i].status == PJSUA_CALL_MEDIA_REMOTE_HOLD)) {
      AudioMedia *audio=(AudioMedia *)getMedia(i);
      AudDevManager &dev=Endpoint::instance().audDevManager();
      audio->startTransmit(dev.getPlaybackDevMedia());
      dev.getCaptureDevMedia().startTransmit(*audio);
    }
  }
  void onCallState(OnCallStateParam &) override {
    std::shared_ptr<SKCall> keepAlive=shared_from_this();
    SKPJSIPBridge *b = bridge; if (!b) return;
    try {
      CallInfo info = getInfo();
      NSString *state = @"connecting";
      if (info.state == PJSIP_INV_STATE_CALLING) state = @"connecting";
      else if (info.state == PJSIP_INV_STATE_EARLY) state = @"ringing";
      else if (info.state == PJSIP_INV_STATE_CONFIRMED) state = @"established";
      else if (info.state == PJSIP_INV_STATE_DISCONNECTED) state = @"terminated";
      [b emit:@{@"type":@"callState", @"callId":[NSString stringWithUTF8String:key.c_str()], @"state":state,
                @"reason":[NSString stringWithUTF8String:info.lastReason.c_str()]}];
      if (info.state == PJSIP_INV_STATE_DISCONNECTED)
        [b retireCall:[NSString stringWithUTF8String:key.c_str()]];
    } catch (...) {}
  }
  void onCallMediaState(OnCallMediaStateParam &) override {
    std::shared_ptr<SKCall> keepAlive=shared_from_this();
    SKPJSIPBridge *b=bridge; if (!b) return;
    BOOL active;
    { std::lock_guard<std::mutex> lock(b->stateMutex); active=b->audioActive; }
    if (!active) return;
    try {
      connectAudio();
    } catch (...) {}
  }
};

class SKAccount : public Account, public std::enable_shared_from_this<SKAccount> {
public:
  std::string key;
  std::string domain, registrar;
  unsigned port;
  __weak SKPJSIPBridge *bridge;
  SKAccount(const std::string &k, SKPJSIPBridge *b): key(k), bridge(b) {}
  void onRegState(OnRegStateParam &) override {
    SKPJSIPBridge *b=bridge; if (!b) return;
    try { AccountInfo i=getInfo(); NSString *status = i.regStatus >= 300 ? @"failed" :
      (i.regIsActive ? @"registered" : @"unregistered");
      [b emit:@{@"type":@"accountStatus", @"accountId":[NSString stringWithUTF8String:key.c_str()],
      @"status": status, @"reason":[NSString stringWithUTF8String:i.regStatusText.c_str()]}]; } catch (...) {}
  }
  void onRegStarted(OnRegStartedParam &) override {
    SKPJSIPBridge *b=bridge; if (b) [b emit:@{@"type":@"accountStatus", @"accountId":[NSString stringWithUTF8String:key.c_str()], @"status":@"registering"}];
  }
  void onIncomingCall(OnIncomingCallParam &prm) override {
    SKPJSIPBridge *b=bridge; if (!b) return;
    std::string id = [[NSUUID UUID].UUIDString UTF8String];
    std::shared_ptr<SKCall> call=std::make_shared<SKCall>(*this, prm.callId, id, key, b);
    call->accountOwner=shared_from_this();
    try { CallInfo info=call->getInfo(); if (!info.callIdString.empty()) id=info.callIdString; } catch (...) {}
    call->key=id;
    { std::lock_guard<std::mutex> lock(b->stateMutex); b->calls[id]=call; } [b incoming:call accountId:key];
  }
};

@implementation SKPJSIPBridge
- (BOOL)isAvailable { return YES; }
- (void)emit:(NSDictionary *)event {
  id<SKPJSIPBridgeDelegate> d=self.delegate;
  if (d) dispatch_async(dispatch_get_main_queue(), ^{ [d pjsipBridgeDidEmitEvent:event]; });
}
- (void)retireCall:(NSString *)callId {
  // A Call must not destroy itself from its PJSUA callback stack.
  dispatch_async(dispatch_get_main_queue(), ^{ std::lock_guard<std::mutex> lock(self->stateMutex); self->calls.erase(callId.UTF8String); });
}
- (void)registerCurrentThread {
  if (started && !endpoint->libIsThreadRegistered())
    endpoint->libRegisterThread("SipKitExternal");
}
- (BOOL)start:(NSError **)error {
  if (started) {
    try { [self registerCurrentThread]; return YES; }
    catch (Error &e) { if(error)*error=SKError(e.info()); return NO; }
  }
  try {
    endpoint = new Endpoint(); endpoint->libCreate();
    // PJSUA owns its event loop; callbacks are marshalled to the main queue
    // before Swift/Flutter are touched.
    EpConfig cfg; cfg.uaConfig.threadCnt=1; cfg.uaConfig.mainThreadOnly=false;
    cfg.logConfig.level=3; cfg.medConfig.clockRate=48000;
    endpoint->libInit(cfg); endpoint->libStart(); audioActive=NO; started=YES; return YES;
  } catch (Error &e) { if(error)*error=SKError(e.info()); return NO; }
}
- (BOOL)stop:(NSError **)error {
  if (!started) return YES;
  try { [self registerCurrentThread]; { std::lock_guard<std::mutex> lock(stateMutex); calls.clear(); accounts.clear(); transports.clear(); } endpoint->libDestroy(); delete endpoint; endpoint=nullptr; started=NO; return YES; }
  catch (Error &e) { if(error)*error=SKError(e.info()); return NO; }
}
- (BOOL)registerAccount:(NSDictionary *)c error:(NSError **)error {
  if (!started && ![self start:error]) return NO;
  [self registerCurrentThread];
  NSString *aid=c[@"accountId"], *user=c[@"username"], *password=c[@"password"], *domain=c[@"domain"];
  if (!aid.length || !user.length || !password.length || !domain.length) { if(error)*error=SKError("INVALID_ARGS: missing account configuration"); return NO; }
  try {
    std::string key=aid.UTF8String;
    std::shared_ptr<SKAccount> old;
    {
      std::lock_guard<std::mutex> lock(stateMutex);
      auto found=accounts.find(key);
      if(found!=accounts.end()){
        for(const auto &entry:calls) if(entry.second->accountKey==key) {
          if(error)*error=SKError("ACTIVE_CALLS: cannot replace account");
          return NO;
        }
        old=found->second;
        accounts.erase(found);
      }
    }
    if(old) old->shutdown();
    std::shared_ptr<SKAccount> acc=std::make_shared<SKAccount>(key,self); AccountConfig cfg;
    NSString *display=c[@"displayName"] ?: user, *auth=c[@"authUsername"] ?: user, *registrar=c[@"registrar"] ?: domain;
    NSInteger port=[c[@"sipPort"] integerValue]; if (!port) port=5060;
    NSString *scheme=[c[@"transport"] lowercaseString] ?: @"udp";
    cfg.idUri=[NSString stringWithFormat:@"\"%@\" <sip:%@@%@>",display,user,domain].UTF8String;
    cfg.regConfig.registrarUri=[NSString stringWithFormat:@"sip:%@:%ld;transport=%@",registrar,(long)port,scheme].UTF8String;
    cfg.regConfig.timeoutSec=(unsigned)[c[@"registrationExpiry"] integerValue];
    cfg.natConfig.udpKaIntervalSec=(unsigned)[c[@"keepAliveInterval"] integerValue];
    cfg.sipConfig.authCreds.push_back(AuthCredInfo("digest","*",auth.UTF8String,0,password.UTF8String));
    if ([c[@"outboundProxy"] isKindOfClass:NSString.class] && [c[@"outboundProxy"] length]) cfg.sipConfig.proxies.push_back([c[@"outboundProxy"] UTF8String]);
    // Local ports are ephemeral. The configured port belongs to the remote
    // registrar, not to a potentially conflicting local listener.
    TransportConfig tc; tc.port=0;
    if (![scheme isEqual:@"udp"] && ![scheme isEqual:@"tcp"] && ![scheme isEqual:@"tls"]) {
      if (error) *error=SKError("INVALID_ARGS: transport must be udp, tcp, or tls");
      return NO;
    }
    std::string transportKey=scheme.UTF8String;
    if ([scheme isEqual:@"tls"]) {
      transportKey += [c[@"verifyTls"] boolValue] ? "|verify" : "|insecure";
      if ([c[@"tlsCaCertPath"] isKindOfClass:NSString.class])
        transportKey += "|" + std::string([c[@"tlsCaCertPath"] UTF8String]);
    }
    TransportId tid;
    BOOL hasTransport=NO;
    { std::lock_guard<std::mutex> lock(stateMutex); auto existing=transports.find(transportKey);
      if (existing != transports.end()) { tid=existing->second; hasTransport=YES; } }
    if (hasTransport) {}
    else {
      if ([scheme isEqual:@"tls"]) { tc.tlsConfig.verifyServer=[c[@"verifyTls"] boolValue]; if ([c[@"tlsCaCertPath"] length]) tc.tlsConfig.caListFile=[c[@"tlsCaCertPath"] UTF8String]; tid=endpoint->transportCreate(PJSIP_TRANSPORT_TLS,tc); }
      else if ([scheme isEqual:@"tcp"]) tid=endpoint->transportCreate(PJSIP_TRANSPORT_TCP,tc);
      else tid=endpoint->transportCreate(PJSIP_TRANSPORT_UDP,tc);
      { std::lock_guard<std::mutex> lock(stateMutex); transports[transportKey]=tid; }
    }
    cfg.sipConfig.transportId=tid;
    // PJSUA2 uses complete codec identifiers (e.g. opus/48000/2).  Dart
    // supplies friendly prefixes, so retain only requested codecs and rank
    // their matching identifiers in the requested order.
    if ([c[@"codecPreferences"] isKindOfClass:NSArray.class]) {
      CodecInfoVector2 codecs=endpoint->codecEnum2(); pj_uint8_t priority=255;
      for (NSString *wanted in c[@"codecPreferences"]) for (const CodecInfo &codec : codecs)
        if ([[NSString stringWithUTF8String:codec.codecId.c_str()] lowercaseString] hasPrefix:wanted.lowercaseString])
          endpoint->codecSetPriority(codec.codecId, priority--);
    }
    acc->domain=domain.UTF8String; acc->registrar=registrar.UTF8String; acc->port=(unsigned)port;
    acc->create(cfg); { std::lock_guard<std::mutex> lock(stateMutex); accounts[key]=acc; } return YES;
  } catch (Error &e) { if(error)*error=SKError(e.info()); return NO; }
}
- (std::shared_ptr<SKCall>)call:(NSString *)key error:(NSError **)error {
  std::lock_guard<std::mutex> lock(stateMutex);
  auto i=calls.find(key.UTF8String); if(i==calls.end()) { if(error)*error=SKError("UNKNOWN_CALL"); return {}; } return i->second;
}
- (BOOL)unregisterAccount:(NSString *)aid error:(NSError **)error {
  try {
    [self registerCurrentThread];
    std::shared_ptr<SKAccount> acc;
    {
      std::lock_guard<std::mutex> lock(stateMutex);
      auto accountIt=accounts.find(aid.UTF8String);
      if(accountIt==accounts.end()){if(error)*error=SKError("UNKNOWN_ACCOUNT");return NO;}
      for(const auto &entry:calls) if(entry.second->accountKey==aid.UTF8String) {
        if(error)*error=SKError("ACTIVE_CALLS: cannot unregister account");
        return NO;
      }
      acc=accountIt->second;
      accounts.erase(accountIt);
    }
    acc->setRegistration(false);
    acc->shutdown();
    return YES;
  } catch(Error&e){if(error)*error=SKError(e.info());return NO;}
}
- (BOOL)canReceiveAccount:(NSString *)aid { std::lock_guard<std::mutex> lock(stateMutex); return started && accounts.find(aid.UTF8String)!=accounts.end(); }
- (BOOL)hasReceivingAccounts { std::lock_guard<std::mutex> lock(stateMutex); return started && !accounts.empty(); }
- (BOOL)makeCallForAccount:(NSString *)aid target:(NSString *)target preferredCallId:(NSString *)preferred error:(NSError **)error { try { [self registerCurrentThread]; std::shared_ptr<SKAccount> acc; {std::lock_guard<std::mutex> lock(stateMutex);auto i=accounts.find(aid.UTF8String);if(i!=accounts.end())acc=i->second;} if(!acc){if(error)*error=SKError("UNKNOWN_ACCOUNT");return NO;} std::string destination=target.UTF8String; if(destination.rfind("sip:",0)!=0 && destination.rfind("sips:",0)!=0) destination="sip:"+destination+"@"+(acc->domain.empty()?acc->registrar:acc->domain)+":"+std::to_string(acc->port); std::string id=preferred.UTF8String; std::shared_ptr<SKCall> call=std::make_shared<SKCall>(*acc,PJSUA_INVALID_ID,id,aid.UTF8String,self); call->accountOwner=acc; {std::lock_guard<std::mutex> lock(stateMutex);calls[id]=call;} try {CallOpParam p(true);call->makeCall(destination,p);} catch(...){std::lock_guard<std::mutex> lock(stateMutex);calls.erase(id);throw;} return YES;}catch(Error&e){if(error)*error=SKError(e.info());return NO;} }
- (BOOL)answer:(NSString *)id error:(NSError **)error { [self registerCurrentThread]; auto c=[self call:id error:error]; if(!c)return NO; try { CallOpParam p; p.statusCode=PJSIP_SC_OK; c->answer(p);return YES;}catch(Error&e){if(error)*error=SKError(e.info());return NO;} }
- (BOOL)hangup:(NSString *)id error:(NSError **)error { [self registerCurrentThread]; auto c=[self call:id error:error]; if(!c)return NO; try { CallOpParam p; c->hangup(p);return YES;}catch(Error&e){if(error)*error=SKError(e.info());return NO;} }
- (BOOL)setHold:(BOOL)hold callId:(NSString *)id error:(NSError **)error { [self registerCurrentThread]; auto c=[self call:id error:error]; if(!c)return NO; try { CallOpParam p; if(hold)c->setHold(p);else {p.opt.audioCount=1;p.opt.flag=PJSUA_CALL_UNHOLD;c->reinvite(p);}return YES;}catch(Error&e){if(error)*error=SKError(e.info());return NO;} }
- (BOOL)setMuted:(BOOL)muted callId:(NSString *)id error:(NSError **)error { [self registerCurrentThread]; auto c=[self call:id error:error]; if(!c)return NO; try { CallInfo ci=c->getInfo(); AudDevManager &d=Endpoint::instance().audDevManager(); for(unsigned i=0;i<ci.media.size();++i)if(ci.media[i].type==PJMEDIA_TYPE_AUDIO){AudioMedia *a=(AudioMedia *)c->getMedia(i); if(muted)d.getCaptureDevMedia().stopTransmit(*a);else d.getCaptureDevMedia().startTransmit(*a);}return YES;}catch(Error&e){if(error)*error=SKError(e.info());return NO;} }
- (BOOL)sendDTMF:(NSString *)d callId:(NSString *)id error:(NSError **)error {[self registerCurrentThread];auto c=[self call:id error:error];if(!c)return NO;try{c->dialDtmf(d.UTF8String);return YES;}catch(Error&e){if(error)*error=SKError(e.info());return NO;}}
- (BOOL)blindTransfer:(NSString *)id target:(NSString *)target error:(NSError **)error {[self registerCurrentThread];auto c=[self call:id error:error];if(!c)return NO;try{CallOpParam p;c->xfer(target.UTF8String,p);return YES;}catch(Error&e){if(error)*error=SKError(e.info());return NO;}}
- (BOOL)attendedTransfer:(NSString *)id otherCall:(NSString *)other error:(NSError **)error {[self registerCurrentThread];auto c=[self call:id error:error],o=[self call:other error:error];if(!c||!o)return NO;try{CallOpParam p;c->xferReplaces(*o,p);return YES;}catch(Error&e){if(error)*error=SKError(e.info());return NO;}}
- (void)setAudioActive:(BOOL)active {
  if (!started) return;
  try {
    [self registerCurrentThread];
    { std::lock_guard<std::mutex> lock(stateMutex); audioActive=active; }
    AudDevManager &dev=Endpoint::instance().audDevManager();
    if (!active) { dev.setNoDev(); return; }
    dev.setCaptureDev(PJMEDIA_AUD_DEFAULT_CAPTURE_DEV);
    dev.setPlaybackDev(PJMEDIA_AUD_DEFAULT_PLAYBACK_DEV);
    dev.setSndDevMode(0);
    std::vector<std::shared_ptr<SKCall> > snapshot;
    { std::lock_guard<std::mutex> lock(stateMutex); for (auto &entry:calls) snapshot.push_back(entry.second); }
    for (auto &call:snapshot) try { call->connectAudio(); } catch (...) {}
  } catch (...) {}
}
- (void)incoming:(std::shared_ptr<SKCall>)call accountId:(const std::string &)accountId { CallInfo ci=call->getInfo(); [self emit:@{@"type":@"incomingCall",@"callId":[NSString stringWithUTF8String:call->key.c_str()],@"accountId":[NSString stringWithUTF8String:accountId.c_str()],@"remoteUri":[NSString stringWithUTF8String:ci.remoteUri.c_str()],@"displayName":[NSString stringWithUTF8String:ci.remoteContact.c_str()],@"hasVideo":@NO}]; }
@end