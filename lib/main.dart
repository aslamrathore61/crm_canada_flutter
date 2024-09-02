import 'dart:async';

import 'package:crm_flutter/bloc/gpsBloc/gps_bloc.dart';
import 'package:crm_flutter/bloc/gpsBloc/gps_event.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:hive_flutter/adapters.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'Component/UpdateMaintainance/ForceUpdateScreen.dart';
import 'Component/UpdateMaintainance/MaintenanceScreen.dart';
import 'Network/ApiProvider.dart';
import 'Pages/InAppWebView.dart';
import 'Pages/SplashScreen.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart' as path_provider;
import 'model/native_item.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'model/user_info.dart';
import 'package:flutter_branch_sdk/flutter_branch_sdk.dart';

late final String WEB_ARCHIVE_DIR;

FlutterLocalNotificationsPlugin? flutterLocalNotificationsPlugin;
AndroidNotificationChannel? channel;

Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // If you're going to use other Firebase services in the background, such as Firestore,
  // make sure you call `initializeApp` before using other Firebase services.

  print("HandlingBackgroundMessage: ${message.messageId}");
  Fluttertoast.showToast(
      msg: "${message.messageId} Notification",
      toastLength: Toast.LENGTH_SHORT,
      gravity: ToastGravity.CENTER,
      timeInSecForIosWeb: 1,
      backgroundColor: Colors.red,
      textColor: Colors.white,
      fontSize: 16.0
  );

}

Future<void> main() async {


  WidgetsFlutterBinding.ensureInitialized();

  // Initialize the Branch SDK
  FlutterBranchSdk.init();

/*  // Wait a moment for the initialization to complete
  await Future.delayed(Duration(milliseconds: 100));

 */



  // FlutterBranchSdk.validateSDKIntegration();

  // StreamSubscription<Map> streamSubscription = FlutterBranchSdk.listSession().listen((data) {
  //   if (data.containsKey("+clicked_branch_link") &&
  //       data["+clicked_branch_link"] == true) {
  //     //Link clicked. Add logic to get link data and route user to correct screen
  //     print('Custom string: ${data["custom_string"]}');
  //
  //   }
  // }, onError: (error) {
  //   PlatformException platformException = error as PlatformException;
  //   print(
  //       'InitSession error: ${platformException.code} - ${platformException.message}');
  // });



  WEB_ARCHIVE_DIR = (await getApplicationSupportDirectory()).path;

  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown
  ]);

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  FirebaseMessaging messaging = FirebaseMessaging.instance;

  await messaging.requestPermission(
    alert: true,
    announcement: false,
    badge: true,
    carPlay: false,
    criticalAlert: false,
    provisional: false,
    sound: true,
  );

  Future<void> initializeHive() async {
    await Hive.initFlutter();
    Hive.registerAdapter(NativeItemAdapter());
    Hive.registerAdapter(BottomAdapter());
    Hive.registerAdapter(UserInfoAdapter());
  }

  final fcmToken = await messaging.getToken();
  SharedPreferences prefs = await SharedPreferences.getInstance();
  print('fcmToakenValue ${fcmToken}');
  await prefs.setString('fcmToken', '$fcmToken');

  channel = const AndroidNotificationChannel(
      'flutter_notification', // id
      'flutter_notification_title', // title
      importance: Importance.high,
      enableLights: true,
      enableVibration: true,
      showBadge: true,
      playSound: true);


  flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  await messaging
      .setForegroundNotificationPresentationOptions(
    alert: true,
    badge: true,
    sound: true,
  );

  await initializeHive();

  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  print('justOne 1');
  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    themeMode: ThemeMode.light, // Always use light theme
    theme: ThemeData(fontFamily: 'Nunito',),
    home: RepositoryProvider(

      create: (context) => ApiProvider(),
      child: SplashScreen(),
    ),
    routes: {
      '/home': (context) {
        final Map<String, dynamic> args =
        ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;
        final UserInfo? userInfo = args['userInfo'];
        final NativeItem nativeItem = args['nativeItem'];
        return BlocProvider(
            create: (context) => GPSBloc()..add(CheckGPS()),
            child: WebViewTab(nativeItem: nativeItem, userInfo: userInfo));
      },
      '/forceUpdatePage': (context) {
        return ForceUpdateScreen();
      },
      '/maintenancePage': (context) {
        return MaintenanceScreen();
      },
    },

  ));
}
