#import "Notifications.h"

#import "NotificationEvents.h"
#import "NotificationUtil.h"
#import <React/RCTConvert.h>
#import <React/RCTUtils.h>

// For iOS 10 we need to implement UNUserNotificationCenterDelegate to receive display
// notifications via APNS
#if defined(__IPHONE_10_0) && __IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_10_0
@import UserNotifications;
@interface Notifications () <UNUserNotificationCenterDelegate>
#else
@interface Notifications ()
#endif
@end

@implementation Notifications {
    NSMutableDictionary<NSString *, void (^)(UIBackgroundFetchResult)> *fetchCompletionHandlers;
    NSMutableDictionary<NSString *, void(^)(void)> *completionHandlers;
}

static Notifications *theNotifications = nil;
// PRE-BRIDGE-EVENTS: Consider enabling this to allow events built up before the bridge is built to be sent to the JS side
// static NSMutableArray *pendingEvents = nil;
static NSDictionary *initialNotification = nil;
static bool jsReady = FALSE;
static NSString *const DEFAULT_ACTION = @"com.apple.UNNotificationDefaultActionIdentifier";
static NSString* initialToken = nil;
static NSMutableArray* pendingMessages = nil;

+ (nonnull instancetype)instance {
    return theNotifications;
}

+ (void)configure {
    // PRE-BRIDGE-EVENTS: Consider enabling this to allow events built up before the bridge is built to be sent to the JS side
    // pendingEvents = [[NSMutableArray alloc] init];
    theNotifications = [[Notifications alloc] init];
}

RCT_EXPORT_MODULE();

- (id)init {
    self = [super init];
    if (self != nil) {
        DLog(@"Setting up RNFirebaseNotifications instance");
        [self initialise];
    }
    return self;
}

- (void)initialise {
    // If we're on iOS 10 then we need to set this as a delegate for the UNUserNotificationCenter
    if (@available(iOS 10.0, *)) {
        [UNUserNotificationCenter currentNotificationCenter].delegate = self;
    }

    // Set static instance for use from AppDelegate
    theNotifications = self;
    completionHandlers = [[NSMutableDictionary alloc] init];
    fetchCompletionHandlers = [[NSMutableDictionary alloc] init];
}

// PRE-BRIDGE-EVENTS: Consider enabling this to allow events built up before the bridge is built to be sent to the JS side
// The bridge is initialised after the module is created
// When the bridge is set, check if we have any pending events to send, and send them
/* - (void)setValue:(nullable id)value forKey:(NSString *)key {
    [super setValue:value forKey:key];
    if ([key isEqualToString:@"bridge"] && value) {
        for (NSDictionary* event in pendingEvents) {
            [RNFirebaseUtil sendJSEvent:self name:event[@"name"] body:event[@"body"]];
        }
        [pendingEvents removeAllObjects];
    }
} */

// *******************************************************
// ** Start AppDelegate methods
// ** iOS 8/9 Only
// *******************************************************
- (void)didReceiveLocalNotification:(nonnull UILocalNotification *)localNotification {
    if ([self isIOS89]) {
        NSString *event;
        if (RCTSharedApplication().applicationState == UIApplicationStateBackground) {
            event = NOTIFICATIONS_NOTIFICATION_DISPLAYED;
        } else if (RCTSharedApplication().applicationState == UIApplicationStateInactive) {
            event = NOTIFICATIONS_NOTIFICATION_OPENED;
        } else {
            event = NOTIFICATIONS_NOTIFICATION_RECEIVED;
        }

        NSDictionary *notification = [self parseUILocalNotification:localNotification];
        if (event == NOTIFICATIONS_NOTIFICATION_OPENED) {
            notification = @{
                             @"action": DEFAULT_ACTION,
                             @"notification": notification
                             };
        }
        [self sendJSEvent:self name:event body:notification];
    }
}

RCT_EXPORT_METHOD(complete:(NSString*)handlerKey fetchResult:(UIBackgroundFetchResult)fetchResult) {
    if (handlerKey != nil) {
        void (^fetchCompletionHandler)(UIBackgroundFetchResult) = fetchCompletionHandlers[handlerKey];
        if (fetchCompletionHandler != nil) {
            fetchCompletionHandlers[handlerKey] = nil;
            fetchCompletionHandler(fetchResult);
        } else {
            void(^completionHandler)(void) = completionHandlers[handlerKey];
            if (completionHandler != nil) {
                completionHandlers[handlerKey] = nil;
                completionHandler();
            }
        }
    }
}

// Listen for background messages
- (void)didReceiveRemoteNotification:(NSDictionary *)userInfo
              fetchCompletionHandler:(void (^)(UIBackgroundFetchResult))completionHandler {
    // FCM Data messages come through here if they specify content-available=true
    // Pass them over to the RNFirebaseMessaging handler instead
    if (userInfo[@"aps"] && ((NSDictionary*)userInfo[@"aps"]).count == 1 && userInfo[@"aps"][@"content-available"]) {
        // [[RNFirebaseMessaging instance] didReceiveRemoteNotification:userInfo];
        completionHandler(UIBackgroundFetchResultNoData);
        return;
    }

    NSDictionary *notification = [self parseUserInfo:userInfo];
    NSString *handlerKey = notification[@"notificationId"];

    NSString *event;
    if (RCTSharedApplication().applicationState == UIApplicationStateBackground) {
        event = NOTIFICATIONS_NOTIFICATION_DISPLAYED;
    } else if ([self isIOS89]) {
        if (RCTSharedApplication().applicationState == UIApplicationStateInactive) {
            event = NOTIFICATIONS_NOTIFICATION_OPENED;
        } else {
            event = NOTIFICATIONS_NOTIFICATION_RECEIVED;
        }
    } else {
        // On IOS 10:
        // - foreground notifications also go through willPresentNotification
        // - background notification presses also go through didReceiveNotificationResponse
        // This prevents duplicate messages from hitting the JS app
        completionHandler(UIBackgroundFetchResultNoData);
        return;
    }

    // For onOpened events, we set the default action name as iOS 8/9 has no concept of actions
    if (event == NOTIFICATIONS_NOTIFICATION_OPENED) {
        notification = @{
            @"action": DEFAULT_ACTION,
            @"notification": notification
        };
    }

    if (handlerKey != nil) {
        fetchCompletionHandlers[handlerKey] = completionHandler;
    } else {
        completionHandler(UIBackgroundFetchResultNoData);
    }

    [self sendJSEvent:self name:event body:notification];
}

// Listen for permission response
- (void) didRegisterUserNotificationSettings:(UIUserNotificationSettings *)notificationSettings {
    if (notificationSettings.types == UIUserNotificationTypeNone) {
        if (_permissionRejecter) {
            _permissionRejecter(@"messaging/permission_error", @"Failed to grant permission", nil);
        }
    } else if (_permissionResolver) {
        _permissionResolver(nil);
    }
    _permissionRejecter = nil;
    _permissionResolver = nil;
}

// Listen for FCM data messages that arrive as a remote notification
- (void)didReceiveRemoteNotification:(nonnull NSDictionary *)userInfo {
    NSDictionary *message = [self parseUserInfo:userInfo];
    [self sendJSEvent:self name:MESSAGING_MESSAGE_RECEIVED body:message];
}

- (void)didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)apnsToken
{
    DLog(@"Received new APNS token: %@", apnsToken);
    if (apnsToken) {
        const char *data = [apnsToken bytes];
        NSMutableString *token = [NSMutableString string];
        for (NSInteger i = 0; i < apnsToken.length; i++) {
            [token appendFormat:@"%02.2hhX", data[i]];
        }
        [self sendJSEvent:self name:MESSAGING_TOKEN_REFRESHED body:token];
    } else {
        [self sendJSEvent:self name:MESSAGING_TOKEN_REFRESHED body:nil];
    }
}

- (void)didFailToRegisterForRemoteNotificationsWithError:(NSError *)error
{
    
}

// *******************************************************
// ** Finish AppDelegate methods
// *******************************************************

// *******************************************************
// ** Start UNUserNotificationCenterDelegate methods
// ** iOS 10+
// *******************************************************

#if defined(__IPHONE_10_0) && __IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_10_0
// Handle incoming notification messages while app is in the foreground.
- (void)userNotificationCenter:(UNUserNotificationCenter *)center
       willPresentNotification:(UNNotification *)notification
         withCompletionHandler:(void (^)(UNNotificationPresentationOptions))completionHandler NS_AVAILABLE_IOS(10_0) {
    UNNotificationTrigger *trigger = notification.request.trigger;
    BOOL isFcm = trigger && [notification.request.trigger class] == [UNPushNotificationTrigger class];
    BOOL isScheduled = trigger && [notification.request.trigger class] == [UNCalendarNotificationTrigger class];

    NSString *event;
    UNNotificationPresentationOptions options;
    NSDictionary *message = [self parseUNNotification:notification];

    if (isFcm || isScheduled) {
        // If app is in the background
        if (RCTSharedApplication().applicationState == UIApplicationStateBackground
            || RCTSharedApplication().applicationState == UIApplicationStateInactive) {
            // display the notification
            options = UNNotificationPresentationOptionAlert | UNNotificationPresentationOptionBadge | UNNotificationPresentationOptionSound;
            // notification_displayed
            event = NOTIFICATIONS_NOTIFICATION_DISPLAYED;
        } else {
            // don't show notification
            options = UNNotificationPresentationOptionNone;
            // notification_received
            event = NOTIFICATIONS_NOTIFICATION_RECEIVED;
        }
    } else {
        // Triggered by `notifications().displayNotification(notification)`
        // Display the notification
        options = UNNotificationPresentationOptionAlert | UNNotificationPresentationOptionBadge | UNNotificationPresentationOptionSound;
        // notification_displayed
        event = NOTIFICATIONS_NOTIFICATION_DISPLAYED;
    }

    [self sendJSEvent:self name:event body:message];
    completionHandler(options);
}

// Handle notification messages after display notification is tapped by the user.
- (void)userNotificationCenter:(UNUserNotificationCenter *)center
didReceiveNotificationResponse:(UNNotificationResponse *)response
#if defined(__IPHONE_11_0)
         withCompletionHandler:(void(^)(void))completionHandler NS_AVAILABLE_IOS(10_0) {
#else
         withCompletionHandler:(void(^)())completionHandler NS_AVAILABLE_IOS(10_0) {
#endif
     NSDictionary *message = [self parseUNNotificationResponse:response];
           
     NSString *handlerKey = message[@"notification"][@"notificationId"];

     [self sendJSEvent:self name:NOTIFICATIONS_NOTIFICATION_OPENED body:message];
     if (handlerKey != nil) {
         completionHandlers[handlerKey] = completionHandler;
     } else {
         completionHandler();
     }
}

//#endif

// *******************************************************
// ** Finish UNUserNotificationCenterDelegate methods
// *******************************************************

RCT_EXPORT_METHOD(cancelAllNotifications:(RCTPromiseResolveBlock)resolve
                                rejecter:(RCTPromiseRejectBlock)reject) {
    if ([self isIOS89]) {
        [RCTSharedApplication() cancelAllLocalNotifications];
    } else {
        if (@available(iOS 10.0, *)) {
            UNUserNotificationCenter *notificationCenter = [UNUserNotificationCenter currentNotificationCenter];
            if (notificationCenter != nil) {
                [[UNUserNotificationCenter currentNotificationCenter] removeAllPendingNotificationRequests];
            }
        }
    }
    resolve(nil);
}

RCT_EXPORT_METHOD(cancelNotification:(NSString*) notificationId
                            resolver:(RCTPromiseResolveBlock)resolve
                            rejecter:(RCTPromiseRejectBlock)reject) {
    if ([self isIOS89]) {
        for (UILocalNotification *notification in RCTSharedApplication().scheduledLocalNotifications) {
            NSDictionary *notificationInfo = notification.userInfo;
            if ([notificationId isEqualToString:notificationInfo[@"notificationId"]]) {
                [RCTSharedApplication() cancelLocalNotification:notification];
            }
        }
    } else {
        if (@available(iOS 10.0, *)) {
            UNUserNotificationCenter *notificationCenter = [UNUserNotificationCenter currentNotificationCenter];
            if (notificationCenter != nil) {
                [[UNUserNotificationCenter currentNotificationCenter] removePendingNotificationRequestsWithIdentifiers:@[notificationId]];
            }
        }
    }
    resolve(nil);
}

RCT_EXPORT_METHOD(displayNotification:(NSDictionary*) notification
                             resolver:(RCTPromiseResolveBlock)resolve
                             rejecter:(RCTPromiseRejectBlock)reject) {
    if ([self isIOS89]) {
        UILocalNotification* notif = [self buildUILocalNotification:notification withSchedule:false];
        [RCTSharedApplication() presentLocalNotificationNow:notif];
        resolve(nil);
    } else {
        if (@available(iOS 10.0, *)) {
            UNNotificationRequest* request = [self buildUNNotificationRequest:notification withSchedule:false];
            [[UNUserNotificationCenter currentNotificationCenter] addNotificationRequest:request withCompletionHandler:^(NSError * _Nullable error) {
                if (!error) {
                    resolve(nil);
                } else{
                    reject(@"notifications/display_notification_error", @"Failed to display notificaton", error);
                }
            }];
        }
    }
}

RCT_EXPORT_METHOD(getBadge: (RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject) {
    dispatch_async(dispatch_get_main_queue(), ^{
        resolve(@([RCTSharedApplication() applicationIconBadgeNumber]));
    });
}

RCT_EXPORT_METHOD(getInitialNotification:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject) {
    // Check if we've cached an initial notification as this will contain the accurate action
    if (initialNotification) {
        resolve(initialNotification);
    } else if (self.bridge.launchOptions[UIApplicationLaunchOptionsLocalNotificationKey]) {
        UILocalNotification *localNotification = self.bridge.launchOptions[UIApplicationLaunchOptionsLocalNotificationKey];
        resolve(@{
                  @"action": DEFAULT_ACTION,
                  @"notification": [self parseUILocalNotification:localNotification]
                  });
    } else if (self.bridge.launchOptions[UIApplicationLaunchOptionsRemoteNotificationKey]) {
        NSDictionary *remoteNotification = [self bridge].launchOptions[UIApplicationLaunchOptionsRemoteNotificationKey];
        resolve(@{
                  @"action": DEFAULT_ACTION,
                  @"notification": [self parseUserInfo:remoteNotification]
                  });
    } else {
        resolve(nil);
    }
}

RCT_EXPORT_METHOD(getScheduledNotifications:(RCTPromiseResolveBlock)resolve
                                   rejecter:(RCTPromiseRejectBlock)reject) {
    if ([self isIOS89]) {
        NSMutableArray* notifications = [[NSMutableArray alloc] init];
        for (UILocalNotification *notif in [RCTSharedApplication() scheduledLocalNotifications]){
            NSDictionary *notification = [self parseUILocalNotification:notif];
            [notifications addObject:notification];
        }
        resolve(notifications);
    } else {
        if (@available(iOS 10.0, *)) {
            [[UNUserNotificationCenter currentNotificationCenter] getPendingNotificationRequestsWithCompletionHandler:^(NSArray<UNNotificationRequest *> * _Nonnull requests) {
                NSMutableArray* notifications = [[NSMutableArray alloc] init];
                for (UNNotificationRequest *notif in requests){
                    NSDictionary *notification = [self parseUNNotificationRequest:notif];
                    [notifications addObject:notification];
                }
                resolve(notifications);
            }];
        }
    }
}

RCT_EXPORT_METHOD(removeAllDeliveredNotifications:(RCTPromiseResolveBlock)resolve
                                         rejecter:(RCTPromiseRejectBlock)reject) {
    if ([self isIOS89]) {
        // No such functionality on iOS 8/9
    } else {
        if (@available(iOS 10.0, *)) {
            UNUserNotificationCenter *notificationCenter = [UNUserNotificationCenter currentNotificationCenter];
            if (notificationCenter != nil) {
                [[UNUserNotificationCenter currentNotificationCenter] removeAllDeliveredNotifications];
            }
        }
    }
    resolve(nil);
}

RCT_EXPORT_METHOD(removeDeliveredNotification:(NSString*) notificationId
                                     resolver:(RCTPromiseResolveBlock)resolve
                                     rejecter:(RCTPromiseRejectBlock)reject) {
    if ([self isIOS89]) {
        // No such functionality on iOS 8/9
    } else {
        if (@available(iOS 10.0, *)) {
            UNUserNotificationCenter *notificationCenter = [UNUserNotificationCenter currentNotificationCenter];
            if (notificationCenter != nil) {
                [[UNUserNotificationCenter currentNotificationCenter] removeDeliveredNotificationsWithIdentifiers:@[notificationId]];
            }
        }
    }
    resolve(nil);
}

RCT_EXPORT_METHOD(scheduleNotification:(NSDictionary*) notification
                              resolver:(RCTPromiseResolveBlock)resolve
                              rejecter:(RCTPromiseRejectBlock)reject) {
    if ([self isIOS89]) {
        UILocalNotification* notif = [self buildUILocalNotification:notification withSchedule:true];
        [RCTSharedApplication() scheduleLocalNotification:notif];
        resolve(nil);
    } else {
        if (@available(iOS 10.0, *)) {
            UNNotificationRequest* request = [self buildUNNotificationRequest:notification withSchedule:true];
            [[UNUserNotificationCenter currentNotificationCenter] addNotificationRequest:request withCompletionHandler:^(NSError * _Nullable error) {
                if (!error) {
                    resolve(nil);
                } else{
                    reject(@"notification/schedule_notification_error", @"Failed to schedule notificaton", error);
                }
            }];
        }
    }
}

RCT_EXPORT_METHOD(setBadge:(NSInteger) number
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [RCTSharedApplication() setApplicationIconBadgeNumber:number];
        resolve(nil);
    });
}

RCT_EXPORT_METHOD(jsInitialised:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject) {
    jsReady = TRUE;
    resolve(nil);
    
    if (initialToken) {
        [self sendJSEvent:self name:MESSAGING_TOKEN_REFRESHED body:initialToken];
    }
    if (pendingMessages) {
        for (id message in pendingMessages) {
            [NotificationUtil sendJSEvent:self name:MESSAGING_MESSAGE_RECEIVED body:message];
        }
        pendingMessages = nil;
    }
}
    
// ** Start React Module methods **
RCT_EXPORT_METHOD(getToken:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject) {
//    if (initialToken) {
//        resolve(initialToken);
//        initialToken = nil;
//    } else if ([[FIRMessaging messaging] FCMToken]) {
//        resolve([[FIRMessaging messaging] FCMToken]);
//    } else {
//        NSString * senderId = [[FIRApp defaultApp] options].GCMSenderID;
//        [[FIRMessaging messaging] retrieveFCMTokenForSenderID:senderId completion:^(NSString * _Nullable FCMToken, NSError * _Nullable error) {
//            if (error) {
//                reject(@"messaging/fcm-token-error", @"Failed to retrieve FCM token.", error);
//            } else if (FCMToken) {
//                resolve(FCMToken);
//            } else {
                resolve([NSNull null]);
//            }
//        }];
//    }
}

RCT_EXPORT_METHOD(deleteToken:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject) {
//    NSString * senderId = [[FIRApp defaultApp] options].GCMSenderID;
//    [[FIRMessaging messaging] deleteFCMTokenForSenderID:senderId completion:^(NSError * _Nullable error) {
//        if (error) {
//            reject(@"messaging/fcm-token-error", @"Failed to delete FCM token.", error);
//        } else {
            resolve([NSNull null]);
//        }
//    }];
}


RCT_EXPORT_METHOD(getAPNSToken:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject) {
//    NSData *apnsToken = [FIRMessaging messaging].APNSToken;
//    if (apnsToken) {
//        const char *data = [apnsToken bytes];
//        NSMutableString *token = [NSMutableString string];
//        for (NSInteger i = 0; i < apnsToken.length; i++) {
//            [token appendFormat:@"%02.2hhX", data[i]];
//        }
//        resolve([token copy]);
//    } else {
        resolve([NSNull null]);
//    }
}

RCT_EXPORT_METHOD(requestPermission:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject) {
    if (RCTRunningInAppExtension()) {
        reject(@"messaging/request-permission-unavailable", @"requestPermission is not supported in App Extensions", nil);
        return;
    }
    
    if (floor(NSFoundationVersionNumber) <= NSFoundationVersionNumber_iOS_9_x_Max) {
        UIUserNotificationType types = (UIUserNotificationTypeSound | UIUserNotificationTypeAlert | UIUserNotificationTypeBadge);
        dispatch_async(dispatch_get_main_queue(), ^{
            [RCTSharedApplication() registerUserNotificationSettings:[UIUserNotificationSettings settingsForTypes:types categories:nil]];
            // We set the promise for usage by the AppDelegate callback which listens
            // for the result of the permission request
            self.permissionRejecter = reject;
            self.permissionResolver = resolve;
        });
    } else {
        if (@available(iOS 10.0, *)) {
            // For iOS 10 display notification (sent via APNS)
            UNAuthorizationOptions authOptions = UNAuthorizationOptionAlert | UNAuthorizationOptionSound | UNAuthorizationOptionBadge;
            [[UNUserNotificationCenter currentNotificationCenter] requestAuthorizationWithOptions:authOptions completionHandler:^(BOOL granted, NSError * _Nullable error) {
                if (granted) {
                    resolve(nil);
                } else {
                    reject(@"messaging/permission_error", @"Failed to grant permission", error);
                }
            }];
        }
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [RCTSharedApplication() registerForRemoteNotifications];
    });
}

RCT_EXPORT_METHOD(registerForRemoteNotifications:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject) {
    [RCTSharedApplication() registerForRemoteNotifications];
    resolve(nil);
}

// Non Web SDK methods
RCT_EXPORT_METHOD(hasPermission:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject) {
    if (floor(NSFoundationVersionNumber) <= NSFoundationVersionNumber_iOS_9_x_Max) {
        dispatch_async(dispatch_get_main_queue(), ^{
            BOOL hasPermission = [RCTConvert BOOL:@([RCTSharedApplication() currentUserNotificationSettings].types != UIUserNotificationTypeNone)];
            resolve(@(hasPermission));
        });
    } else {
        if (@available(iOS 10.0, *)) {
            [[UNUserNotificationCenter currentNotificationCenter] getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings * _Nonnull settings) {
                BOOL hasPermission = [RCTConvert BOOL:@(settings.alertSetting == UNNotificationSettingEnabled)];
                resolve(@(hasPermission));
            }];
        }
    }
}


RCT_EXPORT_METHOD(sendMessage:(NSDictionary *) message
                  resolve:(RCTPromiseResolveBlock) resolve
                  reject:(RCTPromiseRejectBlock) reject) {
//    if (!message[@"to"]) {
//        reject(@"messaging/invalid-message", @"The supplied message is missing a 'to' field", nil);
//    }
//    NSString *to = message[@"to"];
//    NSString *messageId = message[@"messageId"];
//    NSNumber *ttl = message[@"ttl"];
//    NSDictionary *data = message[@"data"];
//
//    [[FIRMessaging messaging] sendMessage:data to:to withMessageID:messageId timeToLive:[ttl intValue]];
    
    // TODO: Listen for send success / errors
    resolve(nil);
}

RCT_EXPORT_METHOD(subscribeToTopic:(NSString*) topic
                  resolve:(RCTPromiseResolveBlock) resolve
                  reject:(RCTPromiseRejectBlock) reject) {
//    [[FIRMessaging messaging] subscribeToTopic:topic];
    resolve(nil);
}

RCT_EXPORT_METHOD(unsubscribeFromTopic: (NSString*) topic
                  resolve:(RCTPromiseResolveBlock) resolve
                  reject:(RCTPromiseRejectBlock) reject) {
//    [[FIRMessaging messaging] unsubscribeFromTopic:topic];
    resolve(nil);
}

// Because of the time delay between the app starting and the bridge being initialised
// we create a temporary instance of RNFirebaseNotifications.
// With this temporary instance, we cache any events to be sent as soon as the bridge is set on the module
- (void)sendJSEvent:(RCTEventEmitter *)emitter name:(NSString *)name body:(id)body {
    if (emitter.bridge && jsReady) {
        [NotificationUtil sendJSEvent:emitter name:name body:body];
    } else {
        if ([name isEqualToString:NOTIFICATIONS_NOTIFICATION_OPENED] && !initialNotification) {
            initialNotification = body;
        } else if ([name isEqualToString:NOTIFICATIONS_NOTIFICATION_OPENED]) {
            DLog(@"Multiple notification open events received before the JS Notifications module has been initialised");
        } if ([name isEqualToString:MESSAGING_TOKEN_REFRESHED]) {
            initialToken = body;
        } else if ([name isEqualToString:MESSAGING_MESSAGE_RECEIVED]) {
            if (!pendingMessages) {
                pendingMessages = [[NSMutableArray alloc] init];
            }
            [pendingMessages addObject:body];
        } else {
            DLog(@"Received unexpected message type");
        }
        // PRE-BRIDGE-EVENTS: Consider enabling this to allow events built up before the bridge is built to be sent to the JS side
        // [pendingEvents addObject:@{@"name":name, @"body":body}];
    }
}

- (BOOL)isIOS89 {
    return floor(NSFoundationVersionNumber) <= NSFoundationVersionNumber_iOS_9_x_Max;
}

- (UILocalNotification*) buildUILocalNotification:(NSDictionary *) notification
                                     withSchedule:(BOOL) withSchedule {
    UILocalNotification *localNotification = [[UILocalNotification alloc] init];
    if (notification[@"body"]) {
        localNotification.alertBody = notification[@"body"];
    }
    if (notification[@"data"]) {
        localNotification.userInfo = notification[@"data"];
    }
    if (notification[@"sound"]) {
        localNotification.soundName = notification[@"sound"];
    }
    if (notification[@"title"]) {
        localNotification.alertTitle = notification[@"title"];
    }
    if (notification[@"ios"]) {
        NSDictionary *ios = notification[@"ios"];
        if (ios[@"alertAction"]) {
            localNotification.alertAction = ios[@"alertAction"];
        }
        if (ios[@"badge"]) {
            NSNumber *badge = ios[@"badge"];
            localNotification.applicationIconBadgeNumber = badge.integerValue;
        }
        if (ios[@"category"]) {
            localNotification.category = ios[@"category"];
        }
        if (ios[@"hasAction"]) {
            localNotification.hasAction = ios[@"hasAction"];
        }
        if (ios[@"launchImage"]) {
            localNotification.alertLaunchImage = ios[@"launchImage"];
        }
    }
    if (withSchedule) {
        NSDictionary *schedule = notification[@"schedule"];
        NSNumber *fireDateNumber = schedule[@"fireDate"];
        NSDate *fireDate = [NSDate dateWithTimeIntervalSince1970:([fireDateNumber doubleValue] / 1000.0)];
        localNotification.fireDate = fireDate;

        NSString *interval = schedule[@"repeatInterval"];
        if (interval) {
            if ([interval isEqualToString:@"minute"]) {
                localNotification.repeatInterval = NSCalendarUnitMinute;
            } else if ([interval isEqualToString:@"hour"]) {
                localNotification.repeatInterval = NSCalendarUnitHour;
            } else if ([interval isEqualToString:@"day"]) {
                localNotification.repeatInterval = NSCalendarUnitDay;
            } else if ([interval isEqualToString:@"week"]) {
                localNotification.repeatInterval = NSCalendarUnitWeekday;
            }
        }

    }

    return localNotification;
}

- (UNNotificationRequest*) buildUNNotificationRequest:(NSDictionary *) notification
                                         withSchedule:(BOOL) withSchedule NS_AVAILABLE_IOS(10_0) {
    UNMutableNotificationContent *content = [[UNMutableNotificationContent alloc] init];
    if (notification[@"body"]) {
        content.body = notification[@"body"];
    }
    if (notification[@"data"]) {
        content.userInfo = notification[@"data"];
    }
    if (notification[@"sound"]) {
        if ([@"default" isEqualToString:notification[@"sound"]]) {
            content.sound = [UNNotificationSound defaultSound];
        } else {
            content.sound = [UNNotificationSound soundNamed:notification[@"sound"]];
        }
    }
    if (notification[@"subtitle"]) {
        content.subtitle = notification[@"subtitle"];
    }
    if (notification[@"title"]) {
        content.title = notification[@"title"];
    }
    if (notification[@"ios"]) {
        NSDictionary *ios = notification[@"ios"];
        if (ios[@"attachments"]) {
            NSMutableArray *attachments = [[NSMutableArray alloc] init];
            for (NSDictionary *a in ios[@"attachments"]) {
                NSString *identifier = a[@"identifier"];
                NSURL *url = [NSURL fileURLWithPath:a[@"url"]];
                NSMutableDictionary *attachmentOptions = nil;

                if (a[@"options"]) {
                    NSDictionary *options = a[@"options"];
                    attachmentOptions = [[NSMutableDictionary alloc] init];

                    for (id key in options) {
                        if ([key isEqualToString:@"typeHint"]) {
                            attachmentOptions[UNNotificationAttachmentOptionsTypeHintKey] = options[key];
                        } else if ([key isEqualToString:@"thumbnailHidden"]) {
                            attachmentOptions[UNNotificationAttachmentOptionsThumbnailHiddenKey] = options[key];
                        } else if ([key isEqualToString:@"thumbnailClippingRect"]) {
                            attachmentOptions[UNNotificationAttachmentOptionsThumbnailClippingRectKey] = options[key];
                        } else if ([key isEqualToString:@"thumbnailTime"]) {
                            attachmentOptions[UNNotificationAttachmentOptionsThumbnailTimeKey] = options[key];
                        }
                    }
                }

                NSError *error;
                UNNotificationAttachment *attachment = [UNNotificationAttachment attachmentWithIdentifier:identifier URL:url options:attachmentOptions error:&error];
                if (attachment) {
                    [attachments addObject:attachment];
                } else {
                    DLog(@"Failed to create attachment: %@", error);
                }
            }
            content.attachments = attachments;
        }

        if (ios[@"badge"]) {
            content.badge = ios[@"badge"];
        }
        if (ios[@"category"]) {
            content.categoryIdentifier = ios[@"category"];
        }
        if (ios[@"launchImage"]) {
            content.launchImageName = ios[@"launchImage"];
        }
        if (ios[@"threadIdentifier"]) {
            content.threadIdentifier = ios[@"threadIdentifier"];
        }
    }

    if (withSchedule) {
        NSDictionary *schedule = notification[@"schedule"];
        NSNumber *fireDateNumber = schedule[@"fireDate"];
        NSString *interval = schedule[@"repeatInterval"];
        NSDate *fireDate = [NSDate dateWithTimeIntervalSince1970:([fireDateNumber doubleValue] / 1000.0)];

        NSCalendarUnit calendarUnit;
        if (interval) {
            if ([interval isEqualToString:@"minute"]) {
                calendarUnit = NSCalendarUnitSecond;
            } else if ([interval isEqualToString:@"hour"]) {
                calendarUnit = NSCalendarUnitMinute | NSCalendarUnitSecond;
            } else if ([interval isEqualToString:@"day"]) {
                calendarUnit = NSCalendarUnitHour | NSCalendarUnitMinute | NSCalendarUnitSecond;
            } else if ([interval isEqualToString:@"week"]) {
                calendarUnit = NSCalendarUnitWeekday | NSCalendarUnitHour | NSCalendarUnitMinute | NSCalendarUnitSecond;
            } else {
                calendarUnit = NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay | NSCalendarUnitHour | NSCalendarUnitMinute | NSCalendarUnitSecond;
            }
        } else {
            // Needs to match exactly to the second
            calendarUnit = NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay | NSCalendarUnitHour | NSCalendarUnitMinute | NSCalendarUnitSecond;
        }

        NSDateComponents *components = [[NSCalendar currentCalendar] components:calendarUnit fromDate:fireDate];
        UNCalendarNotificationTrigger *trigger = [UNCalendarNotificationTrigger triggerWithDateMatchingComponents:components repeats:interval];
        return [UNNotificationRequest requestWithIdentifier:notification[@"notificationId"] content:content trigger:trigger];
    } else {
        return [UNNotificationRequest requestWithIdentifier:notification[@"notificationId"] content:content trigger:nil];
    }
}

- (NSDictionary*) parseUILocalNotification:(UILocalNotification *) localNotification {
    NSMutableDictionary *notification = [[NSMutableDictionary alloc] init];

    if (localNotification.alertBody) {
        notification[@"body"] = localNotification.alertBody;
    }
    if (localNotification.userInfo) {
        notification[@"data"] = localNotification.userInfo;
    }
    if (localNotification.soundName) {
        notification[@"sound"] = localNotification.soundName;
    }
    if (localNotification.alertTitle) {
         notification[@"title"] = localNotification.alertTitle;
    }

    NSMutableDictionary *ios = [[NSMutableDictionary alloc] init];
    if (localNotification.alertAction) {
        ios[@"alertAction"] = localNotification.alertAction;
    }
    if (localNotification.applicationIconBadgeNumber) {
        ios[@"badge"] = @(localNotification.applicationIconBadgeNumber);
    }
    if (localNotification.category) {
        ios[@"category"] = localNotification.category;
    }
    if (localNotification.hasAction) {
        ios[@"hasAction"] = @(localNotification.hasAction);
    }
    if (localNotification.alertLaunchImage) {
        ios[@"launchImage"] = localNotification.alertLaunchImage;
    }
    notification[@"ios"] = ios;

    return notification;
}

- (NSDictionary*)parseUNNotificationResponse:(UNNotificationResponse *)response NS_AVAILABLE_IOS(10_0) {
     NSMutableDictionary *notificationResponse = [[NSMutableDictionary alloc] init];
     NSDictionary *notification = [self parseUNNotification:response.notification];
     notificationResponse[@"notification"] = notification;
     notificationResponse[@"action"] = response.actionIdentifier;
     if ([response isKindOfClass:[UNTextInputNotificationResponse class]]) {
         notificationResponse[@"results"] = @{@"resultKey": ((UNTextInputNotificationResponse *)response).userText};
     }

     return notificationResponse;
}

- (NSDictionary*)parseUNNotification:(UNNotification *)notification NS_AVAILABLE_IOS(10_0) {
    return [self parseUNNotificationRequest:notification.request];
}

- (NSDictionary*) parseUNNotificationRequest:(UNNotificationRequest *) notificationRequest NS_AVAILABLE_IOS(10_0) {
    NSMutableDictionary *notification = [[NSMutableDictionary alloc] init];

    notification[@"notificationId"] = notificationRequest.identifier;

    if (notificationRequest.content.body) {
        notification[@"body"] = notificationRequest.content.body;
    }
    if (notificationRequest.content.userInfo) {
        NSMutableDictionary *data = [[NSMutableDictionary alloc] init];
        for (id k in notificationRequest.content.userInfo) {
            if ([k isEqualToString:@"aps"]
                || [k isEqualToString:@"gcm.message_id"]) {
                // ignore as these are handled by the OS
            } else {
                data[k] = notificationRequest.content.userInfo[k];
            }
        }
        notification[@"data"] = data;
    }
    if (notificationRequest.content.sound) {
        notification[@"sound"] = notificationRequest.content.sound;
    }
    if (notificationRequest.content.subtitle) {
        notification[@"subtitle"] = notificationRequest.content.subtitle;
    }
    if (notificationRequest.content.title) {
        notification[@"title"] = notificationRequest.content.title;
    }

    NSMutableDictionary *ios = [[NSMutableDictionary alloc] init];

    if (notificationRequest.content.attachments) {
        NSMutableArray *attachments = [[NSMutableArray alloc] init];
        for (UNNotificationAttachment *a in notificationRequest.content.attachments) {
            NSMutableDictionary *attachment = [[NSMutableDictionary alloc] init];
            attachment[@"identifier"] = a.identifier;
            attachment[@"type"] = a.type;
            attachment[@"url"] = [a.URL absoluteString];
            [attachments addObject:attachment];
        }
        ios[@"attachments"] = attachments;
    }

    if (notificationRequest.content.badge) {
        ios[@"badge"] = notificationRequest.content.badge;
    }
    if (notificationRequest.content.categoryIdentifier) {
        ios[@"category"] = notificationRequest.content.categoryIdentifier;
    }
    if (notificationRequest.content.launchImageName) {
        ios[@"launchImage"] = notificationRequest.content.launchImageName;
    }
    if (notificationRequest.content.threadIdentifier) {
        ios[@"threadIdentifier"] = notificationRequest.content.threadIdentifier;
    }
    notification[@"ios"] = ios;

    return notification;
}

- (NSDictionary*)parseUserInfo:(NSDictionary *)userInfo {

    NSMutableDictionary *notification = [[NSMutableDictionary alloc] init];
    NSMutableDictionary *data = [[NSMutableDictionary alloc] init];
    NSMutableDictionary *ios = [[NSMutableDictionary alloc] init];

    for (id k1 in userInfo) {
        if ([k1 isEqualToString:@"aps"]) {
            NSDictionary *aps = userInfo[k1];
            for (id k2 in aps) {
                if ([k2 isEqualToString:@"alert"]) {
                    // alert can be a plain text string rather than a dictionary
                    if ([aps[k2] isKindOfClass:[NSDictionary class]]) {
                        NSDictionary *alert = aps[k2];
                        for (id k3 in alert) {
                            if ([k3 isEqualToString:@"body"]) {
                                notification[@"body"] = alert[k3];
                            } else if ([k3 isEqualToString:@"subtitle"]) {
                                notification[@"subtitle"] = alert[k3];
                            } else if ([k3 isEqualToString:@"title"]) {
                                notification[@"title"] = alert[k3];
                            } else if ([k3 isEqualToString:@"loc-args"]
                                       || [k3 isEqualToString:@"loc-key"]
                                       || [k3 isEqualToString:@"title-loc-args"]
                                       || [k3 isEqualToString:@"title-loc-key"]) {
                                // Ignore known keys
                            } else {
                                DLog(@"Unknown alert key: %@", k2);
                            }
                        }
                    } else {
                        notification[@"title"] = aps[k2];
                    }
                } else if ([k2 isEqualToString:@"badge"]) {
                    ios[@"badge"] = aps[k2];
                } else if ([k2 isEqualToString:@"category"]) {
                    ios[@"category"] = aps[k2];
                } else if ([k2 isEqualToString:@"sound"]) {
                    notification[@"sound"] = aps[k2];
                } else {
                    DLog(@"Unknown aps key: %@", k2);
                }
            }
        } else if ([k1 isEqualToString:@"gcm.message_id"]) {
            notification[@"notificationId"] = userInfo[k1];
        } else if ([k1 isEqualToString:@"gcm.n.e"]
                   || [k1 isEqualToString:@"gcm.notification.sound2"]
                   || [k1 isEqualToString:@"google.c.a.c_id"]
                   || [k1 isEqualToString:@"google.c.a.c_l"]
                   || [k1 isEqualToString:@"google.c.a.e"]
                   || [k1 isEqualToString:@"google.c.a.udt"]
                   || [k1 isEqualToString:@"google.c.a.ts"]) {
            // Ignore known keys
        } else {
            // Assume custom data
            data[k1] = userInfo[k1];
        }
    }

    notification[@"data"] = data;
    notification[@"ios"] = ios;

    return notification;
}

- (NSArray<NSString *> *)supportedEvents {
    return @[NOTIFICATIONS_NOTIFICATION_DISPLAYED, NOTIFICATIONS_NOTIFICATION_OPENED, NOTIFICATIONS_NOTIFICATION_RECEIVED, MESSAGING_MESSAGE_RECEIVED, MESSAGING_TOKEN_REFRESHED];
}

- (NSDictionary *) constantsToExport {
    return @{ @"backgroundFetchResultNoData" : @(UIBackgroundFetchResultNoData),
              @"backgroundFetchResultNewData" : @(UIBackgroundFetchResultNewData),
              @"backgroundFetchResultFailed" : @(UIBackgroundFetchResultFailed)};
}

+ (BOOL)requiresMainQueueSetup
{
    return YES;
}

@end

#else
@implementation RNFirebaseNotifications
@end
#endif
