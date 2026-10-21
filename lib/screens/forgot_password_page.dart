import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../widgets/glass.dart';
import 'login_page.dart';

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _email = TextEditingController();
  final _credential = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _auth = AuthService();
  int _mode = 0; // Email, date of birth, recovery code.
  bool _busy = false;
  bool _sent = false;
  bool _hidePassword = true;
  bool _hideConfirm = true;
  DateTime? _dob;

  @override
  void dispose() {
    _email.dispose();
    _credential.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _sendEmail() async {
    final email = _email.text.trim();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      _message('Please enter a valid email address');
      return;
    }
    setState(() => _busy = true);
    try {
      await _auth.sendPasswordResetEmail(email);
      if (!mounted) return;
      setState(() => _sent = true);
    } catch (_) {
      if (!mounted) return;
      // Keep the same instruction for registered and unregistered addresses.
      setState(() => _sent = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resetWithDetails() async {
    final email = _email.text.trim();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      _message('Please enter a valid email address');
      return;
    }
    if (_mode == 1 && _dob == null) {
      _message('Please select your date of birth');
      return;
    }
    if (_mode == 2 &&
        !RegExp(r'^[A-Za-z0-9]{8}$').hasMatch(_credential.text.trim())) {
      _message('Enter your 8-character recovery code');
      return;
    }
    if (_password.text.length < 8) {
      _message('New password must be at least 8 characters');
      return;
    }
    if (_password.text != _confirm.text) {
      _message('Passwords do not match');
      return;
    }
    setState(() => _busy = true);
    try {
      final credential = _mode == 1
          ? '${_dob!.year.toString().padLeft(4, '0')}-${_dob!.month.toString().padLeft(2, '0')}-${_dob!.day.toString().padLeft(2, '0')}'
          : _credential.text.trim().toUpperCase();
      await _auth.resetPasswordWithCredential(
        email: email,
        newPassword: _password.text,
        credential: credential,
        useDob: _mode == 1,
      );
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) =>
              const LoginPage(notice: 'Password changed. Please log in.'),
        ),
        (_) => false,
      );
    } catch (error) {
      _message(error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _passwordFields() => Column(
    children: [
      GlassField(
        controller: _password,
        hint: 'New password (min 8)',
        icon: Icons.lock,
        obscure: _hidePassword,
        suffixIcon: IconButton(
          icon: Icon(
            _hidePassword ? Icons.visibility : Icons.visibility_off,
            color: Colors.white70,
          ),
          onPressed: () => setState(() => _hidePassword = !_hidePassword),
        ),
      ),
      const SizedBox(height: 12),
      GlassField(
        controller: _confirm,
        hint: 'Confirm new password',
        icon: Icons.lock_outline,
        obscure: _hideConfirm,
        suffixIcon: IconButton(
          icon: Icon(
            _hideConfirm ? Icons.visibility : Icons.visibility_off,
            color: Colors.white70,
          ),
          onPressed: () => setState(() => _hideConfirm = !_hideConfirm),
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reset password'),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
      ),
      extendBodyBehindAppBar: true,
      body: GlassBackground(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Forgot password',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Email',
                      hintStyle: const TextStyle(color: Colors.white70),
                      prefixIcon: const Icon(Icons.email, color: Colors.white),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.2),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_mode == 0) ...[
                    Text(
                      _sent
                          ? 'If an account uses this email, reset instructions are on the way. Open the link in the email to choose a new password.'
                          : 'We’ll email a secure password reset link.',
                      style: const TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 16),
                    GlassButton(
                      label: _sent
                          ? 'Send instructions again'
                          : 'Send reset instructions',
                      isLoading: _busy,
                      onPressed: _busy ? null : _sendEmail,
                    ),
                  ] else ...[
                    if (_mode == 1)
                      InkWell(
                        onTap: _busy
                            ? null
                            : () async {
                                final now = DateTime.now();
                                final selected = await showDatePicker(
                                  context: context,
                                  initialDate: DateTime(
                                    now.year - 18,
                                    now.month,
                                    now.day,
                                  ),
                                  firstDate: DateTime(1900),
                                  lastDate: now,
                                );
                                if (selected != null) {
                                  setState(() => _dob = selected);
                                }
                              },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 18,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.cake, color: Colors.white),
                              const SizedBox(width: 12),
                              Text(
                                _dob == null
                                    ? 'Date of birth'
                                    : '${_dob!.day}/${_dob!.month}/${_dob!.year}',
                                style: const TextStyle(color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      GlassField(
                        controller: _credential,
                        hint: '8-character recovery code',
                        icon: Icons.key,
                        textInputAction: TextInputAction.next,
                      ),
                    const SizedBox(height: 12),
                    _passwordFields(),
                    const SizedBox(height: 16),
                    GlassButton(
                      label: 'Change password',
                      isLoading: _busy,
                      onPressed: _busy ? null : _resetWithDetails,
                    ),
                  ],
                  const SizedBox(height: 12),
                  if (!_sent || _mode != 0)
                    Wrap(
                      alignment: WrapAlignment.center,
                      children: [
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => setState(() {
                                  _mode = 0;
                                  _sent = false;
                                }),
                          child: Text(
                            'Email reset',
                            style: TextStyle(color: Colors.white70),
                          ),
                        ),
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => setState(() {
                                  _mode = 1;
                                  _sent = false;
                                }),
                          child: Text(
                            _mode == 0
                                ? 'Use date of birth instead'
                                : 'Use date of birth',
                            style: TextStyle(color: Colors.white70),
                          ),
                        ),
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => setState(() {
                                  _mode = 2;
                                  _sent = false;
                                }),
                          child: const Text(
                            'Use recovery code',
                            style: TextStyle(color: Colors.white70),
                          ),
                        ),
                      ],
                    )
                  else
                    Wrap(
                      alignment: WrapAlignment.center,
                      children: [
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => setState(() => _mode = 1),
                          child: const Text(
                            'Use date of birth',
                            style: TextStyle(color: Colors.white70),
                          ),
                        ),
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => setState(() => _mode = 2),
                          child: const Text(
                            'Use recovery code',
                            style: TextStyle(color: Colors.white70),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
