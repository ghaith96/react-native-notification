# notification

## Getting started

`$ npm install @emanon_/react-native-notification --save`

or 

`$ yarn add @emanon_/react-native-notification`


### Automatic installation

please Use react-native 0.60+, it will be autolink.

#### iOS

1. `$ cd ios`
2. `$ pod install`
3. updte AppDelegate

```objectivec
#import "Notifications.h"  // <-- Add this line

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{

  // ……
  [Notifications configure];  // <-- Add this line
  return YES;
}

- (void)application:(UIApplication *)application didReceiveLocalNotification:(UILocalNotification *)notification
{
  [[Notifications instance] didReceiveLocalNotification:notification];
}
```


#### Android

Add the `NotificationsPackage` to your `android/app/src/main/java/com/[app name]/MainApplication.java:`

```java
import com.facebook.react.ReactApplication;
import com.emanon.notifications.NotificationsPackage;// <-- Add this line

public class MainApplication extends Application implements ReactApplication {

  // ...

    @Override
    protected List<ReactPackage> getPackages() {
      @SuppressWarnings("UnnecessaryLocalVariable")
      List<ReactPackage> packages = new PackageList(this).getPackages();
      // Packages that cannot be autolinked yet can be added manually here, for example:
      // packages.add(new MyReactNativePackage());
      packages.add(new NotificationsPackage());	// <-- Add this line
      return packages;
    }

	// ...

}
```

### Manual installation

Manual installation is not recommend, please Use react-native 0.60+.

## Usage

Most usage is like notifications in `react-native-firebase`

```javascript
import { NotificationApp } from '@emanon_/react-native-notification';

// check permission
NotificationApp
      .notifications()
      .hasPermission()
      .then(enabled => {
        if (enabled) {
          // user has permissions
        } else {
          // user doesn't have permission
        }
			});
			
// request permission
NotificationApp
	.notifications()
	.requestPermission()
	.then(() => {
		// User has authorised
	})
	.catch(error => {
		// User has rejected permissions
	});

// construct nofication
const notification = new NotificationApp.notifications.Notification()
      .setNotificationId('notificationId')
      .setTitle('My notification title')
      .setBody('My notification body')
      .setData({
        key1: 'value1',
        key2: 'value2',
      });
    notification
      .android.setChannelId('test-channel')
      .android.setSmallIcon('ic_launcher');

// display notifcation
NotificationApp.notifications().displayNotification(notification)
.then(() => {
  // Display Success
})
.catch(error => {
  // Display Failed
});

// schedule notificaton
const date = new Date();
date.setMinutes(date.getMinutes() + 1);

NotificationApp.notifications().scheduleNotification(notification, {
  fireDate: date.getTime(),
})
.then(() => {
  // Schedule Success
})
.catch(error => {
  // Schedule Failed
});


```

### TODO

- APNS
- Firebase Cloude Message & GCM Message
- CN Push