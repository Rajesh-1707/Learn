import 'package:flutter/material.dart';

import '../services/pricing_service.dart';
import '../utils/money.dart';
import '../widgets/glass.dart';

class OwnerPricingPage extends StatefulWidget {
  const OwnerPricingPage({super.key});

  @override
  State<OwnerPricingPage> createState() => _OwnerPricingPageState();
}

class _OwnerPricingPageState extends State<OwnerPricingPage> {
  final _pricing = PricingService();
  final _controllers = <String, TextEditingController>{};
  bool _loading = true;
  final _saving = <String>{};
  Map<String, DateTime?> _updated = {};
  Object? _error;

  static const _definitions = <(String, String, String, bool)>[
    ('audio_min_paise', 'Audio minimum', 'paise', true),
    ('video_min_paise', 'Video minimum', 'paise', true),
    ('default_earner_percent', 'Standard earner share', '%', false),
    ('custom_earner_percent', 'Custom rate earner share', '%', false),
    ('chat_per_day_paise', 'Chat price per day', 'paise', true),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait<Object>([
        _pricing.fetchSettings(),
        _pricing.fetchSettingUpdates(),
      ]);
      final values = results[0] as Map<String, int>;
      if (!mounted) return;
      setState(() {
        _updated = results[1] as Map<String, DateTime?>;
        for (final entry in values.entries) {
          _controllers.putIfAbsent(entry.key, TextEditingController.new).text =
              '${entry.value}';
        }
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _save(String key, bool isPaise, String title) async {
    final controller = _controllers[key]!;
    final value = int.tryParse(controller.text.trim());
    if (value == null ||
        value < (isPaise ? 1 : 0) ||
        (!isPaise && value > 100)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isPaise
                ? 'Enter a positive amount in paise'
                : 'Enter a percentage from 0 to 100',
          ),
        ),
      );
      return;
    }
    setState(() => _saving.add(key));
    try {
      await _pricing.setSetting(key, value);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$title saved')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not save $title: $e')));
    } finally {
      if (mounted) setState(() => _saving.remove(key));
    }
  }

  Widget _settingCard(String key, String title, String unit, bool isPaise) {
    final controller = _controllers[key]!;
    final value = int.tryParse(controller.text) ?? 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              'Last updated: ${_updated[key]?.toString().substring(0, 16) ?? 'Not available'}',
              style: const TextStyle(color: Colors.white54, fontSize: 11),
            ),
            if (isPaise) ...[
              const SizedBox(height: 4),
              Text(
                'Current: ${formatRupees(value)}',
                style: const TextStyle(color: Colors.white70),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: unit == '%' ? 'Percentage' : 'Amount in paise',
                labelStyle: const TextStyle(color: Colors.white70),
                suffixText: unit,
                suffixStyle: const TextStyle(color: Colors.white70),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.16),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 12),
            GlassButton(
              label: _saving.contains(key) ? 'Saving...' : 'Save $title',
              isLoading: _saving.contains(key),
              onPressed: _saving.contains(key)
                  ? null
                  : () => _save(key, isPaise, title),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pricing'),
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
              : _error != null
              ? Center(
                  child: GlassCard(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Could not load pricing',
                          style: TextStyle(color: Colors.white),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '$_error',
                          style: const TextStyle(color: Colors.white70),
                        ),
                        TextButton(
                          onPressed: _load,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 72, 16, 24),
                  children: [
                    const Text(
                      'Platform pricing',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Minimum rates are in paise. Earner shares are percentages.',
                      style: TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 16),
                    for (final definition in _definitions)
                      _settingCard(
                        definition.$1,
                        definition.$2,
                        definition.$3,
                        definition.$4,
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}
