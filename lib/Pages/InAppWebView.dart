import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crm_flutter/Config.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hive/hive.dart';
import 'package:image_picker/image_picker.dart';
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';
import 'package:intl/intl.dart';
import 'package:location/location.dart';
import 'package:lottie/lottie.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../Component/buttons/socal_button.dart';
import '../InAppWebViewUtil.dart';
import '../SharePrefFile.dart';
import '../Utils.dart';
import '../bloc/gpsBloc/gps_bloc.dart';
import '../bloc/gpsBloc/gps_state.dart';
import '../main.dart';
import '../model/native_item.dart';
import '../model/user_info.dart';
import 'package:permission_handler/permission_handler.dart' as ph;
import 'package:geolocator/geolocator.dart' as geolocator;

import 'NoInternetConnectionPage.dart';

final webViewTabStateKey = GlobalKey<_WebViewTabState>();

class WebViewTab extends StatefulWidget {

  final NativeItem nativeItem;
  late final UserInfo? userInfo;

  WebViewTab({required this.nativeItem, required this.userInfo});

  @override
  State<WebViewTab> createState() => _WebViewTabState();
}

class _WebViewTabState extends State<WebViewTab> with WidgetsBindingObserver {
  InAppWebViewController? _webViewController;
  FindInteractionController? _findInteractionController;
  bool _isWindowClosed = false;
  bool IsInternetConnected = true;
  AlertDialog? _gpsDialog;
  UserInfo? _userInfo;
  bool userDetailsAvaible = false;
  late String deepLinkingURL;

  final TextEditingController _httpAuthUsernameController =
  TextEditingController();
  final TextEditingController _httpAuthPasswordController =
  TextEditingController();



  Future<void> setupInteractedMessage() async {
    // To handle messages while your application is in the foreground, listen to the onMessage stream
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      RemoteNotification? notification = message.notification;
      AndroidNotification? android = message.notification?.android;

      if (notification != null && android != null && !kIsWeb) {
        String action = jsonEncode(message.data);
        print('action ${action}');

        flutterLocalNotificationsPlugin!.show(
            notification.hashCode,
            notification.title,
            notification.body,
            NotificationDetails(
              android: AndroidNotificationDetails(
                channel!.id,
                channel!.name,
                priority: Priority.high,
                importance: Importance.high,
                styleInformation: DefaultStyleInformation(true, true),
                largeIcon: DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
                channelShowBadge: true,
                autoCancel: true,
                icon: '@mipmap/ic_launcher',
              ),
            ),
            payload: action);
      }
      print('A new event was published!');
    });

    // Get any messages which caused the application to open from
    // a terminated state.
    RemoteMessage? initialMessage =
    await FirebaseMessaging.instance.getInitialMessage();

    // If the message also contains a data property with a "type" of "chat",
    // navigate to a chat screen
    if (initialMessage != null) {
      _handleMessage(initialMessage);
    }
    /*else {
      handleDeepLink(null);
    }*/

    // Also handle any interaction when the app is in the background via a
    // Stream listener
    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessage);

    final android = AndroidInitializationSettings('@mipmap/ic_launcher');
    final iOS = DarwinInitializationSettings();
    final initSettings = InitializationSettings(android: android, iOS: iOS);

    await flutterLocalNotificationsPlugin!.initialize(initSettings,
        onDidReceiveNotificationResponse: notificationTapForeGround,
        onDidReceiveBackgroundNotificationResponse: notificationTapForeGround);
  }

  void notificationTapForeGround(NotificationResponse notificationResponse) {
    final String? payloadString = notificationResponse.payload;
    if (payloadString != null) {
      final Map<String, dynamic> payloadMap = jsonDecode(payloadString);
      final String? url = payloadMap['url'];
      handleDeepLink(url);
    }
  }

  void _handleMessage(RemoteMessage message) {
    handleDeepLink(message.data['url']);
  }

  void handleDeepLink(String? redirectLink) {
    if (redirectLink != null && redirectLink.isNotEmpty) {
      Uri uri = Uri.parse(redirectLink);
      String segmentPath = uri.path + '?' + uri.query;
      deepLinkingURL = Config.HOME_URL + segmentPath;
    } else {
      deepLinkingURL = Config.HOME_URL;
    }

    _webViewController?.loadUrl(urlRequest: URLRequest(url: WebUri(deepLinkingURL)));
  }


  @override
  void initState() {
    print('thisOneGetCall');
    WidgetsBinding.instance.addObserver(this);
    super.initState();

    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.blueAccent, // Change this to the desired color
    ));

    _internetConnectionStatus();
    setupInteractedMessage();
    _findInteractionController = FindInteractionController();

    if (widget.userInfo != null) {
      userDetailsAvaible = true;
      _userInfo = widget.userInfo;
    }
  }


  void _internetConnectionStatus() {
    InternetConnection().onStatusChange.listen((InternetStatus status) {
      switch (status) {
        case InternetStatus.connected:
          setState(() {
            IsInternetConnected = true;
          });
          break;
        case InternetStatus.disconnected:
          setState(() {
            IsInternetConnected = false;
          });
          break;
      }
    });
  }


  @override
  void dispose() {
    _webViewController = null;

    _httpAuthUsernameController.dispose();
    _httpAuthPasswordController.dispose();

    WidgetsBinding.instance.removeObserver(this);

    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_webViewController != null && Util.isAndroid()) {
      if (state == AppLifecycleState.paused) {
        pauseAll();
      } else {
        resumeAll();
      }
    }
  }

  void pauseAll() {
    if (Util.isAndroid()) {
      _webViewController?.pause();
    }
    pauseTimers();
  }

  void resumeAll() {
    if (Util.isAndroid()) {
      _webViewController?.resume();
    }
    resumeTimers();
  }

  void pause() {
    if (Util.isAndroid()) {
      _webViewController?.pause();
    }
  }

  void resume() {
    if (Util.isAndroid()) {
      _webViewController?.resume();
    }
  }

  void pauseTimers() {
    _webViewController?.pauseTimers();
  }

  void resumeTimers() {
    _webViewController?.resumeTimers();
  }


  late double _statusBarHeight;
  bool canPop = false;
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {

    _statusBarHeight = MediaQuery.of(context).padding.top;


    return PopScope(
      canPop: canPop,
      onPopInvoked: (didPop) async {
        if (!didPop) {
          _exitApp(context, _webViewController!);
        }
      },
      child: Scaffold(
        body: Container(
          //  margin: EdgeInsets.only(top: _statusBarHeight),
          color: Colors.white,
          //child: _buildWebView(),
          child: IsInternetConnected == false ?
          Center(
            child: NoInternetConnectionPage(
              tryAgain: _checkInitialConnectivity,
            ),
          ) : Stack(
            children: [
              Container(
                color: Colors.white,
                margin: EdgeInsets.only(top: _statusBarHeight),
                child: BlocConsumer<GPSBloc, GPSState>(
                  listener: (context, state) {
                    print('gpsState : xy');
                    if (state is GPSStatusUpdated) {
                      print('gpsState 1: ${state.isGPSEnabled}');
                      print('gpsState 2: ${state.isPermissionGranted}');

                      if (!state.isGPSEnabled || !state.isPermissionGranted) {
                        _showGPSDialog(context);
                      } else {
                        _dismissGPSDialog(context);
                      }
                    }
                  },
                  builder: (context, state) {
                    return  _buildWebView();
                  },
                ),
              ),
              if (_isLoading) ...[
                ModalBarrier(
                  dismissible: false,
                  color: Colors.black.withOpacity(0.3),
                ),
                Center(
                    child: CircularProgressIndicator(
                      color: Color(0xFF0054a0),
                    )),
              ],
            ],
          ),


        ),
      ),
    );
  }

  InAppWebView _buildWebView() {

    if (Util.isAndroid()) {
      InAppWebViewController.setWebContentsDebuggingEnabled(true);
    }

    var initialSettings = InAppWebViewSettings();
    initialSettings.mixedContentMode = MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW;
    initialSettings.isInspectable = true;
    initialSettings.useOnDownloadStart = true;
    initialSettings.useOnLoadResource = true;
    initialSettings.builtInZoomControls = false;
    initialSettings.supportZoom = false;
    initialSettings.textZoom = 100;
    initialSettings.useShouldOverrideUrlLoading = true;
    initialSettings.javaScriptCanOpenWindowsAutomatically = true;
    initialSettings.userAgent =
    "Mozilla/5.0 (Linux; Android 9; LG-H870 Build/PKQ1.190522.001) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/83.0.4103.106 Mobile Safari/537.36";
    initialSettings.transparentBackground = true;

    initialSettings.safeBrowsingEnabled = true;
    initialSettings.disableDefaultErrorPage = true;
    //initialSettings.supportMultipleWindows = true;
    initialSettings.verticalScrollbarThumbColor =
    const Color.fromRGBO(0, 0, 0, 0.5);
    initialSettings.horizontalScrollbarThumbColor =
    const Color.fromRGBO(0, 0, 0, 0.5);

    initialSettings.allowsLinkPreview = false;
    //  initialSettings.isFraudulentWebsiteWarningEnabled = true;
    initialSettings.disableLongPressContextMenuOnLinks = true;
    //initialSettings.allowingReadAccessTo = WebUri('file://$WEB_ARCHIVE_DIR/');

    return InAppWebView(
      //  keepAlive: InAppWebViewKeepAlive(),
      initialUrlRequest: URLRequest(url: WebUri(Config.HOME_URL)),
      initialSettings: initialSettings,
      // windowId: widget.webViewModel.windowId,
      findInteractionController: _findInteractionController,
      onWebViewCreated: (controller) async {
        initialSettings.transparentBackground = false;
        await controller.setSettings(settings: initialSettings);
        _webViewController = controller;
        _webViewController?.setSettings(
            settings:InAppWebViewSettings(builtInZoomControls:false)
        );
        // _webViewController?.loadData(data: htmlContent, mimeType: 'text/html', encoding: 'utf-8');
        addJavaScriptHandlers(controller, context);
        if (Util.isAndroid()) {
          controller.startSafeBrowsing();
        }

      },
      onLoadStart: (controller, url) async {

        print('onLoadStart $url');
        // Intercept tel: URLs before they load in the WebView
        if (url != null && url.toString().startsWith('tel:')) {
          controller.stopLoading(); // Stop the WebView from trying to load the tel: URL
          _webViewController?.stopLoading();
          if (await canLaunchUrl(url)) {
            print('Launching dialer from onLoadStart');
            await launchUrl(url);
          } else {
            print('Cannot launch dialer from onLoadStart');
          }
        }



        print('onLoadStart $url');
      },

      onLoadStop: (controller, url) async {
        print('onLoadStop $url');
      },
      onProgressChanged: (controller, progress) {
        print('onProgressChanged $progress');
      },
      onUpdateVisitedHistory: (controller, url, androidIsReload) async {
      },
      onConsoleMessage: (controller, consoleMessage) {
        Color consoleTextColor = Colors.black;
        Color consoleBackgroundColor = Colors.transparent;
        IconData? consoleIconData;
        Color? consoleIconColor;
        if (consoleMessage.messageLevel == ConsoleMessageLevel.ERROR) {
          consoleTextColor = Colors.red;
          consoleIconData = Icons.report_problem;
          consoleIconColor = Colors.red;
        } else if (consoleMessage.messageLevel == ConsoleMessageLevel.TIP) {
          consoleTextColor = Colors.blue;
          consoleIconData = Icons.info;
          consoleIconColor = Colors.blueAccent;
        } else if (consoleMessage.messageLevel == ConsoleMessageLevel.WARNING) {
          consoleBackgroundColor = const Color.fromRGBO(255, 251, 227, 1);
          consoleIconData = Icons.report_problem;
          consoleIconColor = Colors.orangeAccent;
        }


      },
      onLoadResource: (controller, resource) {

      },

      shouldOverrideUrlLoading: (controller, navigationAction) async {
        var url = navigationAction.request.url;
        print('shouldOverrideUrl $url');

        if (url != null && url.toString().startsWith('https://wa.me')) {
          if (await canLaunchUrl(url)) {
            print('Launching WhatsApp');
            await launchUrl(url);
            return NavigationActionPolicy.CANCEL;
          }
        }

        print('urlname $url');


        if (url != null) {
          // Handle tel: URLs (Phone call links)
          if (url.toString().startsWith('tel:')) {
            if (await canLaunchUrl(url)) {
              print('Launching dialer');
              await launchUrl(url);
              return NavigationActionPolicy.CANCEL;
            } else {
              print('Cannot launch dialer');
              return NavigationActionPolicy.CANCEL;
            }
          }
        }


        if (url != null && !["http", "https", "file", "chrome", "data", "javascript", "about"].contains(url.scheme)) {
          if (await canLaunchUrl(url)) {
            print('thisOneGetCall 0');

            // Launch the App
            await launchUrl(
              url,
            );
            // and cancel the request
            print('thisOneGetCall 1');
            return NavigationActionPolicy.CANCEL;
          }
        }
        print('thisOneGetCall 2');
        return NavigationActionPolicy.ALLOW;
      },


      onDownloadStartRequest: (controller, url) async {
        String path = url.url.path;
        String fileName = path.substring(path.lastIndexOf('/') + 1);

        await FlutterDownloader.enqueue(
          url: url.toString(),
          fileName: fileName,
          savedDir: (await getTemporaryDirectory()).path,
          showNotification: true,
          openFileFromNotification: true,
        );
      },
      onReceivedServerTrustAuthRequest: (controller, challenge) async {
        var sslError = challenge.protectionSpace.sslError;
        print('checkServerTrust $sslError');
        if (sslError != null && (sslError.code != null)) {
          if (Util.isIOS() && sslError.code == SslErrorType.UNSPECIFIED) {
            return ServerTrustAuthResponse(
                action: ServerTrustAuthResponseAction.PROCEED);
          }

          return ServerTrustAuthResponse(
              action: ServerTrustAuthResponseAction.CANCEL);
        }
        return ServerTrustAuthResponse(
            action: ServerTrustAuthResponseAction.PROCEED);
      },
      onReceivedError: (controller, request, error) async {

        print("Received error: ${error.description}");
        var isForMainFrame = request.isForMainFrame ?? false;
        if (!isForMainFrame) {
          return;
        }

        // if (Util.isIOS() && error.type == WebResourceErrorType.CANCELLED) {
        //   // NSURLErrorDomain
        //   return;
        // }

        var errorUrl = request.url;
        print('errorURL $errorUrl');

  /*      _webViewController?.loadData(data: """
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, user-scalable=no, initial-scale=1.0, maximum-scale=1.0, minimum-scale=1.0">
    <meta http-equiv="X-UA-Compatible" content="ie=edge">
    <style>
    ${await InAppWebViewController.tRexRunnerCss}
    </style>
    <style>
    .interstitial-wrapper {
        box-sizing: border-box;
        font-size: 1em;
        line-height: 1.6em;
        margin: 0 auto 0;
        max-width: 600px;
        width: 100%;
    }
    </style>
</head>
<body>
    ${await InAppWebViewController.tRexRunnerHtml}
    <div class="interstitial-wrapper">
      <h1>Website not available</h1>
      <p>Could not load web pages at <strong>$errorUrl</strong> because:</p>
      <p>${error.description}</p>
    </div>
</body>
    """, baseUrl: errorUrl, historyUrl: errorUrl);*/


      },
      onTitleChanged: (controller, title) async {
      },
      onCreateWindow: (controller, createWindowRequest) async {
      },
      onCloseWindow: (controller) {
        if (_isWindowClosed) {
          return;
        }
        _isWindowClosed = true;
      },
      onPermissionRequest: (controller, permissionRequest) async {
        return PermissionResponse(
            resources: permissionRequest.resources,
            action: PermissionResponseAction.GRANT);
      },
      onReceivedHttpAuthRequest: (controller, challenge) async {

      },
    );

  }



  void addJavaScriptHandlers(InAppWebViewController controller, BuildContext context) {

    //  String response = "";

    controller.addJavaScriptHandler(handlerName: 'fromWebToFlutter', callback: (args) async {
      final messageFromWeb = args[0];

      if (messageFromWeb == "agentClockOut" || messageFromWeb == "agentClockIn" || messageFromWeb == "TrackCall" || messageFromWeb == "getActivityCoordinate") {
        return await setLatLongToWeb(context);
      }else if (messageFromWeb == "CaptureSiteImage") {
        final responseValue = await showOptions(context);
        Map<String, dynamic> response = jsonDecode(responseValue);
        return response;
      }else if (messageFromWeb == "GenerateFCMToken") {
        return await Util.sentDeviceInfoToWeb();
        //_hideSystemUI();
      }else if (messageFromWeb == "showMap") {
        //_hideSystemUI();
      } else if (messageFromWeb == "closeMap") {
        //  _showSystemUI();
      }else {
        final decode = jsonDecode(messageFromWeb);
        _handleJsonMessageUserInfo(decode);
      }

      // Convert the JSON string to a JSON object

      // print('responseFlutter $response');
      // return response;

    });
  }



  Future<void> _handleJsonMessageUserInfo(Map<String, dynamic> data) async {
    try {
      /*if (data['action'] == 'Share') {
        print('actionshare ${data['action']}');
        shareURL(data['text'], data['url']);
        //title
      } else */if (data['type'] == 'login') {
        String barearToken = data['token'];
        await setPrefStringValue(Config.BarearToken, barearToken);
      } else {
        final UserInfo userInfo = UserInfo.fromJson(data);
        var box = await Hive.openBox<UserInfo>(Config.USER_INFO_BOX);
        await box.put(Config.USER_INFO_KEY, userInfo);
        setState(() {
          _userInfo = userInfo;
          userDetailsAvaible = true;
        });
      }
    } catch (e) {
      print('Error saving user info: $e');
    }
  }




//Show options to get image from camera or gallery
  Future<String> showOptions(BuildContext context) async {

    String response = "";
    AndroidDeviceInfo? deviceInfo;

    if (Platform.isAndroid) {
      deviceInfo = await DeviceInfoPlugin().androidInfo;
    }

    if (Platform.isAndroid && deviceInfo != null && deviceInfo.version.sdkInt <= 32) {
      var permissionStatus = await Permission.camera.request();

      if (permissionStatus.isGranted) {
        // get image from camera
        response = await getImageFromCamera();
      } else if (permissionStatus.isPermanentlyDenied) {
        showPermissionSettingsDialog(context,
            'Please enable storage permission in app settings to use this feature.');
      }
    } else {
      final permissionStatus = await Permission.camera.status;
      if (permissionStatus.isPermanentlyDenied) {
        showPermissionSettingsDialog(context,
            'Please enable storage permission in app settings to use this feature.');
      } else {
        response = await getImageFromCamera();
      }
    }

    return response;

  }

  final picker = ImagePicker();

  Future<String> getImageFromCamera() async {
    String response = "";
    await picker.pickImage(source: ImageSource.camera, imageQuality: 25)
        .then((value) async => {
      if (value != null) {
        response = await cropImageCall(File(value.path))
      }
    });

    return response;
  }


  Future<String> cropImageCall(File imgFile) async {
    String? croppedImagePath = await cropImage(imgFile);
    print("croppedImagePath $croppedImagePath");
    File file = File('$croppedImagePath');

    return await uploadImage(file);
  }

  Future<String> uploadImage(File imageFile) async {
    setState(() {
      _isLoading = true;
    });

    String barearToken = await getPrefStringValue(Config.BarearToken);
    final dio = Dio();
    const url = Config.IMAGE_UPLOAD;

    // Generate the current date and time in the desired format
    String formattedDate =
    DateFormat('yyyy-MM-dd HHmmss').format(DateTime.now());
    String noSpacesStr = formattedDate.replaceAll(' ', '_');
    String name = 'properties_$noSpacesStr.png';

    FormData formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(imageFile.path, filename: name),
    });

    final response = await dio.post(url,
        data: formData,
        options: Options(
          headers: {
            'Authorization': 'Bearer $barearToken', // Replace with your token
            'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36',
            'Content-Type': 'application/json',
            'Accept': 'application/json, text/plain, */*',
            'Referer': 'https://sync.savemax.com/',
            'platform': 'web',
            'sec-ch-ua':
            '"Not/A)Brand";v="8", "Chromium";v="126", "Google Chrome";v="126"',
            'sec-ch-ua-mobile': '?0',
            'sec-ch-ua-platform': '"Windows"'
          },
        ));
    var responseData = jsonEncode(response.data);

    setState(() {
      _isLoading = false;
    });

    print("jsonResponse : $responseData");

    if (response.statusCode == 200) {
      return responseData;
    } else {
      return "";
    }

  }


  Future<void> _launchUrl(String _url) async {
    if (!await launchUrl(Uri.parse(_url))) {
      throw Exception('Could not launch $_url');
    }
  }

  void _showGPSDialog(BuildContext context) {
    if (_gpsDialog == null) {
      _gpsDialog = AlertDialog(
        title: Center(child: Text('Location Required')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Lottie.asset('assets/lottie/lotti_gps.json', width: 150, height: 150),
            SizedBox(height: 10),
            Center(
              child: Text(
                'Enable device location to use the CRM app.',
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
        actions: <Widget>[
          Container(
            margin: EdgeInsets.only(right: 16,left: 16,top: 10,bottom: 8), // Equivalent to @dimen/_16sdp
            child: SocalButton(
              color: Color(0xFF0054a0),
              icon: Icon(Icons.location_off, color: Colors.white, size: 16),
              press: () async {
                Location location = Location();
                bool serviceEnabled = await location.serviceEnabled();
                if (!serviceEnabled) {
                  serviceEnabled = await location.requestService();
                  if (!serviceEnabled) {
                    return;
                  }
                }

                LocationPermission permission = await Geolocator.checkPermission();
                if (permission == LocationPermission.denied) {
                  permission = await Geolocator.requestPermission();

                  if (permission == LocationPermission.deniedForever) {
                    ph.openAppSettings();
                    return;
                  } else if (permission != LocationPermission.whileInUse &&
                      permission != LocationPermission.always) {
                    return;
                  }
                }
              },
              text: "Enable Location",
            ),
          ),
        ],
      );

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) => _gpsDialog!,
      );
    }
  }


  void _dismissGPSDialog(BuildContext context) {
    if (_gpsDialog != null) {
      Navigator.of(context, rootNavigator: true).pop();
      _gpsDialog = null;
    }
  }

  Future<void> _checkInitialConnectivity() async {
    IsInternetConnected = await InternetConnection().hasInternetAccess;

    if (IsInternetConnected) {
      _webViewController?.reload();
    }

    setState(() {
      IsInternetConnected;
    });

  }

  Future<void> _exitApp(BuildContext context, InAppWebViewController inAppWebViewController) async {
    if (await inAppWebViewController.canGoBack()) {
      print('WxistApp 1');
      inAppWebViewController.goBack();
      setState(() {
        canPop = false;
      });
    } else {
      inAppWebViewController.getUrl().then((currentUrl) {
        print('CurrentURL: $currentUrl');
        if (currentUrl == Config.HOME_URL + "leads") {
          setState(() {
            SystemNavigator.pop();
            //canPop = true;
          });
        }
      });
    }
  }

}





void showPermissionSettingsDialog(BuildContext context, String msg) {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Permission Required'),
      content: Text('$msg'),
      actions: [
        TextButton(
          onPressed: () async {
            Navigator.pop(context);
            await ph.openAppSettings();
          },
          child: Text('Open Settings'),
        ),
      ],
    ),
  );
}


// send coordinate to web
Future<String> setLatLongToWeb(BuildContext context) async {

  Location location = Location();
  bool serviceEnabled = await location.serviceEnabled();
  if (!serviceEnabled) {
    serviceEnabled = await location.requestService();
    if (!serviceEnabled) {
      return 'Service not enabled';
    }
  }

  LocationPermission permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();

    if (permission == LocationPermission.deniedForever) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Location Permission Required'),
          content: const Text(
              'Please enable location permissions in your device settings to use this feature.'),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                // Open the app settings
                Navigator.pop(context);
                ph.openAppSettings();
              },
              child: Text('Settings'),
            ),
          ],
        ),
      );
      return 'Permission denied forever';
    } else if (permission != LocationPermission.whileInUse &&
        permission != LocationPermission.always) {
      return 'Permission denied';
    }
  }

  Position? position = await geolocator.Geolocator.getCurrentPosition(
      desiredAccuracy: geolocator.LocationAccuracy.high);

  String coordinate = "${position.latitude},${position.longitude}";

  return coordinate;
}




const String htmlContent = """
      <!DOCTYPE html>
      <html>
      <head>
        <title>My HTML Content</title>
      </head>
      <body>
        <h1>Hello, Flutter InAppWebView!</h1>
        <p>This is a sample HTML content.</p>
        <button onclick="sendMessageToFlutter()">Send Message to Flutter</button>
        <script>
          function sendMessageToFlutter() {
          if(window.flutter_inappwebview) {
            window.flutter_inappwebview.callHandler('fromWebToFlutter', 'CaptureSiteImage').then(function(response) {
              console.log('aslamrathore ',response)
            });
          }else {
          console.log('noFLutterfound')
          }
          
          }
        </script>
        <p id="response"></p>
      </body>
      </html>
    """;