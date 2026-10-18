import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/auth_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: 'https://cjggkmwsxssyikrpksvr.supabase.co',
    publishableKey: 'sb_publishable_CSqQxDGxrl4N_6CVuRVo9w_iPVTd2_-',
  );
  runApp(const SpeakEarnApp());
}

class SpeakEarnApp extends StatelessWidget {
  const SpeakEarnApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SpeakEarn',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: const AuthGate(),
    );
  }
}
