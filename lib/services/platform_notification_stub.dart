class PlatformNotification {
  static const String announcementsChannelId = 'announcements_channel';
  static const String rescueAlertsChannelId = 'rescue_alerts_channel';

  static Future<void> requestPermission() async {}
  static bool isSupported() => false;
  static Future<void> showNotification({
    required String title,
    required String body,
    String? channelId,
    String? payload,
    String? iconUrl,
  }) async {}
}
