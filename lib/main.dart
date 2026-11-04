import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'theme/app_theme.dart';
import 'viewmodels/auth_viewmodel.dart';
import 'viewmodels/user_management_viewmodel.dart';
import 'views/login_screen.dart';
import 'views/admin_screen.dart';
import 'views/signup_screen.dart';
import 'views/forgot_password_screen.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  usePathUrlStrategy();
  runApp(const FirebaseInitGate());
}

class FirebaseInitGate extends StatefulWidget {
  const FirebaseInitGate({super.key});

  @override
  State<FirebaseInitGate> createState() => _FirebaseInitGateState();
}

class _FirebaseInitGateState extends State<FirebaseInitGate> {
  bool _initialized = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }

      // Brief delay to show splash
      await Future.delayed(const Duration(seconds: 1));

      if (mounted) setState(() => _initialized = true);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.red),
                const SizedBox(height: 16),
                const Text('Initialization Error', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (!_initialized) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        home: const _SplashView(),
      );
    }

    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthViewModel>(
          create: (_) => AuthViewModel()..initialize(),
        ),
        ChangeNotifierProvider<UserManagementViewModel>(
          create: (_) => UserManagementViewModel(),
        ),
      ],
      child: const SaveAPawAdminApp(),
    );
  }
}

/// Enables smooth click-and-drag scrolling for mouse, trackpad, touch, and stylus across web and desktop
class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      };
}

class SaveAPawAdminApp extends StatelessWidget {
  const SaveAPawAdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SAVEAPAW Admin',
      debugShowCheckedModeBanner: false,
      scrollBehavior: const AppScrollBehavior(),
      theme: AppTheme.lightTheme,
      initialRoute: '/',
      onGenerateRoute: (settings) {
        final uri = Uri.tryParse(settings.name ?? '') ?? Uri(path: '/');
        final path = uri.path;

        if (path == '/dashboard') {
          return MaterialPageRoute(
            settings: settings,
            builder: (_) => const _AdminAuthGuard(),
          );
        }

        if (path == '/signup') {
          return MaterialPageRoute(
            settings: settings,
            builder: (_) => const SignUpScreen(),
          );
        }

        if (path == '/forgot-password') {
          return MaterialPageRoute(
            settings: settings,
            builder: (_) => const ForgotPasswordScreen(),
          );
        }

        if (path == '/login') {
          return MaterialPageRoute(
            settings: settings,
            builder: (_) => _LoginAuthGuard(
              initialErrorMessage: settings.arguments as String?,
            ),
          );
        }

        // Default or root ('/')
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => const _RootAuthGate(),
        );
      },
    );
  }
}

class _RootAuthGate extends StatelessWidget {
  const _RootAuthGate();

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthViewModel>(context);

    if (auth.isAuthChecking) {
      return const _SplashView();
    }

    if (auth.isLoggedIn && auth.isAdmin) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          Navigator.pushReplacementNamed(context, '/dashboard');
        }
      });
      return const _SplashView();
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.mounted) {
        Navigator.pushReplacementNamed(context, '/login');
      }
    });
    return const _SplashView();
  }
}

class _AdminAuthGuard extends StatelessWidget {
  const _AdminAuthGuard();

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthViewModel>(context);

    if (auth.isAuthChecking) {
      return const _SplashView();
    }

    if (auth.isLoggedIn && auth.isAdmin) {
      return const AdminScreen();
    }

    // Not logged in or not admin
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.mounted) {
        Navigator.pushReplacementNamed(
          context,
          '/login',
          arguments: 'Please sign in to access the admin portal.',
        );
      }
    });

    return const _SplashView();
  }
}

class _LoginAuthGuard extends StatelessWidget {
  final String? initialErrorMessage;
  const _LoginAuthGuard({this.initialErrorMessage});

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthViewModel>(context);

    if (auth.isAuthChecking) {
      return const _SplashView();
    }

    // If already logged in as admin, redirect to /dashboard
    if (auth.isLoggedIn && auth.isAdmin) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          Navigator.pushReplacementNamed(context, '/dashboard');
        }
      });
      return const _SplashView();
    }

    return LoginScreen(initialErrorMessage: initialErrorMessage);
  }
}

/// Simple splash view shown while Firebase initializes.
class _SplashView extends StatelessWidget {
  const _SplashView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundWhite,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'SAVE A PAW',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: AppTheme.primaryOrange),
            ),
            const SizedBox(height: 8),
            Text(
              'Admin Portal',
              style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 32),
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.5, color: AppTheme.primaryOrange),
            ),
          ],
        ),
      ),
    );
  }
}
