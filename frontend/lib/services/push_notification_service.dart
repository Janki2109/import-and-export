import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../core/navigation/navigator_key.dart';
import '../screens/shared/notifications_screen.dart';
import 'notification_service.dart';

/// Must match backend's fcm.AndroidChannelID (pkg/fcm/client.go) so the system tray uses this
/// channel's sound/vibration/importance instead of falling back to Android defaults.
const String _androidChannelId = 'onebharat_notifications';
const String _androidChannelName = 'One Bharat';
const String _androidChannelDescription = 'Order, payment, KYC, shipment and message alerts';

final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();

/// Top-level (not a class method) background message handler — FCM requires this to be a
/// top-level or static function so it can be invoked in a separate isolate when the app is
/// fully terminated. It intentionally does very little: the OS already renders the system-tray
/// notification for a message that has a `notification` payload (which every push this app
/// sends does — see NotificationService.Send on the backend), so there's nothing to display
/// here. This handler exists so FCM has a registered background entry point at all, which is
/// required for background/terminated delivery to work reliably on Android.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('Background push received: ${message.notification?.title}');
}

/// Wraps Firebase Cloud Messaging: requests permission, fetches the device's registration
/// token, registers it with our backend (so the server can push via FCM), and keeps it
/// fresh on rotation. Also owns the local-notifications plugin used to show the system-tray
/// banner for messages that arrive while the app is in the foreground (FCM does this
/// automatically in background/terminated, but not foreground — the OS assumes a foregrounded
/// app will handle its own UI). Call [init] once after login succeeds.
class PushNotificationService {
  static final PushNotificationService _instance = PushNotificationService._internal();
  factory PushNotificationService() => _instance;
  PushNotificationService._internal();

  final _notificationService = NotificationService();
  bool _initialized = false;
  bool _localNotificationsInitialized = false;

  /// Sets up the local-notifications plugin and Android notification channel. Safe to call
  /// before login (called once from main()) since it only touches local OS notification
  /// plumbing, not anything account-specific.
  Future<void> initLocalNotifications() async {
    if (_localNotificationsInitialized) return;
    _localNotificationsInitialized = true;

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: false, // requested explicitly via FirebaseMessaging.requestPermission instead
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _localNotifications.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveNotificationResponse: (response) => _handleNotificationTap(response.payload),
    );

    if (Platform.isAndroid) {
      // Custom notification sound — android/app/src/main/res/raw/notification_sound.mp3.
      // NOTE: an Android notification channel's sound is locked in at first creation; if this
      // ever needs to change again, bump _androidChannelId (e.g. 'onebharat_notifications_v2')
      // since updating the sound on an already-created channel silently has no effect on
      // devices that already created the old one.
      const channel = AndroidNotificationChannel(
        _androidChannelId,
        _androidChannelName,
        description: _androidChannelDescription,
        importance: Importance.high,
        playSound: true,
        sound: RawResourceAndroidNotificationSound('notification_sound'),
        enableVibration: true,
      );
      await _localNotifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);
    }
  }

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    try {
      await initLocalNotifications();

      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(alert: true, badge: true, sound: true);

      final token = await messaging.getToken();
      if (token != null) {
        await _registerToken(token);
      }
      messaging.onTokenRefresh.listen(_registerToken);

      // Foreground messages don't reach the system tray on their own (the OS assumes a
      // foregrounded app renders its own UI) — show them ourselves via local notifications so
      // foreground behaves the same as background/closed, matching WhatsApp-style delivery.
      FirebaseMessaging.onMessage.listen(_showForegroundNotification);

      // App was backgrounded (not terminated) and the user tapped the system notification.
      FirebaseMessaging.onMessageOpenedApp.listen((message) => _navigateForMessage(message.data));

      // App was fully terminated and launched by tapping the system notification.
      final initialMessage = await messaging.getInitialMessage();
      if (initialMessage != null) {
        _navigateForMessage(initialMessage.data);
      }
    } catch (e) {
      debugPrint('Push notification init failed (continuing without push): $e');
    }
  }

  Future<void> _showForegroundNotification(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;
    final payload = _encodePayload(message.data);
    await _localNotifications.show(
      notification.hashCode,
      notification.title,
      notification.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _androidChannelId,
          _androidChannelName,
          channelDescription: _androidChannelDescription,
          importance: Importance.high,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
        ),
        iOS: const DarwinNotificationDetails(presentAlert: true, presentBadge: true, presentSound: true),
      ),
      payload: payload,
    );
  }

  String _encodePayload(Map<String, dynamic> data) {
    final type = data['type'] ?? '';
    final referenceId = data['reference_id'] ?? '';
    return '$type|$referenceId';
  }

  void _handleNotificationTap(String? payload) {
    if (payload == null || payload.isEmpty) return;
    final parts = payload.split('|');
    final type = parts.isNotEmpty ? parts[0] : '';
    final referenceId = parts.length > 1 ? parts[1] : '';
    _navigateForMessage({'type': type, 'reference_id': referenceId});
  }

  /// Routes a tapped notification to the existing in-app Notifications screen — the one
  /// existing, category-aware place every notification type (order, payment, KYC, shipment,
  /// message, RFQ) already surfaces with its reference. Per-type screens (order details, chat,
  /// KYC, wallet) each require data fetched by ID before they can render, so landing on the
  /// inbox first — where the matching notification is one tap away with full context — is the
  /// safe, existing-screens-only route requested, without needing a new fetch-then-navigate
  /// path per notification type.
  void _navigateForMessage(Map<String, dynamic> data) {
    final navigator = rootNavigatorKey.currentState;
    if (navigator == null) return;
    navigator.push(MaterialPageRoute(builder: (_) => const NotificationsScreen()));
  }

  Future<void> _registerToken(String token) async {
    try {
      await _notificationService.registerDevice(
        token: token,
        platform: Platform.isIOS ? 'ios' : 'android',
      );
    } catch (e) {
      debugPrint('Device token registration failed: $e');
    }
  }

  /// Called on logout — best-effort so this device stops receiving pushes for the account
  /// that just signed out (important on shared/reused devices). Never throws: logout must
  /// succeed locally even if this network call fails.
  Future<void> unregisterCurrentDevice() async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await _notificationService.unregisterDevice(token);
      }
    } catch (e) {
      debugPrint('Device token unregistration failed (continuing logout): $e');
    }
  }
}
