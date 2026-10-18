import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/auth_service.dart';
import '../widgets/glass.dart';
import 'home_page.dart';
import 'login_page.dart';
import 'profile_setup_page.dart';

/// Routes: no session -> LoginPage, session + incomplete profile ->
/// ProfileSetupPage, otherwise HomePage.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final AuthService _auth = AuthService();
  int _profileVersion = 0;

  void refreshProfile() {
    if (!mounted) return;
    setState(() => _profileVersion++);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: _auth.authStateChanges,
      builder: (context, snapshot) {
        final session = _auth.currentSession;
        if (snapshot.connectionState == ConnectionState.waiting &&
            session == null) {
          return const GlassLoading(message: 'Checking session...');
        }
        if (session == null) {
          return const LoginPage();
        }
        return FutureBuilder<Map<String, dynamic>?>(
          key: ValueKey('$_profileVersion ${session.user.id}'),
          future: _auth.getMyProfile(),
          builder: (context, profileSnap) {
            if (profileSnap.connectionState == ConnectionState.waiting) {
              return const GlassLoading(message: 'Loading profile...');
            }
            final profile = profileSnap.data;
            if (!AuthService.isProfileComplete(profile)) {
              return ProfileSetupPage(onSaved: refreshProfile);
            }
            return HomePage(profile: profile);
          },
        );
      },
    );
  }
}
