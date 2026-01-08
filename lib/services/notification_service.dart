import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

import '../main.dart';
import '../screens/notifications_screen.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  bool _isInitialized = false;
  // Global in-memory toggles for notifications (can be persisted later)
  bool _globalOffersNotificationsEnabled = true;
  bool _globalVouchersNotificationsEnabled = true;

  // Firestore listener for real-time notifications (free, client-side approach)
  StreamSubscription<QuerySnapshot>? _notificationsListener;
  Set<String> _processedNotificationIds =
      {}; // Track which notifications we've already shown

  Future<void> initialize() async {
    if (_isInitialized) return;

    // Initialize local notifications
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/launcher_icon');

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

    // Setup Firestore listener for real-time notifications (free, client-side)
    _setupNotificationsListener();

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
    } else if (settings.authorizationStatus ==
        AuthorizationStatus.provisional) {
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
        await FirebaseFirestore.instance
            .collection('user_tokens')
            .doc(user.uid)
            .set({
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

    // Use the global navigator key to navigate to the notifications screen
    if (navigatorKey.currentState != null) {
      navigatorKey.currentState!.push(
        MaterialPageRoute(builder: (_) => const NotificationsScreen()),
      );
    }
  }

  Future<void> showLocalNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    if (!_isInitialized) await initialize();

    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      'general_channel',
      'General Notifications',
      channelDescription: 'General notifications for the app',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/launcher_icon',
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

  // Global notification toggles
  bool get isGlobalOffersEnabled => _globalOffersNotificationsEnabled;
  bool get isGlobalVouchersEnabled => _globalVouchersNotificationsEnabled;

  void setGlobalOffersEnabled(bool enabled) {
    _globalOffersNotificationsEnabled = enabled;
  }

  void setGlobalVouchersEnabled(bool enabled) {
    _globalVouchersNotificationsEnabled = enabled;
  }

  Future<bool> requestPermissions() async {
    final status = await Permission.notification.request();
    return status.isGranted;
  }

  Future<void> _onNotificationTapped(NotificationResponse response) async {
    // Handle notification tap
    print('Notification tapped: ${response.payload}');

    // Use the global navigator key to navigate to the notifications screen
    if (navigatorKey.currentState != null) {
      navigatorKey.currentState!.push(
        MaterialPageRoute(builder: (_) => const NotificationsScreen()),
      );
    }
  }

  Future<void> showOfferNotification({
    required String title,
    required String body,
    required String stationName,
    required String offerId,
  }) async {
    if (!_isInitialized) await initialize();

    // Create notification document in Firestore FIRST (FREE approach - no cloud functions needed!)
    // All user apps will automatically detect this via Firestore listener and show notification
    // We create the document first so other devices can pick it up immediately
    await _createNotificationDocument(
      title: title,
      body: body,
      stationName: stationName,
      type: 'offer',
      itemId: offerId,
    );

    // Also show local notification on THIS device (other devices will get it via listener)
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      'offers_channel',
      'Gas Station Offers',
      channelDescription: 'Notifications for new gas station offers',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/launcher_icon',
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

    // Mark this notification as processed so the listener doesn't show it again on this device
    // We'll use the document ID, but we need to get it. For now, we'll use a hash of the offerId
    // The listener will handle deduplication based on the actual document ID
    print(
        'Offer notification created and shown locally. Firestore document created for other devices.');
  }

  Future<void> showVoucherNotification({
    required String title,
    required String body,
    required String stationName,
    required String voucherId,
  }) async {
    if (!_isInitialized) await initialize();

    // Create notification document in Firestore FIRST (FREE approach - no cloud functions needed!)
    // All user apps will automatically detect this via Firestore listener and show notification
    // We create the document first so other devices can pick it up immediately
    await _createNotificationDocument(
      title: title,
      body: body,
      stationName: stationName,
      type: 'voucher',
      itemId: voucherId,
    );

    // Also show local notification on THIS device (other devices will get it via listener)
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      'vouchers_channel',
      'Gas Station Vouchers',
      channelDescription: 'Notifications for new gas station vouchers',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/launcher_icon',
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

    // Mark this notification as processed so the listener doesn't show it again on this device
    // The listener will handle deduplication based on the actual document ID
    print(
        'Voucher notification created and shown locally. Firestore document created for other devices.');
  }

  Future<void> _createNotificationDocument({
    required String title,
    required String body,
    required String stationName,
    required String type,
    required String itemId,
  }) async {
    try {
      final docRef =
          await FirebaseFirestore.instance.collection('notifications').add({
        'title': title,
        'body': body,
        'stationName': stationName,
        'type': type,
        'itemId': itemId,
        'createdAt': FieldValue.serverTimestamp(),
        'read': false,
      });

      // Mark this notification as processed on THIS device to prevent duplicate
      // The creating device already showed the notification locally, so we don't want the listener to show it again
      _processedNotificationIds.add(docRef.id);

      print('Notification document created in Firestore with ID: ${docRef.id}');
    } catch (e) {
      print('Failed to create notification document: $e');
    }
  }

  /// Setup Firestore listener to watch for new notifications (FREE, client-side approach)
  /// This works like your admin functionality - no cloud functions needed!
  void _setupNotificationsListener() {
    print('Setting up notifications listener...');

    // Listen to notifications collection for new entries
    // We use a simple query without orderBy to avoid index requirements and handle null createdAt
    _notificationsListener = FirebaseFirestore.instance
        .collection('notifications')
        .snapshots(
            includeMetadataChanges: false) // Only listen to actual data changes
        .listen((snapshot) {
      print(
          'Notifications listener received ${snapshot.docChanges.length} changes');

      // Process new notifications
      for (final docChange in snapshot.docChanges) {
        // Only process newly added documents (not existing ones or modifications)
        if (docChange.type != DocumentChangeType.added) {
          continue;
        }

        final notificationId = docChange.doc.id;
        final data = docChange.doc.data();

        print('Processing new notification: $notificationId');

        // Skip if data is null
        if (data == null) {
          print('Notification $notificationId: data is null, skipping');
          continue;
        }

        // Skip if we've already processed this notification
        if (_processedNotificationIds.contains(notificationId)) {
          print('Notification $notificationId: already processed, skipping');
          continue;
        }

        // Skip if notification is marked as read
        if (data['read'] == true) {
          print('Notification $notificationId: marked as read, skipping');
          continue;
        }

        // Handle serverTimestamp - it might be null initially
        final createdAt = data['createdAt'];
        Timestamp? timestamp;

        if (createdAt is Timestamp) {
          timestamp = createdAt;
        } else if (createdAt == null) {
          // ServerTimestamp hasn't been resolved yet - show the notification anyway
          // This is important for real-time notifications
          print(
              'Notification $notificationId: createdAt is null (serverTimestamp pending), showing anyway');
        } else {
          // Try to cast it
          try {
            timestamp = createdAt as Timestamp?;
          } catch (e) {
            print(
                'Error parsing createdAt for notification $notificationId: $e');
          }
        }

        // If we have a timestamp, check if it's too old (only filter out very old ones)
        if (timestamp != null) {
          final created = timestamp.toDate();
          // Only skip notifications older than 1 hour (to avoid showing very old notifications on first load)
          if (created
              .isBefore(DateTime.now().subtract(const Duration(hours: 1)))) {
            print(
                'Notification $notificationId: too old (${created}), skipping');
            continue;
          }
        }

        // Mark as processed immediately to avoid duplicate notifications
        _processedNotificationIds.add(notificationId);

        // Show local notification
        final title = data['title'] as String? ?? 'New Notification';
        final body = data['body'] as String? ?? '';
        final type = data['type'] as String? ?? 'general';

        // Determine channel based on type
        String channelId = 'general_channel';
        if (type == 'offer') {
          channelId = 'offers_channel';
        } else if (type == 'voucher') {
          channelId = 'vouchers_channel';
        } else if (type == 'price_alert') {
          channelId = 'price_alerts_channel';
        }

        print(
            'Showing notification from Firestore: $title - $body (type: $type, channel: $channelId)');

        // Show the notification
        _showNotificationFromFirestore(
          id: notificationId.hashCode,
          title: title,
          body: body,
          channelId: channelId,
          payload:
              '${type}:${data['itemId'] as String? ?? ''}:${data['stationName'] as String? ?? ''}',
        );
      }

      // Clean up old processed IDs (keep only last 100)
      if (_processedNotificationIds.length > 100) {
        final idsToKeep = _processedNotificationIds.toList().take(100).toSet();
        _processedNotificationIds = idsToKeep;
      }
    }, onError: (error) {
      print('Error in notifications listener: $error');
      // Try to restart the listener after a delay
      Future.delayed(const Duration(seconds: 5), () {
        if (_isInitialized) {
          print('Attempting to restart notifications listener...');
          _setupNotificationsListener();
        }
      });
    });

    print('Notifications listener set up successfully');
  }

  /// Show notification from Firestore data
  Future<void> _showNotificationFromFirestore({
    required int id,
    required String title,
    required String body,
    required String channelId,
    String? payload,
  }) async {
    if (!_isInitialized) await initialize();

    // Create Android details with correct channel
    final androidDetails = AndroidNotificationDetails(
      channelId,
      channelId == 'offers_channel'
          ? 'Gas Station Offers'
          : channelId == 'vouchers_channel'
              ? 'Gas Station Vouchers'
              : channelId == 'price_alerts_channel'
                  ? 'Price Alerts'
                  : 'General Notifications',
      channelDescription: channelId == 'offers_channel'
          ? 'Notifications for new gas station offers'
          : channelId == 'vouchers_channel'
              ? 'Notifications for new gas station vouchers'
              : channelId == 'price_alerts_channel'
                  ? 'Notifications for gas price changes'
                  : 'General notifications for the app',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/launcher_icon',
    );

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notifications.show(
      id,
      title,
      body,
      notificationDetails,
      payload: payload,
    );
  }

  /// Cleanup listener when service is disposed
  void dispose() {
    _notificationsListener?.cancel();
    _processedNotificationIds.clear();
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

    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      'price_alerts_channel',
      'Price Alerts',
      channelDescription: 'Notifications for gas price changes',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      icon: '@mipmap/launcher_icon',
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
