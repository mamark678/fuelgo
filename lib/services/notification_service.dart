import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  bool _isInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized) return;

    // Initialize local notifications
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings initializationSettingsIOS =
        DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const InitializationSettings initializationSettings =
        InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
    );

    await _notifications.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    // Initialize Firebase Cloud Messaging
    await _initializeFirebaseMessaging();

    _isInitialized = true;
  }

  Future<void> _initializeFirebaseMessaging() async {
    // Request permission for notifications
    NotificationSettings settings = await _firebaseMessaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      print('User granted permission for notifications');
    } else if (settings.authorizationStatus == AuthorizationStatus.provisional) {
      print('User granted provisional permission for notifications');
    } else {
      print('User declined or has not accepted permission for notifications');
    }

    // Get FCM token
    String? token = await _firebaseMessaging.getToken();
    print('FCM Token: $token');

    // Listen to token refresh
    _firebaseMessaging.onTokenRefresh.listen((String token) {
      print('FCM Token refreshed: $token');
      _saveTokenToFirestore(token);
    });

    // Handle background messages
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // Handle foreground messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print('Received foreground message: ${message.messageId}');
      _handleForegroundMessage(message);
    });

    // Handle notification taps when app is in background
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      print('Message opened app: ${message.messageId}');
      _handleNotificationTap(message);
    });

    // Save initial token
    if (token != null) {
      await _saveTokenToFirestore(token);
    }
  }

  Future<void> _saveTokenToFirestore(String token) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await FirebaseFirestore.instance.collection('user_tokens').doc(user.uid).set({
          'token': token,
          'userId': user.uid,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    } catch (e) {
      print('Error saving token to Firestore: $e');
    }
  }

  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    // Show local notification when app is in foreground
    await showLocalNotification(
      title: message.notification?.title ?? 'New Notification',
      body: message.notification?.body ?? '',
      payload: message.data.toString(),
    );
  }

  Future<void> _handleNotificationTap(RemoteMessage message) async {
    // Handle notification tap - navigate to relevant screen
    print('Handling notification tap: ${message.data}');
    // You can add navigation logic here based on the notification data
  }

  Future<void> showLocalNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    if (!_isInitialized) await initialize();

    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'general_channel',
      'General Notifications',
      channelDescription: 'General notifications for the app',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notifications.show(
      DateTime.now().millisecondsSinceEpoch.remainder(100000),
      title,
      body,
      notificationDetails,
      payload: payload,
    );
  }

  Future<bool> requestPermissions() async {
    final status = await Permission.notification.request();
    return status.isGranted;
  }

  Future<void> _onNotificationTapped(NotificationResponse response) async {
    // Handle notification tap
    print('Notification tapped: ${response.payload}');
  }

  Future<void> showOfferNotification({
    required String title,
    required String body,
    required String stationName,
    required String offerId,
  }) async {
    if (!_isInitialized) await initialize();

    // Send push notification to all users
    await _sendPushNotificationToAllUsers(
      title: title,
      body: body,
      data: {
        'type': 'offer',
        'offerId': offerId,
        'stationName': stationName,
      },
    );

    // Also show local notification
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'offers_channel',
      'Gas Station Offers',
      channelDescription: 'Notifications for new gas station offers',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notifications.show(
      offerId.hashCode,
      title,
      body,
      notificationDetails,
      payload: 'offer:$offerId:$stationName',
    );
  }

  Future<void> showVoucherNotification({
    required String title,
    required String body,
    required String stationName,
    required String voucherId,
  }) async {
    if (!_isInitialized) await initialize();

    // Send push notification to all users
    await _sendPushNotificationToAllUsers(
      title: title,
      body: body,
      data: {
        'type': 'voucher',
        'voucherId': voucherId,
        'stationName': stationName,
      },
    );

    // Also show local notification
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'vouchers_channel',
      'Gas Station Vouchers',
      channelDescription: 'Notifications for new gas station vouchers',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notifications.show(
      voucherId.hashCode,
      title,
      body,
      notificationDetails,
      payload: 'voucher:$voucherId:$stationName',
    );
  }

  Future<void> _sendPushNotificationToAllUsers({
    required String title,
    required String body,
    required Map<String, String> data,
  }) async {
    try {
      // Get all user tokens from Firestore
      final tokensSnapshot = await FirebaseFirestore.instance
          .collection('user_tokens')
          .get();

      if (tokensSnapshot.docs.isEmpty) {
        print('No user tokens found for push notifications');
        return;
      }

      // Extract tokens
      final tokens = tokensSnapshot.docs
          .map((doc) => doc.data()['token'] as String?)
          .where((token) => token != null)
          .cast<String>()
          .toList();

      if (tokens.isEmpty) {
        print('No valid tokens found for push notifications');
        return;
      }

      print('Sending push notification to ${tokens.length} users');

      // Send notification to each token
      for (final token in tokens) {
        try {
          await _sendSinglePushNotification(
            token: token,
            title: title,
            body: body,
            data: data,
          );
        } catch (e) {
          print('Error sending notification to token $token: $e');
        }
      }
    } catch (e) {
      print('Error sending push notifications: $e');
    }
  }

  Future<void> _sendSinglePushNotification({
    required String token,
    required String title,
    required String body,
    required Map<String, String> data,
  }) async {
    // This would typically be done through a backend service
    // For now, we'll use Firebase Admin SDK or a cloud function
    // Since we can't directly send from the client, we'll store the notification
    // in Firestore and let a cloud function handle the actual sending
    
    await FirebaseFirestore.instance.collection('pending_notifications').add({
      'token': token,
      'title': title,
      'body': body,
      'data': data,
      'createdAt': FieldValue.serverTimestamp(),
      'sent': false,
    });
  }

  Future<void> showPriceAlertNotification({
    required String stationName,
    required String fuelType,
    required double price,
    required double previousPrice,
  }) async {
    if (!_isInitialized) await initialize();

    final priceChange = price - previousPrice;
    final changeText = priceChange > 0 ? 'increased' : 'decreased';
    final changeAmount = priceChange.abs().toStringAsFixed(2);

    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'price_alerts_channel',
      'Price Alerts',
      channelDescription: 'Notifications for gas price changes',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      icon: '@mipmap/ic_launcher',
    );

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notifications.show(
      '${stationName}_$fuelType'.hashCode,
      'Price Alert: $stationName',
      '$fuelType price $changeText by ₱$changeAmount to ₱${price.toStringAsFixed(2)}',
      notificationDetails,
      payload: 'price_alert:$stationName:$fuelType',
    );
  }

  Future<void> cancelNotification(int id) async {
    await _notifications.cancel(id);
  }

  Future<void> cancelAllNotifications() async {
    await _notifications.cancelAll();
  }

  Future<List<PendingNotificationRequest>> getPendingNotifications() async {
    return await _notifications.pendingNotificationRequests();
  }
}

// Background message handler - must be top-level function
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  print('Handling background message: ${message.messageId}');
  // Handle background message here
  // You can perform background tasks like updating local storage, etc.
}
