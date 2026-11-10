import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'platform_notification.dart';
import 'firebase_service.dart';

class NotificationService extends ChangeNotifier {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final DatabaseReference _dbRef = FirebaseService.ref;
  StreamSubscription<DatabaseEvent>? _announcementsSubscription;
  StreamSubscription<DatabaseEvent>? _readSubscription;
  StreamSubscription<User?>? _authSubscription;

  List<Map<String, dynamic>> _announcements = [];
  List<Map<String, dynamic>> get announcements => _announcements;

  final Set<String> _readAnnouncementIds = <String>{};
  int _unreadCount = 0;
  int get unreadCount => _unreadCount;

  bool _initialized = false;
  bool get initialized => _initialized;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    // Request browser notification permission
    PlatformNotification.requestPermission();

    _listenToAnnouncements();

    _authSubscription?.cancel();
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((user) {
      _bindUserReadListener(user?.uid);
    });
    _bindUserReadListener(FirebaseAuth.instance.currentUser?.uid);
  }

  void _bindUserReadListener(String? uid) {
    _readSubscription?.cancel();
    _readSubscription = null;
    _readAnnouncementIds.clear();
    if (uid == null || uid.isEmpty) {
      _recalculateUnreadCount();
      return;
    }

    _readSubscription = _dbRef.child('users').child(uid).child('read_announcements').onValue.listen((event) {
      if (event.snapshot.exists && event.snapshot.value is Map) {
        final map = event.snapshot.value as Map;
        map.forEach((k, v) {
          if (v == true) {
            _readAnnouncementIds.add(k.toString());
          }
        });
      }
      _recalculateUnreadCount();
    }, onError: (err) {
      debugPrint("Read announcements stream error: $err");
    });
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
        final tA = (a['timestamp'] as num?)?.toInt() ?? 0;
        final tB = (b['timestamp'] as num?)?.toInt() ?? 0;
        return tB.compareTo(tA);
      });

      _announcements = fetched;
      _recalculateUnreadCount();
    }, onError: (err) {
      debugPrint("Admin announcements stream error: $err");
    });
  }

  void _recalculateUnreadCount() {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    int unread = 0;
    for (final a in _announcements) {
      final id = a['id']?.toString() ?? '';
      final authorUid = a['authorUid']?.toString();
      if (authorUid != null && currentUid != null && authorUid == currentUid) {
        _readAnnouncementIds.add(id);
        continue;
      }
      if (id.isNotEmpty && !_readAnnouncementIds.contains(id)) {
        unread++;
      }
    }
    _unreadCount = unread;
    notifyListeners();
  }

  Future<void> markAllAsRead() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final updates = <String, dynamic>{};
    for (final a in _announcements) {
      final id = a['id']?.toString() ?? '';
      if (id.isNotEmpty) {
        _readAnnouncementIds.add(id);
        if (uid != null && uid.isNotEmpty) {
          updates[id] = true;
        }
      }
    }
    _unreadCount = 0;
    notifyListeners();

    if (uid != null && uid.isNotEmpty && updates.isNotEmpty) {
      try {
        await _dbRef.child('users').child(uid).child('read_announcements').update(updates);
      } catch (e) {
        debugPrint("Error writing read announcements to Firebase: $e");
      }
    }
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
  }

  /// Delete an announcement
  Future<void> deleteAnnouncement(String id) async {
    await _dbRef.child('announcements').child(id).remove();
  }

  @override
  void dispose() {
    _announcementsSubscription?.cancel();
    _readSubscription?.cancel();
    _authSubscription?.cancel();
    super.dispose();
  }
}
