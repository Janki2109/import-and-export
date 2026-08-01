import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'notification_service.dart';

/// Wraps Firebase Cloud Messaging: requests permission, fetches the device's registration
/// token, registers it with our backend (so the server can push via FCM), and keeps it
/// fresh on rotation. Call [init] once after login succeeds.
class PushNotificationService {
  static final PushNotificationService _instance = PushNotificationService._internal();
  factory PushNotificationService() => _instance;
  PushNotificationService._internal();

  final _notificationService = NotificationService();
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    try {
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(alert: true, badge: true, sound: true);

      final token = await messaging.getToken();
      if (token != null) {
        await _registerToken(token);
      }
      messaging.onTokenRefresh.listen(_registerToken);

      // Foreground messages arrive here instead of the system tray — the OS shows a
      // system notification automatically only when the app is backgrounded/terminated.
      FirebaseMessaging.onMessage.listen((message) {
        debugPrint('Foreground push received: ${message.notification?.title} — ${message.notification?.body}');
      });
    } catch (e) {
      debugPrint('Push notification init failed (continuing without push): $e');
    }
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
}
