#import "ATHLTHConnectIQBridge.h"

static NSString * const ATHLTHGarminScheme = @"athlth-connectiq";
static NSString * const ATHLTHGarminAppUUID = @"8FC5F765-AB34-4DE2-BDCA-2580F832729B";

@interface ATHLTHConnectIQBridge ()
@property (nonatomic, strong, nullable) IQDevice *device;
@property (nonatomic, strong, nullable) IQApp *app;
@property (nonatomic, readwrite) BOOL ready;
@property (nonatomic) BOOL initialized;
@property (nonatomic) BOOL selectionPending;
@property (nonatomic) NSUInteger generation;
@end

@implementation ATHLTHConnectIQBridge
- (NSUUID *)selectedDeviceID { return self.device.uuid; }

- (void)initializeSDK {
    NSAssert(NSThread.isMainThread, @"Main thread required");
    if (self.initialized) { return; }
    [[ConnectIQ sharedInstance] initializeWithUrlScheme:ATHLTHGarminScheme uiOverrideDelegate:nil];
    self.initialized = YES;
}

- (void)chooseDevice {
    NSAssert(NSThread.isMainThread, @"Main thread required");
    if (!self.initialized) { return; }
    self.selectionPending = YES;
    [[ConnectIQ sharedInstance] showConnectIQDeviceSelection];
}

- (NSArray<IQDevice *> *)devicesFromSelectionURL:(NSURL *)url {
    NSAssert(NSThread.isMainThread, @"Main thread required");
    if (!self.initialized || !self.selectionPending ||
        ![url.scheme.lowercaseString isEqualToString:ATHLTHGarminScheme]) { return @[]; }
    self.selectionPending = NO;
    NSArray *response = [[ConnectIQ sharedInstance] parseDeviceSelectionResponseFromURL:url];
    NSMutableArray<IQDevice *> *devices = [NSMutableArray array];
    for (id item in response) {
        if ([item isKindOfClass:IQDevice.class]) { [devices addObject:item]; }
    }
    return devices;
}

- (void)updateReadiness:(BOOL)value {
    if (_ready == value) { return; }
    _ready = value;
    if (self.onReadinessChanged) { self.onReadinessChanged(value); }
}

- (void)selectDevice:(IQDevice *)device {
    NSAssert(NSThread.isMainThread, @"Main thread required");
    if (!self.initialized) { return; }
    [self disconnect];
    self.device = device;
    NSUUID *identifier = [[NSUUID alloc] initWithUUIDString:ATHLTHGarminAppUUID];
    self.app = [IQApp appWithUUID:identifier storeUuid:identifier device:device];
    ConnectIQ *sdk = [ConnectIQ sharedInstance];
    [sdk registerForDeviceEvents:device delegate:self];
    [sdk registerForAppMessages:self.app delegate:self];
    // Wait for deviceCharacteristicsDiscovered and installed-app status.
}

- (void)disconnect {
    NSAssert(NSThread.isMainThread, @"Main thread required");
    self.generation += 1;
    self.selectionPending = NO;
    [self updateReadiness:NO];
    if (self.app) { [[ConnectIQ sharedInstance] unregisterForAppMessages:self.app delegate:self]; }
    if (self.device) { [[ConnectIQ sharedInstance] unregisterForDeviceEvents:self.device delegate:self]; }
    self.app = nil;
    self.device = nil;
}

- (void)deviceStatusChanged:(IQDevice *)device status:(IQDeviceStatus)status {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (![device.uuid isEqual:self.device.uuid]) { return; }
        if (status != IQDeviceStatus_Connected) {
            self.generation += 1;
            [self updateReadiness:NO];
        }
    });
}

- (void)deviceCharacteristicsDiscovered:(IQDevice *)device {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (![device.uuid isEqual:self.device.uuid] || !self.app) { return; }
        NSUInteger generation = self.generation;
        IQApp *app = self.app;
        [[ConnectIQ sharedInstance] getAppStatus:app completion:^(IQAppStatus *status) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (self.generation != generation || self.app != app) { return; }
                [self updateReadiness:status.isInstalled &&
                    [[ConnectIQ sharedInstance] getDeviceStatus:device] == IQDeviceStatus_Connected];
            });
        }];
    });
}

- (void)receivedMessage:(id)message fromApp:(IQApp *)app {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (![app.uuid isEqual:self.app.uuid] || ![app.device.uuid isEqual:self.device.uuid] ||
            ![message isKindOfClass:NSDictionary.class]) { return; }
        if (self.onEvent) { self.onEvent(message, app.device.uuid); }
    });
}

- (void)openWatchApp:(void (^)(BOOL))completion {
    NSAssert(NSThread.isMainThread, @"Main thread required");
    if (!self.ready || !self.app) { completion(NO); return; }
    NSUInteger generation = self.generation;
    [[ConnectIQ sharedInstance] openAppRequest:self.app completion:^(IQSendMessageResult result) {
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(self.generation == generation &&
                (result == IQSendMessageResult_Success || result == IQSendMessageResult_Failure_AppAlreadyRunning));
        });
    }];
}

- (void)send:(NSDictionary *)message completion:(void (^)(BOOL))completion {
    NSAssert(NSThread.isMainThread, @"Main thread required");
    if (!self.ready || !self.app) { completion(NO); return; }
    NSUInteger generation = self.generation;
    [[ConnectIQ sharedInstance] sendMessage:message toApp:self.app progress:^(uint32_t sent, uint32_t total) {}
        completion:^(IQSendMessageResult result) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(self.generation == generation && result == IQSendMessageResult_Success);
            });
        } isTransient:YES];
    // Delivery alone never establishes a live workout. Caller must handle
    // missing callbacks, ACK timeout, uncertain capture and reconciliation.
}
@end
