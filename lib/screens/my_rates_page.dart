import 'package:flutter/material.dart';

import '../services/pricing_service.dart';
import '../utils/money.dart';
import '../widgets/glass.dart';

class MyRatesPage extends StatefulWidget {
  const MyRatesPage({super.key});

  @override
  State<MyRatesPage> createState() => _MyRatesPageState();
}

class _MyRatesPageState extends State<MyRatesPage> {
  final _pricing = PricingService();
  final _audio = TextEditingController();
  final _video = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  Object? _error;
  Map<String, int> _settings = {};
  bool _customAudio = false;
  bool _customVideo = false;
  int? _savedAudio;
  int? _savedVideo;

  int get _audioMin => _settings['audio_min_paise'] ?? 1000;
  int get _videoMin => _settings['video_min_paise'] ?? 2000;
  int get _defaultPercent => _settings['default_earner_percent'] ?? 10;
  int get _customPercent => _settings['custom_earner_percent'] ?? 50;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _audio.dispose();
    _video.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final values = await Future.wait<Object>([
        _pricing.fetchSettings(),
        _pricing.fetchOwnRates(),
      ]);
      final settings = values[0] as Map<String, int>;
      final rates = values[1] as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _settings = settings;
        _savedAudio = (rates['audio_rate_paise'] as num?)?.toInt();
        _savedVideo = (rates['video_rate_paise'] as num?)?.toInt();
        _customAudio = _savedAudio != null;
        _customVideo = _savedVideo != null;
        _audio.text = ((_savedAudio ?? _audioMin) / 100).round().toString();
        _video.text = ((_savedVideo ?? _videoMin) / 100).round().toString();
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

  int _paise(TextEditingController controller, int minimum) {
    final rupees = int.tryParse(controller.text.trim());
    return (rupees == null ? minimum : rupees * 100).clamp(minimum, 2147483647);
  }

  String _preview(TextEditingController controller, int minimum, bool custom) {
    final rate = custom ? _paise(controller, minimum) : minimum;
    final percent = custom ? _customPercent : _defaultPercent;
    return formatRupees(rate * percent ~/ 100);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final audio = _customAudio ? _paise(_audio, _audioMin) : null;
      final video = _customVideo ? _paise(_video, _videoMin) : null;
      await _pricing.setMyRates(audioPaise: audio, videoPaise: video);
      if (!mounted) return;
      setState(() {
        _savedAudio = audio;
        _savedVideo = video;
        _saving = false;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Rates saved')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not save rates: $e')));
    }
  }

  Widget _rateCard({
    required String title,
    required String description,
    required TextEditingController controller,
    required int minimum,
    required bool custom,
    required ValueChanged<bool> onCustomChanged,
  }) {
    final minRupees = (minimum / 100).ceilToDouble();
    final current = double.tryParse(controller.text) ?? minRupees;
    final max = current > minRupees + 500 ? current + 500 : minRupees + 500;
    return GlassCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(description, style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 12),
          Text(
            'Minimum: ${formatRupees(minimum)} / minute',
            style: const TextStyle(color: Colors.white70),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'Set a custom rate',
              style: TextStyle(color: Colors.white),
            ),
            subtitle: const Text(
              'Off uses the standard minimum rate',
              style: TextStyle(color: Colors.white60),
            ),
            value: custom,
            activeThumbColor: Colors.white,
            onChanged: onCustomChanged,
          ),
          if (custom) ...[
            Row(
              children: [
                const Text(
                  '₹',
                  style: TextStyle(color: Colors.white, fontSize: 20),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 120,
                  child: TextField(
                    controller: controller,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() {}),
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Per minute',
                      labelStyle: const TextStyle(color: Colors.white70),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.16),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            Slider(
              min: minRupees,
              max: max,
              value: current.clamp(minRupees, max),
              divisions: ((max - minRupees) * 4).round().clamp(1, 5000),
              label: '₹${current.toStringAsFixed(0)}',
              onChanged: (value) =>
                  setState(() => controller.text = value.round().toString()),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            'At ${formatRupees(custom ? _paise(controller, minimum) : minimum)}/min you earn ${_preview(controller, minimum, custom)} per minute (${custom ? _customPercent : _defaultPercent}%)',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My rates'),
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
                      'Choose your rates',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'You can use standard rates or set your own above the minimum.',
                      style: TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 16),
                    _rateCard(
                      title: 'Audio calls',
                      description: 'Audio rate',
                      controller: _audio,
                      minimum: _audioMin,
                      custom: _customAudio,
                      onCustomChanged: (v) => setState(() {
                        _customAudio = v;
                        if (v &&
                            (int.tryParse(_audio.text) ?? 0) * 100 <
                                _audioMin) {
                          _audio.text = (_audioMin / 100).ceil().toString();
                        }
                      }),
                    ),
                    const SizedBox(height: 12),
                    _rateCard(
                      title: 'Video calls',
                      description: 'Video rate',
                      controller: _video,
                      minimum: _videoMin,
                      custom: _customVideo,
                      onCustomChanged: (v) => setState(() {
                        _customVideo = v;
                        if (v &&
                            (int.tryParse(_video.text) ?? 0) * 100 <
                                _videoMin) {
                          _video.text = (_videoMin / 100).ceil().toString();
                        }
                      }),
                    ),
                    const SizedBox(height: 16),
                    GlassButton(
                      label: 'Save rates',
                      isLoading: _saving,
                      onPressed: _saving ? null : _save,
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
