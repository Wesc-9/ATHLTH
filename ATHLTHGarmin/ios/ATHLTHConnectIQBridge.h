#import <Foundation/Foundation.h>
#import <ConnectIQ/ConnectIQ.h>

NS_ASSUME_NONNULL_BEGIN
/// Optional native SDK adapter. Add to a private iOS target only after linking
/// the official ConnectIQ package. All public calls are main-thread only.
@interface ATHLTHConnectIQBridge : NSObject <IQDeviceEventDelegate, IQAppMessageDelegate>
@property (nonatomic, readonly, nullable) NSUUID *selectedDeviceID;
@property (nonatomic, readonly) BOOL ready;
@property (nonatomic, copy, nullable) void (^onReadinessChanged)(BOOL ready);
@property (nonatomic, copy, nullable) void (^onEvent)(NSDictionary *message, NSUUID *deviceID);

- (void)initializeSDK;
- (void)chooseDevice;
- (NSArray<IQDevice *> *)devicesFromSelectionURL:(NSURL *)url;
- (void)selectDevice:(IQDevice *)device;
- (void)disconnect;
- (void)openWatchApp:(void (^)(BOOL promptDelivered))completion;
- (void)send:(NSDictionary *)message completion:(void (^)(BOOL delivered))completion;
@end
NS_ASSUME_NONNULL_END
