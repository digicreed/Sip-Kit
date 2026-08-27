#import "PJSIPBridge.h"

static NSError *SKUnavailableError(void) {
  return [NSError errorWithDomain:@"SipKit.PJSIP" code:1 userInfo:@{
    NSLocalizedDescriptionKey: @"PJSIP_UNAVAILABLE: ios/Frameworks/PJSIP.xcframework is not installed"
  }];
}

@implementation SKPJSIPBridge
- (BOOL)isAvailable { return NO; }
- (BOOL)fail:(NSError **)error { if (error) *error = SKUnavailableError(); return NO; }
- (BOOL)start:(NSError **)error { return [self fail:error]; }
- (BOOL)stop:(NSError **)error { return YES; }
- (BOOL)registerAccount:(NSDictionary *)configuration error:(NSError **)error { return [self fail:error]; }
- (BOOL)unregisterAccount:(NSString *)accountId error:(NSError **)error { return [self fail:error]; }
- (BOOL)canReceiveAccount:(NSString *)accountId { return NO; }
- (BOOL)hasReceivingAccounts { return NO; }
- (BOOL)makeCallForAccount:(NSString *)accountId target:(NSString *)target preferredCallId:(NSString *)callId error:(NSError **)error { return [self fail:error]; }
- (BOOL)answer:(NSString *)callId error:(NSError **)error { return [self fail:error]; }
- (BOOL)hangup:(NSString *)callId error:(NSError **)error { return [self fail:error]; }
- (BOOL)setHold:(BOOL)hold callId:(NSString *)callId error:(NSError **)error { return [self fail:error]; }
- (BOOL)setMuted:(BOOL)muted callId:(NSString *)callId error:(NSError **)error { return [self fail:error]; }
- (BOOL)sendDTMF:(NSString *)digits callId:(NSString *)callId error:(NSError **)error { return [self fail:error]; }
- (BOOL)blindTransfer:(NSString *)callId target:(NSString *)target error:(NSError **)error { return [self fail:error]; }
- (BOOL)attendedTransfer:(NSString *)callId otherCall:(NSString *)otherCallId error:(NSError **)error { return [self fail:error]; }
- (void)setAudioActive:(BOOL)active {}
@end