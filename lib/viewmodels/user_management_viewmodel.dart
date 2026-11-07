import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

/// Represents a single user record from the database.
class AppUser {
  final String uid;
  final String firstName;
  final String lastName;
  final String email;
  final String username;
  final String role;
  final bool isVerified;
  final bool isBanned;
  final bool restrictPostings;
  final bool restrictAdoptions;
  final bool restrictReporting;
  final int cancelledAdoptionsCount;
  final String? banReason;
  final String? profileImageUrl;
  final String? phone;
  final int? createdAt;

  AppUser({
    required this.uid,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.username,
    required this.role,
    required this.isVerified,
    this.isBanned = false,
    this.restrictPostings = false,
    this.restrictAdoptions = false,
    this.restrictReporting = false,
    this.cancelledAdoptionsCount = 0,
    this.banReason,
    this.profileImageUrl,
    this.phone,
    this.createdAt,
  });

  bool get isAdmin => role.trim().toLowerCase() == 'admin';
  bool get hasRestrictions => restrictPostings || restrictAdoptions || restrictReporting;

  String get fullName => '$firstName $lastName'.trim();

  String get status {
    if (isBanned) return 'Banned';
    if (hasRestrictions) return 'Restricted';
    if (isAdmin) return 'Admin';
    if (isVerified) return 'Verified';
    return 'Unverified';
  }

  factory AppUser.fromMap(String uid, Map<dynamic, dynamic> data) {
    String parsedRole = (data['role']?.toString() ?? 'user').trim();
    if (parsedRole.toLowerCase() == 'rescue partner' || parsedRole.toLowerCase() == 'rescue_partner') {
      parsedRole = 'partner';
    }

    return AppUser(
      uid: uid,
      firstName: data['firstName']?.toString() ?? '',
      lastName: data['lastName']?.toString() ?? '',
      email: data['email']?.toString() ?? '',
      username: data['username']?.toString() ?? '',
      role: parsedRole,
      isVerified: data['isVerified'] == true ||
          data['isVerified']?.toString().toLowerCase() == 'true',
      isBanned: data['isBanned'] == true ||
          data['isBanned']?.toString().toLowerCase() == 'true',
      restrictPostings: data['restrictPostings'] == true ||
          data['restrictPostings']?.toString().toLowerCase() == 'true',
      restrictAdoptions: data['restrictAdoptions'] == true ||
          data['restrictAdoptions']?.toString().toLowerCase() == 'true',
      restrictReporting: data['restrictReporting'] == true ||
          data['restrictReporting']?.toString().toLowerCase() == 'true',
      cancelledAdoptionsCount: (data['cancelledAdoptionsCount'] as num?)?.toInt() ?? 0,
      banReason: data['banReason']?.toString(),
      profileImageUrl: data['profileImageUrl']?.toString(),
      phone: data['phone']?.toString(),
      createdAt: data['createdAt'] is int ? data['createdAt'] as int : null,
    );
  }
}

class UserManagementViewModel extends ChangeNotifier {
  final FirebaseDatabase _db = FirebaseDatabase.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  StreamSubscription<DatabaseEvent>? _usersSubscription;

  List<AppUser> _users = [];
  List<AppUser> get users => _filteredUsers;
  int get totalUsersCount => _users.length;
  bool get isFiltered => _searchQuery.isNotEmpty || _filterStatus != 'All';

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _error;
  String? get error => _error;

  bool _isPermissionDenied = false;
  bool get isPermissionDenied => _isPermissionDenied;

  String _searchQuery = '';
  String get searchQuery => _searchQuery;

  String _filterStatus = 'All';
  String get filterStatus => _filterStatus;

  AppUser? _selectedUser;
  AppUser? get selectedUser => _selectedUser;

  List<AppUser> get _filteredUsers {
    var filtered = _users;

    // Apply search
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      filtered = filtered.where((u) {
        return u.fullName.toLowerCase().contains(query) ||
            u.email.toLowerCase().contains(query) ||
            u.username.toLowerCase().contains(query);
      }).toList();
    }

    // Apply status filter
    if (_filterStatus != 'All') {
      filtered = filtered.where((u) => u.status == _filterStatus).toList();
    }

    return filtered;
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  void setFilterStatus(String status) {
    _filterStatus = status;
    notifyListeners();
  }

  void selectUser(AppUser? user) {
    _selectedUser = user;
    notifyListeners();
  }

  /// Listen to all users in realtime.
  void listenToUsers() {
    _usersSubscription?.cancel();
    _isLoading = true;
    _error = null;
    _isPermissionDenied = false;
    notifyListeners();

    _usersSubscription = _db.ref().child('users').onValue.listen((event) {
      if (event.snapshot.exists && event.snapshot.value != null) {
        final data = event.snapshot.value as Map<dynamic, dynamic>;
        _users = data.entries.map((e) {
          return AppUser.fromMap(
            e.key.toString(),
            e.value as Map<dynamic, dynamic>,
          );
        }).toList();

        // Sort: admins first, then by name
        _users.sort((a, b) {
          if (a.isAdmin && !b.isAdmin) return -1;
          if (!a.isAdmin && b.isAdmin) return 1;
          return a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase());
        });

        // Update selected user if it still exists
        if (_selectedUser != null) {
          final updated = _users.where((u) => u.uid == _selectedUser!.uid);
          _selectedUser = updated.isNotEmpty ? updated.first : null;
        }
      } else {
        _users = [];
      }
      _isLoading = false;
      _error = null;
      _isPermissionDenied = false;
      notifyListeners();
    }, onError: (error) {
      _isLoading = false;
      _error = error.toString();
      final errStr = error.toString().toLowerCase();
      if (errStr.contains('permission-denied') || errStr.contains('permission denied')) {
        _isPermissionDenied = true;
      }
      notifyListeners();
    });
  }

  /// Clears all cached user data and cancels subscriptions.
  void clearData() {
    _usersSubscription?.cancel();
    _usersSubscription = null;
    _users = [];
    _selectedUser = null;
    _searchQuery = '';
    _filterStatus = 'All';
    _error = null;
    _isPermissionDenied = false;
    _isLoading = false;
    notifyListeners();
  }

  /// Send a password reset email to the given user.
  Future<String?> sendPasswordReset(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
      return null; // success
    } on FirebaseAuthException catch (e) {
      return e.message ?? 'Failed to send password reset email.';
    } catch (e) {
      return e.toString();
    }
  }

  /// Update user's role
  Future<void> updateUserRole(String uid, String newRole) async {
    final cleanRole = newRole.toLowerCase().trim();
    await _db.ref().child('users').child(uid).update({
      'role': cleanRole,
      'isAdmin': cleanRole == 'admin',
    });
  }

  /// Toggle user verification status
  Future<void> toggleUserVerification(String uid, bool currentStatus) async {
    await _db.ref().child('users').child(uid).update({
      'isVerified': !currentStatus,
    });
  }

  /// Ban or unban user
  Future<void> toggleUserBan(String uid, bool currentlyBanned, {String? reason}) async {
    if (currentlyBanned) {
      await _db.ref().child('users').child(uid).update({
        'isBanned': false,
        'restrictPostings': false,
        'restrictAdoptions': false,
        'restrictReporting': false,
        'banReason': null,
      });
    } else {
      await _db.ref().child('users').child(uid).update({
        'isBanned': true,
        'banReason': reason ?? 'Terms violation',
      });
    }
  }

  /// Update user granular restrictions & ban status
  Future<void> updateUserRestrictions(
    String uid, {
    required bool isBanned,
    required bool restrictPostings,
    required bool restrictAdoptions,
    required bool restrictReporting,
    String? reason,
  }) async {
    await _db.ref().child('users').child(uid).update({
      'isBanned': isBanned,
      'restrictPostings': restrictPostings,
      'restrictAdoptions': restrictAdoptions,
      'restrictReporting': restrictReporting,
      'banReason': reason,
    });
  }

  @override
  void dispose() {
    _usersSubscription?.cancel();
    super.dispose();
  }
}
