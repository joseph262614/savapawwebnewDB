class PlatformNotification {
  static Future<void> requestPermission() async {}
  static bool isSupported() => false;
  static void showNotification({
    required String title,
    required String body,
    String? iconUrl,
  }) {}
}
