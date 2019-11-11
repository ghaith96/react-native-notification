package com.emanon.notifications;

import android.content.Intent;

import com.facebook.react.HeadlessJsTaskService;
import com.facebook.react.bridge.WritableMap;
import com.facebook.react.jstasks.HeadlessJsTaskConfig;

import javax.annotation.Nullable;

import static com.emanon.notifications.BackgroundNotificationActionReceiver.isBackgroundNotficationIntent;
import static com.emanon.notifications.BackgroundNotificationActionReceiver.toNotificationOpenMap;

public class BackgroundNotificationActionsService extends HeadlessJsTaskService {
  @Override
  protected @Nullable
  HeadlessJsTaskConfig getTaskConfig(Intent intent) {
    if (isBackgroundNotficationIntent(intent)) {
      WritableMap notificationOpenMap = toNotificationOpenMap(intent);

      return new HeadlessJsTaskConfig(
        "RNFirebaseBackgroundNotificationAction",
        notificationOpenMap,
        60000,
        true
      );
    }
    return null;
  }
}
