import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../viewmodels/auth_viewmodel.dart';

class LoginScreen extends StatefulWidget {
  final String? initialErrorMessage;
  const LoginScreen({super.key, this.initialErrorMessage});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  final _identifierController = TextEditingController();
  final _passwordController = TextEditingController();
  final _identifierFocusNode = FocusNode();
  final _passwordFocusNode = FocusNode();
  bool _isLoading = false;
  String? _errorMessage;
  bool _obscurePassword = true;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _errorMessage = widget.initialErrorMessage;
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnimation = CurvedAnimation(parent: _fadeController, curve: Curves.easeOut);
    _fadeController.forward();
  }

  @override
  void dispose() {
    _identifierController.dispose();
    _passwordController.dispose();
    _identifierFocusNode.dispose();
    _passwordFocusNode.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  void _handleLogin(AuthViewModel authViewModel) async {
    setState(() => _errorMessage = null);

    if (_identifierController.text.isEmpty || _passwordController.text.isEmpty) {
      setState(() => _errorMessage = 'Please enter credentials');
      return;
    }

    setState(() => _isLoading = true);
    final error = await authViewModel.signIn(
      _identifierController.text.trim(),
      _passwordController.text.trim(),
    );

    if (!mounted) return;

    if (error != null) {
      setState(() {
        _isLoading = false;
        _errorMessage = error;
      });
    } else {
      setState(() => _isLoading = false);
      if (authViewModel.isAdmin) {
        Navigator.pushNamedAndRemoveUntil(
          context,
          '/dashboard',
          (route) => false,
        );
      } else {
        setState(() => _errorMessage = 'Access denied. This portal is for administrators only.');
        await authViewModel.signOut();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authViewModel = Provider.of<AuthViewModel>(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth > 800;

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: isDesktop
              ? const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFFFFF5F2),
                    Color(0xFFFAFAFA),
                    Color(0xFFF0F9F8),
                  ],
                )
              : null,
          color: isDesktop ? null : AppTheme.backgroundWhite,
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: isDesktop ? 40 : 24,
              vertical: 24,
            ),
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Logo & branding
                    _buildHeader(isDesktop),
                    const SizedBox(height: 32),

                    // Login card
                    Container(
                      padding: EdgeInsets.all(isDesktop ? 40 : 24),
                      decoration: isDesktop
                          ? BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(24),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.06),
                                  blurRadius: 30,
                                  offset: const Offset(0, 10),
                                ),
                                BoxShadow(
                                  color: AppTheme.primaryOrange.withValues(alpha: 0.05),
                                  blurRadius: 60,
                                  offset: const Offset(0, 20),
                                ),
                              ],
                            )
                          : null,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (isDesktop) ...[
                            const Text(
                              'Admin Login',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Sign in to access the admin dashboard',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            const SizedBox(height: 28),
                          ],

                          // Email / Username field
                          TextField(
                            controller: _identifierController,
                            focusNode: _identifierFocusNode,
                            autofocus: true,
                            keyboardType: TextInputType.text,
                            textInputAction: TextInputAction.next,
                            onChanged: (_) => setState(() => _errorMessage = null),
                            onSubmitted: (_) => _passwordFocusNode.requestFocus(),
                            decoration: InputDecoration(
                              labelText: 'Email or Username',
                              prefixIcon: const Icon(Icons.person_outline),
                              errorText: _errorMessage != null ? '' : null,
                              errorStyle: const TextStyle(height: 0),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Password field
                          TextField(
                            controller: _passwordController,
                            focusNode: _passwordFocusNode,
                            obscureText: _obscurePassword,
                            textInputAction: TextInputAction.done,
                            onChanged: (_) => setState(() => _errorMessage = null),
                            onSubmitted: (_) => _handleLogin(authViewModel),
                            decoration: InputDecoration(
                              labelText: 'Password',
                              prefixIcon: const Icon(Icons.lock_outline),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                                  color: Colors.grey,
                                ),
                                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                              ),
                              error: _errorMessage != null
                                  ? Row(
                                      children: [
                                        const Icon(Icons.error_outline, size: 16, color: Colors.red),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            _errorMessage!,
                                            style: const TextStyle(color: Colors.red, fontSize: 12),
                                          ),
                                        ),
                                      ],
                                    )
                                  : null,
                            ),
                          ),

                          // Forgot password link (right-aligned)
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: () {
                                Navigator.pushNamed(context, '/forgot-password');
                              },
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                              ),
                              child: const Text(
                                'Forgot Password?',
                                style: TextStyle(fontSize: 13),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),

                          // Login button
                          SizedBox(
                            height: 50,
                            child: _isLoading
                                ? const Center(child: CircularProgressIndicator())
                                : ElevatedButton(
                                    onPressed: () => _handleLogin(authViewModel),
                                    child: const Text('Login'),
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(bool isDesktop) {
    return Column(
      children: [
        const Text(
          'Welcome to SAVE A PAW',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.bold,
            color: AppTheme.primaryOrange,
          ),
        ),
        if (isDesktop)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Admin Control Portal',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
            ),
          ),
      ],
    );
  }
}
