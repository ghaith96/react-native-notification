package com.emanon.notifications;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

/*
 * This is invoked by the Alarm Manager when it is time to display a scheduled notification.
 */
public class NotificationReceiver extends BroadcastReceiver {
  @Override
  public void onReceive(Context context, Intent intent) {
    new NotificationManager(context).displayScheduledNotification(intent.getExtras());
  }
}
