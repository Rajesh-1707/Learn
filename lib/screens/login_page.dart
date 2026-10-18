import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../widgets/glass.dart';
import 'forgot_password_page.dart';

class LoginPage extends StatefulWidget {
  final String? notice;
  const LoginPage({super.key, this.notice});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final AuthService _auth = AuthService();
  bool _isLogin = true;
  bool _isLoading = false;
  bool _obscure = true;
  bool _acceptedTerms = false;

  @override
  void initState() {
    super.initState();
    if (widget.notice != null && widget.notice!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(widget.notice!)));
      });
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  static final RegExp _emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _toggleMode() {
    setState(() {
      _isLogin = !_isLogin;
    });
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (!_emailRe.hasMatch(email)) {
      _snack('Please enter a valid email address');
      return;
    }
    if (_isLogin && password.isEmpty) {
      _snack('Please enter your password');
      return;
    }
    if (!_isLogin && password.length < 8) {
      _snack('Password must be at least 8 characters');
      return;
    }
    if (!_isLogin && !_acceptedTerms) {
      _snack('Please accept the Terms and Privacy Policy');
      return;
    }
    setState(() => _isLoading = true);
    try {
      if (_isLogin) {
        await _auth.signIn(email: email, password: password);
      } else {
        final res = await _auth.signUp(email: email, password: password);
        if (!mounted) return;
        if (res.session == null) {
          _snack('Account created. Check your email to confirm, then log in.');
          setState(() {
            _isLogin = true;
            _isLoading = false;
          });
          return;
        }
      }
    } catch (e) {
      _snack(AuthService.friendlyMessage(e));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GlassBackground(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: GlassCard(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.mic, size: 80, color: Colors.white),
                  const SizedBox(height: 16),
                  const Text(
                    'SpeakEarn',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Speak English. Earn money.',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 24),
                  GlassField(
                    controller: _emailController,
                    hint: 'Email',
                    icon: Icons.email,
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 12),
                  GlassField(
                    controller: _passwordController,
                    hint: 'Password',
                    icon: Icons.lock,
                    obscure: _obscure,
                    textInputAction: TextInputAction.done,
                    suffixIcon: IconButton(
                      icon: Icon(
                          _obscure
                              ? Icons.visibility
                              : Icons.visibility_off,
                          color: Colors.white70),
                      onPressed: () =>
                          setState(() => _obscure = !_obscure),
                    ),
                  ),
                  if (!_isLogin) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Checkbox(
                          value: _acceptedTerms,
                          activeColor: Colors.white,
                          checkColor: Colors.deepPurple,
                          side:
                              const BorderSide(color: Colors.white70),
                          onChanged: (v) => setState(
                              () => _acceptedTerms = v ?? false),
                        ),
                        const Expanded(
                          child: Text(
                            'I am 18 or older and I accept the Terms and Privacy Policy',
                            style: TextStyle(
                                color: Colors.white70, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _isLoading
                          ? null
                          : () => Navigator.of(context).push(
                                MaterialPageRoute(
                                    builder: (_) =>
                                        const ForgotPasswordPage()),
                              ),
                      child: const Text(
                        'Forgot password?',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  GlassButton(
                    label: _isLogin ? 'Log in' : 'Create account',
                    isLoading: _isLoading,
                    onPressed: _isLoading ? null : _submit,
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _isLoading ? null : _toggleMode,
                    child: Text(
                      _isLogin
                          ? 'Create account instead'
                          : 'Already have an account? Log in',
                      style: const TextStyle(color: Colors.white70),
                    ),
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
