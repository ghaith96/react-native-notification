#ifndef RNFirebaseUtil_h
#define RNFirebaseUtil_h

#import <Foundation/Foundation.h>
#import <React/RCTEventEmitter.h>

#ifdef DEBUG
#define DLog(fmt, ...) NSLog((@"%s [Line %d] " fmt), __PRETTY_FUNCTION__, __LINE__, ##__VA_ARGS__);
#else
#define DLog(...)
#endif

@interface NotificationUtil : NSObject

+ (NSString *)getISO8601String:(NSDate *)date;
+ (NSString *)getAppName:(NSString *)appDisplayName;
+ (NSString *)getAppDisplayName:(NSString *)appName;
+ (void)sendJSEvent:(RCTEventEmitter *)emitter name:(NSString *)name body:(id)body;

@end

#endif
