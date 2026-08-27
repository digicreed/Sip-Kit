#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol SKPJSIPBridgeDelegate <NSObject>
- (void)pjsipBridgeDidEmitEvent:(NSDictionary<NSString *, id> *)event;
@end

/// Objective-C façade around PJSUA2.  Keeping C++ out of Swift also means the
/// plugin can be built by CocoaPods projects which do not ship PJSIP.
@interface SKPJSIPBridge : NSObject
@property(nonatomic, weak, nullable) id<SKPJSIPBridgeDelegate> delegate;
@property(nonatomic, readonly, getter=isAvailable) BOOL available;
- (BOOL)start:(NSError **)error;
- (BOOL)stop:(NSError **)error;
- (BOOL)registerAccount:(NSDictionary<NSString *, id> *)configuration error:(NSError **)error;
- (BOOL)unregisterAccount:(NSString *)accountId error:(NSError **)error;
- (BOOL)canReceiveAccount:(NSString *)accountId;
- (BOOL)hasReceivingAccounts;
- (BOOL)makeCallForAccount:(NSString *)accountId target:(NSString *)target
           preferredCallId:(NSString *)callId error:(NSError **)error;
- (BOOL)answer:(NSString *)callId error:(NSError **)error;
- (BOOL)hangup:(NSString *)callId error:(NSError **)error;
- (BOOL)setHold:(BOOL)hold callId:(NSString *)callId error:(NSError **)error;
- (BOOL)setMuted:(BOOL)muted callId:(NSString *)callId error:(NSError **)error;
- (BOOL)sendDTMF:(NSString *)digits callId:(NSString *)callId error:(NSError **)error;
- (BOOL)blindTransfer:(NSString *)callId target:(NSString *)target error:(NSError **)error;
- (BOOL)attendedTransfer:(NSString *)callId otherCall:(NSString *)otherCallId error:(NSError **)error;
- (void)setAudioActive:(BOOL)active;
@end

NS_ASSUME_NONNULL_END