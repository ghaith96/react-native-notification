#import "NotificationUtil.h"

@implementation NotificationUtil

static NSString *const DEFAULT_APP_DISPLAY_NAME = @"[DEFAULT]";
static NSString *const DEFAULT_APP_NAME = @"__FIRAPP_DEFAULT";

+ (NSString *)getISO8601String:(NSDate *)date {
  static NSDateFormatter *formatter = nil;

  if (!formatter) {
    formatter = [[NSDateFormatter alloc] init];
    [formatter setLocale:[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"]];
    formatter.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"UTC"];
    [formatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ss"];
  }

  NSString *iso8601String = [formatter stringFromDate:date];

  return [iso8601String stringByAppendingString:@"Z"];
}

+ (NSString *)getAppName:(NSString *)appDisplayName {
  if ([appDisplayName isEqualToString:DEFAULT_APP_DISPLAY_NAME]) {
    return DEFAULT_APP_NAME;
  }
  return appDisplayName;
}

+ (NSString *)getAppDisplayName:(NSString *)appName {
  if ([appName isEqualToString:DEFAULT_APP_NAME]) {
    return DEFAULT_APP_DISPLAY_NAME;
  }
  return appName;
}

+ (void)sendJSEvent:(RCTEventEmitter *)emitter name:(NSString *)name body:(id)body {
  @try {
    // TODO: Temporary fix for https://github.com/invertase/react-native-firebase/issues/233
    // until a better solution comes around
    if (emitter.bridge) {
      [emitter sendEventWithName:name body:body];
    }
  } @catch (NSException *error) {
    DLog(@"An error occurred in sendJSEvent: %@", [error debugDescription]);
  }
}

@end
