import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../viewmodels/auth_viewmodel.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  String _selectedRole = 'Adopter';
  bool _isLoading = false;
  String? _errorMessage;
  bool _obscurePassword = true;

  // Password requirement states
  bool _hasMinLength = false;
  bool _hasLetter = false;
  bool _hasNumberOrSymbol = false;

  final List<String> _roles = [
    'Adopter',
    'Foster',
    'Volunteer',
    'Rescue Partner',
  ];

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _onFieldChanged() {
    if (_errorMessage != null) {
      setState(() => _errorMessage = null);
    }
  }

  void _checkPassword(String value) {
    setState(() {
      _hasMinLength = value.length >= 8;
      _hasLetter = value.contains(RegExp(r'[A-Z]'));
      _hasNumberOrSymbol = value.contains(RegExp(r'[0-9!@#$%^&*(),.?":{}|<>]'));
      _onFieldChanged();
    });
  }

  @override
  Widget build(BuildContext context) {
    final authViewModel = Provider.of<AuthViewModel>(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth > 800;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Account'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.black,
      ),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: isDesktop
              ? const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFFFF5F2), Color(0xFFFAFAFA), Color(0xFFF0F9F8)],
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
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Container(
                padding: EdgeInsets.all(isDesktop ? 40 : 0),
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
                        ],
                      )
                    : null,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.pets, size: 50, color: AppTheme.primaryOrange),
                    const SizedBox(height: 16),
                    const Text(
                      'Join SAVEAPAW',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Help us save more lives',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                    const SizedBox(height: 32),

                    // Name row
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _firstNameController,
                            textInputAction: TextInputAction.next,
                            onChanged: (_) => _onFieldChanged(),
                            decoration: const InputDecoration(labelText: 'First Name'),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextField(
                            controller: _lastNameController,
                            textInputAction: TextInputAction.next,
                            onChanged: (_) => _onFieldChanged(),
                            decoration: const InputDecoration(labelText: 'Last Name'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Username
                    TextField(
                      controller: _usernameController,
                      textInputAction: TextInputAction.next,
                      onChanged: (_) => _onFieldChanged(),
                      decoration: InputDecoration(
                        labelText: 'Username',
                        prefixIcon: const Icon(Icons.alternate_email),
                        hintText: 'Choose a unique username',
                        errorText: _errorMessage != null && _errorMessage!.contains('username') ? '' : null,
                        errorStyle: const TextStyle(height: 0),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Email
                    TextField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      onChanged: (_) => _onFieldChanged(),
                      decoration: InputDecoration(
                        labelText: 'Email',
                        prefixIcon: const Icon(Icons.email_outlined),
                        errorText: _errorMessage != null && _errorMessage!.contains('email') ? '' : null,
                        errorStyle: const TextStyle(height: 0),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Password
                    TextField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      textInputAction: TextInputAction.done,
                      onChanged: _checkPassword,
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
                    const SizedBox(height: 12),

                    // Password requirements
                    _buildRequirementRow('Minimum 8 characters', _hasMinLength),
                    _buildRequirementRow('At least 1 capital letter', _hasLetter),
                    _buildRequirementRow('At least 1 number or symbol', _hasNumberOrSymbol),
                    const SizedBox(height: 24),

                    // Role dropdown
                    const Text(
                      'Select Your Role',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: _errorMessage != null ? Colors.red.shade400 : Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedRole,
                          isExpanded: true,
                          items: _roles.map((String role) {
                            return DropdownMenuItem<String>(
                              value: role,
                              child: Text(role),
                            );
                          }).toList(),
                          onChanged: (String? newValue) {
                            if (newValue != null) {
                              _onFieldChanged();
                              setState(() => _selectedRole = newValue);
                            }
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Sign up button
                    SizedBox(
                      height: 50,
                      child: _isLoading
                          ? const Center(child: CircularProgressIndicator())
                          : ElevatedButton(
                              onPressed: () async {
                                setState(() => _errorMessage = null);

                                if (_firstNameController.text.isEmpty ||
                                    _lastNameController.text.isEmpty ||
                                    _usernameController.text.isEmpty ||
                                    _emailController.text.isEmpty ||
                                    _passwordController.text.isEmpty) {
                                  setState(() => _errorMessage = 'Please fill in all fields');
                                  return;
                                }

                                if (!_hasMinLength || !_hasLetter || !_hasNumberOrSymbol) {
                                  setState(() => _errorMessage = 'Please meet all password requirements');
                                  return;
                                }

                                setState(() => _isLoading = true);
                                final error = await authViewModel.signUp(
                                  email: _emailController.text.trim(),
                                  password: _passwordController.text.trim(),
                                  firstName: _firstNameController.text.trim(),
                                  lastName: _lastNameController.text.trim(),
                                  username: _usernameController.text.trim(),
                                  role: _selectedRole,
                                );

                                if (error != null) {
                                  setState(() {
                                    _isLoading = false;
                                    _errorMessage = error;
                                  });
                                } else {
                                  if (context.mounted) {
                                    setState(() => _isLoading = false);
                                    showDialog(
                                      context: context,
                                      barrierDismissible: false,
                                      builder: (context) => AlertDialog(
                                        title: const Text('Verify Your Email'),
                                        content: const Text(
                                            'A verification email has been sent to your inbox. Please verify your account before logging in.'),
                                        actions: [
                                          TextButton(
                                            onPressed: () {
                                              Navigator.pop(context); // Close dialog
                                              Navigator.pop(context); // Go back to Login
                                            },
                                            child: const Text('OK'),
                                          ),
                                        ],
                                      ),
                                    );
                                  }
                                }
                              },
                              child: const Text('Sign Up'),
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

  Widget _buildRequirementRow(String text, bool isMet) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(
            isMet ? Icons.check_circle : Icons.circle_outlined,
            size: 16,
            color: isMet ? Colors.green : Colors.grey,
          ),
          const SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              color: isMet ? Colors.green : Colors.grey,
            ),
          ),
        ],
      ),
    );
  }
}
