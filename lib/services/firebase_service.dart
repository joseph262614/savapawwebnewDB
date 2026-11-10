import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import '../firebase_options.dart';

/// Single shared Firebase service providing unified, guarded Firebase initialization
/// and a single shared Realtime Database instance across the application.
class FirebaseService {
  FirebaseService._();

  static FirebaseApp? _app;
  static FirebaseDatabase? _db;

  /// Singleton FirebaseApp initialization.
  /// Guarded with Firebase.apps.isNotEmpty (equivalent to !getApps().length ? initializeApp() : getApp())
  /// and handles duplicate-app exceptions cleanly.
  static Future<FirebaseApp> initialize() async {
    if (_app != null) return _app!;
    if (Firebase.apps.isNotEmpty) {
      _app = Firebase.app();
    } else {
      try {
        _app = await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      } on FirebaseException catch (e) {
        if (e.code == 'duplicate-app') {
          _app = Firebase.app();
        } else {
          rethrow;
        }
      } catch (e) {
        if (e.toString().contains('duplicate-app')) {
          _app = Firebase.app();
        } else {
          rethrow;
        }
      }
    }
    return _app!;
  }

  /// Single shared FirebaseDatabase instance used across the ENTIRE application.
  /// Uses FirebaseDatabase.instance uniformly so every call throughout the app
  /// resolves through the exact same singleton database instance and format.
  static FirebaseDatabase get db {
    return _db ??= FirebaseDatabase.instance;
  }

  /// Root database reference helper
  static DatabaseReference get ref => db.ref();
}

/// Global shared database instance export
FirebaseDatabase get db => FirebaseService.db;
