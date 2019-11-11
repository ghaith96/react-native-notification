#ifndef Notifications_h
#define Notifications_h
#import <Foundation/Foundation.h>

#import <React/RCTBridgeModule.h>
#import <React/RCTEventEmitter.h>


@interface Notifications : RCTEventEmitter<RCTBridgeModule>

@property _Nullable RCTPromiseRejectBlock permissionRejecter;
@property _Nullable RCTPromiseResolveBlock permissionResolver;


+ (void)configure;
+ (_Nonnull instancetype)instance;

#if !TARGET_OS_TV
- (void)didReceiveLocalNotification:(nonnull UILocalNotification *)notification;
- (void)didReceiveRemoteNotification:(nonnull NSDictionary *)userInfo fetchCompletionHandler:(void (^_Nonnull)(UIBackgroundFetchResult))completionHandler;
- (void)didReceiveRemoteNotification:(nonnull NSDictionary *)userInfo;
- (void)didRegisterUserNotificationSettings:(nonnull UIUserNotificationSettings *)notificationSettings;
- (void)didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken;
- (void)didFailToRegisterForRemoteNotificationsWithError:(NSError *)error;
#endif

@end

#endif

