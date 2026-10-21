import 'package:supabase_flutter/supabase_flutter.dart';

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';

/// All Supabase auth + profile calls live here.
/// Screens must use this class and never call Supabase directly.
class AuthService {
  final SupabaseClient _client;

  AuthService([SupabaseClient? client])
    : _client = client ?? Supabase.instance.client;

  Session? get currentSession => _client.auth.currentSession;

  User? get currentUser => _client.auth.currentUser;

  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  Future<AuthResponse> signUp({
    required String email,
    required String password,
  }) {
    return _client.auth.signUp(email: email.trim(), password: password);
  }

  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) {
    return _client.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<void> signOut() => _client.auth.signOut();

  Future<void> sendPasswordResetEmail(String email) {
    return _client.auth.resetPasswordForEmail(
      email.trim(),
      redirectTo: AppConfig.passwordResetRedirectUrl,
    );
  }

  Future<void> resetPasswordWithCredential({
    required String email,
    required String newPassword,
    required String credential,
    required bool useDob,
  }) async {
    final response = await http
        .post(
          Uri.parse('${AppConfig.apiBaseUrl}/api/auth/reset-with-dob'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'email': email.trim(),
            'new_password': newPassword,
            if (useDob) 'dob': credential else 'recovery_code': credential,
          }),
        )
        .timeout(const Duration(seconds: 20));
    final decoded = jsonDecode(response.body);
    if (response.statusCode != 200 || decoded is! Map) {
      final message = decoded is Map && decoded['error'] is String
          ? decoded['error'] as String
          : 'Details do not match';
      throw Exception(message);
    }
  }

  Future<void> saveRecoveryCode(String code) async {
    final token = _client.auth.currentSession?.accessToken;
    if (token == null) {
      throw const AuthException('Not signed in. Please log in again.');
    }
    final response = await http
        .post(
          Uri.parse('${AppConfig.apiBaseUrl}/api/auth/set-recovery-code'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'recovery_code': code}),
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw Exception('Could not save your recovery code. Please try again.');
    }
  }

  Future<void> updatePassword(String password) async {
    await _client.auth.updateUser(UserAttributes(password: password));
    final token = _client.auth.currentSession?.accessToken;
    if (token == null) {
      throw const AuthException(
        'Your session expired. Please request a new reset email.',
      );
    }
    final response = await http
        .post(
          Uri.parse('${AppConfig.apiBaseUrl}/api/auth/mark-password-reset'),
          headers: {'Authorization': 'Bearer $token'},
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw Exception('Could not complete password reset. Please try again.');
    }
  }

  Future<Map<String, dynamic>?> getMyProfile() async {
    final user = _client.auth.currentUser;
    if (user == null) return null;
    final row = await _client
        .from('profiles')
        .select(
          'id, full_name, gender, native_language, avatar_url, role, dob, city, state',
        )
        .eq('id', user.id)
        .maybeSingle();
    if (row == null) return null;
    return Map<String, dynamic>.from(row as Map);
  }

  Future<void> saveProfile({
    required String fullName,
    required String gender,
    required String nativeLanguage,
    required DateTime dob,
    required String city,
    required String state,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Not signed in. Please log in again.');
    }
    await _client
        .from('profiles')
        .update({
          'full_name': fullName.trim(),
          'gender': gender,
          'native_language': nativeLanguage,
          'dob': dob.toIso8601String().split('T').first,
          'city': city.trim(),
          'state': state,
        })
        .eq('id', user.id);
  }

  Future<void> updateNativeLanguage(String language) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Not signed in. Please log in again.');
    }
    await _client
        .from('profiles')
        .update({'native_language': language.trim()})
        .eq('id', user.id);
  }

  /// A profile counts as complete when these three are non-empty.
  static bool isProfileComplete(Map<String, dynamic>? profile) {
    if (profile == null) return false;
    final name = (profile['full_name'] as String?)?.trim() ?? '';
    final gender = (profile['gender'] as String?)?.trim() ?? '';
    final lang = (profile['native_language'] as String?)?.trim() ?? '';
    final city = (profile['city'] as String?)?.trim() ?? '';
    final state = (profile['state'] as String?)?.trim() ?? '';
    final dob = (profile['dob'] as String?)?.trim() ?? '';
    return name.isNotEmpty &&
        gender.isNotEmpty &&
        lang.isNotEmpty &&
        city.isNotEmpty &&
        state.isNotEmpty &&
        dob.isNotEmpty;
  }

  /// Converts Supabase / network errors into friendly UI text.
  static String friendlyMessage(Object error) {
    final raw = error is AuthException
        ? error.message
        : error.toString().replaceFirst('Exception: ', '');
    final lower = raw.toLowerCase();
    if (lower.contains('invalid login credentials') ||
        lower.contains('invalid_credentials')) {
      return 'Wrong email or password';
    }
    if (lower.contains('user already registered') ||
        lower.contains('already registered') ||
        lower.contains('email already') ||
        lower.contains('user already exists')) {
      return 'This email already has an account. Please log in.';
    }
    if (lower.contains('email not confirmed') ||
        lower.contains('email_not_confirmed')) {
      return 'Please confirm your email first, then log in.';
    }
    if (lower.contains('rate limit') ||
        lower.contains('too many') ||
        lower.contains('over_email_send_rate_limit') ||
        lower.contains('over_request_rate_limit') ||
        lower.contains('429')) {
      return 'Too many attempts. Please wait a few minutes.';
    }
    if (lower.contains('socketexception') ||
        lower.contains('failed host') ||
        lower.contains('network') ||
        lower.contains('connection refused') ||
        lower.contains('no internet') ||
        lower.contains('clientexception')) {
      return 'No internet connection. Please check and try again.';
    }
    return 'Something went wrong. Please try again.';
  }
}
