import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

class AuthViewModel extends ChangeNotifier {
  FirebaseAuth get _auth => FirebaseAuth.instance;
  FirebaseDatabase get _db => FirebaseDatabase.instance;
  
  User? _user;
  User? get user => _user;
  
  bool get isLoggedIn => _user != null && _isAdminSession;
  bool _isInitialized = false;
  bool _isAdminSession = false;
  bool get isAdmin => _isAdminSession;

  bool _isAuthChecking = true;
  bool get isAuthChecking => _isAuthChecking;

  Map<dynamic, dynamic>? _userData;
  Map<dynamic, dynamic>? get userData => _userData;

  StreamSubscription<DatabaseEvent>? _userSubscription;
  StreamSubscription<User?>? _authSubscription;

  AuthViewModel();

  void initialize() {
    if (_isInitialized) return;
    _isInitialized = true;
    _isAuthChecking = true;

    _authSubscription?.cancel();
    _authSubscription = _auth.authStateChanges().listen((User? user) async {
      _user = user;
      if (user != null) {
        final isAdminFresh = await checkIfAdmin(user.uid);
        _isAdminSession = isAdminFresh;
        if (!isAdminFresh) {
          _userData = null;
          _userSubscription?.cancel();
          _userSubscription = null;
          await _auth.signOut();
        } else {
          _listenToUserData(user.uid);
        }
      } else {
        _userData = null;
        _isAdminSession = false;
        _userSubscription?.cancel();
        _userSubscription = null;
      }
      _isAuthChecking = false;
      notifyListeners();
    });
  }

  void _listenToUserData(String uid) {
    _userSubscription?.cancel();

    _userSubscription = _db.ref().child('users').child(uid).onValue.listen((event) {
      if (event.snapshot.exists && event.snapshot.value != null && event.snapshot.value is Map) {
        final data = Map<String, dynamic>.from(event.snapshot.value as Map);
        _userData = data;
        final role = (data['role']?.toString() ?? '').trim().toLowerCase();
        final isNowAdmin = role == 'admin';
        if (!isNowAdmin && _isAdminSession) {
          _isAdminSession = false;
          _userData = null;
          signOut();
          return;
        }
        _isAdminSession = isNowAdmin;
        notifyListeners();
      } else {
        if (_isAdminSession) {
          _isAdminSession = false;
          _userData = null;
          signOut();
        }
      }
    }, onError: (error) {
      debugPrint("User data listener error: $error");
      if (error.toString().toLowerCase().contains('permission')) {
        _isAdminSession = false;
        _userData = null;
        signOut();
      }
    });
  }

  Future<bool> checkIfAdmin(String uid) async {
    try {
      final snapshot = await _db.ref().child('users').child(uid).child('role').get();
      if (snapshot.exists && snapshot.value != null) {
        final role = snapshot.value.toString().trim().toLowerCase();
        return role == 'admin';
      }
      return false;
    } catch (e) {
      debugPrint("checkIfAdmin error: $e");
      return false;
    }
  }

  Future<String?> signIn(String identifier, String password) async {
    try {
      // Automatically trim whitespace from the input
      final cleanIdentifier = identifier.trim();
      final cleanPassword = password.trim();
      
      String email = cleanIdentifier;

      if (!cleanIdentifier.contains('@')) {
        debugPrint("Attempting username lookup for: '$cleanIdentifier'");
        final foundEmail = await _getEmailFromUsername(cleanIdentifier);
        
        if (foundEmail == null) {
          debugPrint("Username '$cleanIdentifier' not found in database.");
          return "Incorrect email or password";
        }
        
        debugPrint("Username found. Associated email: $foundEmail");
        email = foundEmail;
      }

      UserCredential credential = await _auth.signInWithEmailAndPassword(
        email: email, 
        password: cleanPassword
      );
      
      if (credential.user != null) {
        await _ensureUsernameIndexed(credential.user!);
        bool isAdminUser = await checkIfAdmin(credential.user!.uid);
        _isAdminSession = isAdminUser;
        
        if (!isAdminUser) {
          await _auth.signOut();
          _isAdminSession = false;
          return "Access denied. This portal is for administrators only.";
        }
      }
      return null;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found' || e.code == 'wrong-password' || e.code == 'invalid-credential') {
        return "Incorrect email or password";
      }
      return e.message;
    } catch (e) {
      return e.toString();
    }
  }

  /// Converts a username into a valid, case-insensitive Realtime Database key.
  String _usernameKey(String username) =>
      username.trim().toLowerCase().replaceAll(RegExp(r'[.#$\[\]/]'), '_');

  /// Looks up the email linked to a username from the public `usernames` index.
  Future<String?> _getEmailFromUsername(String username) async {
    final key = _usernameKey(username);
    if (key.isEmpty) return null;
    final snapshot = await _db.ref().child('usernames').child(key).get();
    if (!snapshot.exists) return null;
    final data = snapshot.value;
    if (data is Map) return data['email']?.toString();
    return null;
  }

  Future<bool> isUsernameAvailable(String username) async {
    final key = _usernameKey(username);
    if (key.isEmpty) return false;
    final snapshot = await _db.ref().child('usernames').child(key).get();
    return !snapshot.exists;
  }

  Future<void> _ensureUsernameIndexed(User user) async {
    try {
      final snap = await _db.ref().child('users').child(user.uid).child('username').get();
      final username = snap.value?.toString();
      if (username == null || username.trim().isEmpty || user.email == null) return;
      final ref = _db.ref().child('usernames').child(_usernameKey(username));
      final existing = await ref.get();
      if (!existing.exists) {
        await ref.set({'uid': user.uid, 'email': user.email});
      }
    } catch (e) {
      debugPrint("Username index error: $e");
    }
  }

  Future<String?> signUp({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    required String username,
    required String role,
  }) async {
    try {
      if (username.contains('@')) {
        return "Username cannot contain '@'";
      }
      final available = await isUsernameAvailable(username);
      if (!available) return "This username is already exist";

      UserCredential credential = await _auth.createUserWithEmailAndPassword(email: email.trim(), password: password.trim());
      if (credential.user != null) {
        final key = _usernameKey(username);
        await _db.ref().child('usernames').child(key).set({
          'uid': credential.user!.uid,
          'email': email.trim(),
        });
        await credential.user!.updateDisplayName("$firstName $lastName");
        await credential.user!.sendEmailVerification();
        await _db.ref().child('users').child(credential.user!.uid).set({
          'firstName': firstName,
          'lastName': lastName,
          'username': username,
          'email': email.trim(),
          'role': role,
          'isVerified': false,
          'createdAt': ServerValue.timestamp,
        });
        await _auth.signOut();
      }
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  Future<void> signOut() async {
    _userSubscription?.cancel();
    _userSubscription = null;
    await _auth.signOut();
    _user = null;
    _userData = null;
    _isAdminSession = false;
    notifyListeners();
  }

  Future<String?> sendPasswordResetEmail(String? email) async {
    final emailToSend = email ?? _user?.email;
    if (emailToSend == null) return "Email not found";
    try { await _auth.sendPasswordResetEmail(email: emailToSend); return null; } catch (e) { return e.toString(); }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _userSubscription?.cancel();
    super.dispose();
  }
}
