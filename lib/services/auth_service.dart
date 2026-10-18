import 'package:supabase_flutter/supabase_flutter.dart';

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
    return _client.auth.signUp(
      email: email.trim(),
      password: password,
    );
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

  /// Step 1 of code-based reset: sends the 6-digit recovery code.
  Future<void> sendResetCode(String email) {
    return _client.auth.resetPasswordForEmail(email.trim());
  }

  /// Steps 2-3: verify the code, set the new password, then sign out
  /// so the user logs in fresh with the new password.
  Future<void> verifyResetCodeAndSetPassword({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    final trimmedEmail = email.trim();
    final trimmedCode = code.trim();
    await _client.auth.verifyOTP(
      type: OtpType.recovery,
      email: trimmedEmail,
      token: trimmedCode,
    );
    await _client.auth.updateUser(
      UserAttributes(password: newPassword),
    );
    await _client.auth.signOut();
  }

  Future<Map<String, dynamic>?> getMyProfile() async {
    final user = _client.auth.currentUser;
    if (user == null) return null;
    final row = await _client
        .from('profiles')
        .select('id, full_name, gender, native_language, avatar_url, role')
        .eq('id', user.id)
        .maybeSingle();
    if (row == null) return null;
    return Map<String, dynamic>.from(row as Map);
  }

  Future<void> saveProfile({
    required String fullName,
    required String gender,
    required String nativeLanguage,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Not signed in. Please log in again.');
    }
    await _client.from('profiles').update({
      'full_name': fullName.trim(),
      'gender': gender,
      'native_language': nativeLanguage,
    }).eq('id', user.id);
  }

  Future<void> updateNativeLanguage(String language) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Not signed in. Please log in again.');
    }
    await _client.from('profiles').update(
      {'native_language': language.trim()},
    ).eq('id', user.id);
  }

  /// A profile counts as complete when these three are non-empty.
  static bool isProfileComplete(Map<String, dynamic>? profile) {
    if (profile == null) return false;
    final name = (profile['full_name'] as String?)?.trim() ?? '';
    final gender = (profile['gender'] as String?)?.trim() ?? '';
    final lang = (profile['native_language'] as String?)?.trim() ?? '';
    return name.isNotEmpty && gender.isNotEmpty && lang.isNotEmpty;
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
