import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'platform_notification.dart';

class NotificationService extends ChangeNotifier {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final DatabaseReference _dbRef = FirebaseDatabase.instance.ref();
  StreamSubscription<DatabaseEvent>? _announcementsSubscription;

  List<Map<String, dynamic>> _announcements = [];
  List<Map<String, dynamic>> get announcements => _announcements;

  bool _initialized = false;
  bool get initialized => _initialized;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    // Request browser notification permission
    PlatformNotification.requestPermission();

    _listenToAnnouncements();
  }

  void _listenToAnnouncements() {
    _announcementsSubscription?.cancel();
    _announcementsSubscription = _dbRef.child('announcements').onValue.listen((event) {
      final snapshot = event.snapshot;
      List<Map<String, dynamic>> fetched = [];

      if (snapshot.exists && snapshot.value != null) {
        final dynamic raw = snapshot.value;
        if (raw is Map) {
          raw.forEach((key, value) {
            if (value is Map) {
              final item = Map<String, dynamic>.from(value);
              item['id'] = key.toString();
              fetched.add(item);
            }
          });
        }
      }

      fetched.sort((a, b) {
        final tA = a['timestamp'] is int ? a['timestamp'] as int : 0;
        final tB = b['timestamp'] is int ? b['timestamp'] as int : 0;
        return tB.compareTo(tA);
      });

      _announcements = fetched;
      notifyListeners();
    }, onError: (err) {
      debugPrint("Admin announcements stream error: $err");
    });
  }

  /// Broadcasts an announcement to all users
  Future<void> broadcastAnnouncement({
    required String title,
    required String message,
    required String category,
    required String priority,
    required String authorUid,
    required String authorName,
    String? imageUrl,
  }) async {
    final ref = _dbRef.child('announcements').push();
    final announcementData = {
      'id': ref.key,
      'title': title.trim(),
      'message': message.trim(),
      'category': category,
      'priority': priority.toLowerCase(),
      'authorUid': authorUid,
      'authorName': authorName,
      'imageUrl': imageUrl,
      'timestamp': ServerValue.timestamp,
      'isActive': true,
    };

    await ref.set(announcementData);

    // Show native system desktop alert outside the browser window
    PlatformNotification.showNotification(
      title: '📢 Broadcast Sent: $title',
      body: message,
    );
  }

  /// Delete an announcement
  Future<void> deleteAnnouncement(String id) async {
    await _dbRef.child('announcements').child(id).remove();
  }

  @override
  void dispose() {
    _announcementsSubscription?.cancel();
    super.dispose();
  }
}
