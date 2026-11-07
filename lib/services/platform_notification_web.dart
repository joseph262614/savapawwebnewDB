// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import 'package:flutter/foundation.dart';

class PlatformNotification {
  static const String announcementsChannelId = 'announcements_channel';
  static const String rescueAlertsChannelId = 'rescue_alerts_channel';

  static Future<void> requestPermission() async {
    try {
      if (html.Notification.permission == 'default') {
        final result = await html.Notification.requestPermission();
        debugPrint("Admin Web notification permission: $result");
      }
    } catch (e) {
      debugPrint("Admin Web notification permission request error: $e");
    }
  }

  static bool isSupported() {
    try {
      return html.Notification.supported;
    } catch (_) {
      return false;
    }
  }

  static Future<void> showNotification({
    required String title,
    required String body,
    String? channelId,
    String? payload,
    String? iconUrl,
  }) async {
    try {
      if (html.Notification.permission == 'granted') {
        html.Notification(
          title,
          body: body,
          icon: iconUrl ?? 'icons/Icon-192.png',
        );
      } else if (html.Notification.permission == 'default') {
        html.Notification.requestPermission().then((permission) {
          if (permission == 'granted') {
            html.Notification(
              title,
              body: body,
              icon: iconUrl ?? 'icons/Icon-192.png',
            );
          }
        });
      }
    } catch (e) {
      debugPrint("Failed to display admin platform notification: $e");
    }
  }
}
