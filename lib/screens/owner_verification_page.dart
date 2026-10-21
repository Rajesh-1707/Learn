import 'package:flutter/material.dart';

import '../services/owner_service.dart';
import '../widgets/glass.dart';

class OwnerVerificationPage extends StatefulWidget {
  const OwnerVerificationPage({super.key});
  @override
  State<OwnerVerificationPage> createState() => _OwnerVerificationPageState();
}

class _OwnerVerificationPageState extends State<OwnerVerificationPage> {
  final _owner = OwnerService();
  bool _loading = true;
  List<Map<String, dynamic>> _pending = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rows = await _owner.listUsers(limit: 100);
      if (!mounted) return;
      setState(() {
        _pending = rows.where((row) => row['verified_gender'] != true).toList();
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _verify(String id, bool verified) async {
    try {
      await _owner.setGenderVerified(id, verified);
      await _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update verification')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Verification queue'),
      backgroundColor: Colors.transparent,
      foregroundColor: Colors.white,
      elevation: 0,
    ),
    extendBodyBehindAppBar: true,
    body: GlassBackground(
      child: SafeArea(
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: Colors.white),
              )
            : _pending.isEmpty
            ? const Center(
                child: Text(
                  'No profiles are waiting for verification.',
                  style: TextStyle(color: Colors.white70),
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 72, 16, 20),
                itemCount: _pending.length,
                itemBuilder: (context, index) {
                  final row = _pending[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: GlassCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            '${row['full_name'] ?? 'User'} · ${row['gender'] ?? 'Gender not set'}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '${row['city'] ?? ''}${row['state'] == null ? '' : ', ${row['state']}'}',
                            style: const TextStyle(color: Colors.white70),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: TextButton(
                                  onPressed: () =>
                                      _verify('${row['id']}', false),
                                  child: const Text('Decline'),
                                ),
                              ),
                              Expanded(
                                child: GlassButton(
                                  label: 'Verify',
                                  onPressed: () =>
                                      _verify('${row['id']}', true),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    ),
  );
}
