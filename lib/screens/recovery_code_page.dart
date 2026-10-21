import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../widgets/glass.dart';

class RecoveryCodePage extends StatefulWidget {
  final String code;
  const RecoveryCodePage({super.key, required this.code});

  @override
  State<RecoveryCodePage> createState() => _RecoveryCodePageState();
}

class _RecoveryCodePageState extends State<RecoveryCodePage> {
  bool _saved = false;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: GlassBackground(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Save your recovery code',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'This code is shown once. Keep it somewhere safe so you can recover your account.',
                  style: TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 22),
                SelectableText(
                  widget.code,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 4,
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    await Clipboard.setData(ClipboardData(text: widget.code));
                    if (!mounted) return;
                    messenger.showSnackBar(
                      const SnackBar(content: Text('Recovery code copied')),
                    );
                  },
                  icon: const Icon(Icons.copy, color: Colors.white),
                  label: const Text(
                    'Copy',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
                const SizedBox(height: 12),
                CheckboxListTile(
                  value: _saved,
                  contentPadding: EdgeInsets.zero,
                  activeColor: Colors.white,
                  checkColor: Colors.deepPurple,
                  title: const Text(
                    'I saved it',
                    style: TextStyle(color: Colors.white),
                  ),
                  onChanged: (value) => setState(() => _saved = value ?? false),
                ),
                const SizedBox(height: 8),
                GlassButton(
                  label: 'Continue',
                  onPressed: _saved ? () => Navigator.pop(context, true) : null,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
