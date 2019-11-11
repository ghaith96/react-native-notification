#ifndef NotificationEvents_h
#define NotificationEvents_h

#import <Foundation/Foundation.h>

static NSString *const AUTH_STATE_CHANGED_EVENT = @"auth_state_changed";
static NSString *const AUTH_ID_TOKEN_CHANGED_EVENT = @"auth_id_token_changed";
static NSString *const PHONE_AUTH_STATE_CHANGED_EVENT = @"phone_auth_state_changed";

// Messaging
static NSString *const MESSAGING_MESSAGE_RECEIVED = @"messaging_message_received";
static NSString *const MESSAGING_TOKEN_REFRESHED = @"messaging_token_refreshed";

// Notifications
static NSString *const NOTIFICATIONS_NOTIFICATION_DISPLAYED = @"notifications_notification_displayed";
static NSString *const NOTIFICATIONS_NOTIFICATION_OPENED = @"notifications_notification_opened";
static NSString *const NOTIFICATIONS_NOTIFICATION_RECEIVED = @"notifications_notification_received";

#endif
