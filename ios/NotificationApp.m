#import "NotificationApp.h"
#import <React/RCTUtils.h>
#import "NotificationUtil.h"


@implementation NotificationApp

RCT_EXPORT_MODULE(NotificationApp)

- (id)init {
    self = [super init];
    if (self != nil) {
        DLog(@"Setting up Notification instance");
    }
    return self;
}

- (NSArray<NSString *> *)supportedEvents {
    return @[];
}

RCT_EXPORT_METHOD(sampleMethod:(NSString *)stringArgument numberParameter:(nonnull NSNumber *)numberArgument callback:(RCTResponseSenderBlock)callback)
{
    // TODO: Implement some actually useful functionality
	callback(@[[NSString stringWithFormat: @"numberArgument: %@ stringArgument: %@", numberArgument, stringArgument]]);
}

/**
 * Initialize a new firebase app instance or ignore if currently exists.
 * @return
 */
RCT_EXPORT_METHOD(initializeApp:
                  (NSString *) appDisplayName
                  options:
                  (NSDictionary *) options
                  callback:
                  (RCTResponseSenderBlock) callback) {
    
    RCTUnsafeExecuteOnMainQueueSync(^{
        callback(@[[NSNull null], @{@"result": @"success"}]);
    });
}

/**
 * Delete a firebase app
 * @return
 */
RCT_EXPORT_METHOD(deleteApp:
                  (NSString *) appDisplayName
                  resolver:
                  (RCTPromiseResolveBlock) resolve
                  rejecter:
                  (RCTPromiseRejectBlock) reject) {
    
    return resolve([NSNull null]);
}

- (NSDictionary *)constantsToExport {
    NSMutableDictionary *constants = [NSMutableDictionary new];
    
    NSMutableArray *appsArray = [NSMutableArray new];
    {
        NSMutableDictionary *appOptions = [NSMutableDictionary new];
        appOptions[@"name"] = @"[DEFAULT]";
        [appsArray addObject:appOptions];
    }
    
    constants[@"apps"] = appsArray;
    return constants;
}

+ (BOOL)requiresMainQueueSetup
{
    return YES;
}

@end
