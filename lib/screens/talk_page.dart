import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/wallet_models.dart';
import '../services/auth_service.dart';
import '../services/call_service.dart';
import '../services/pricing_service.dart';
import '../services/wallet_service.dart';
import '../utils/money.dart';
import '../widgets/glass.dart';
import 'call_page.dart';
import 'friends_page.dart';
import 'wallet_page.dart';

class TalkPage extends StatefulWidget {
  final Map<String, dynamic>? profile;
  const TalkPage({super.key, this.profile});

  @override
  State<TalkPage> createState() => _TalkPageState();
}

class _TalkPageState extends State<TalkPage> {
  final _calls = CallService();
  final _wallet = WalletService();
  final _pricing = PricingService();
  Timer? _pollTimer;
  Timer? _timeoutTimer;
  String _gender = 'any';
  String _mediaType = 'audio';
  int _audioRate = 1000;
  int _videoRate = 2000;
  int _balancePaise = 0;
  bool _loading = true;
  bool _searching = false;
  String? _error;
  String? _rejoinCallId;

  int get _rate => _mediaType == 'video' ? _videoRate : _audioRate;
  int get _minutes => _rate <= 0 ? 0 : _balancePaise ~/ _rate;
  bool get _videoSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _timeoutTimer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait<Object?>([
        _pricing.fetchSettings(),
        _wallet.fetchWallet(),
        _calls.currentCall(),
      ]);
      if (!mounted) return;
      final settings = results[0] as Map<String, int>;
      final wallet = results[1] as WalletRow;
      final current = results[2] as Map<String, dynamic>?;
      setState(() {
        _audioRate = settings['audio_min_paise'] ?? 1000;
        _videoRate = settings['video_min_paise'] ?? 2000;
        _balancePaise = wallet.balancePaise;
        _rejoinCallId = current?['call_id']?.toString();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = AuthService.friendlyMessage(e);
      });
    }
  }

  Future<void> _openCall(String callId, [Map<String, dynamic>? row]) async {
    _cancelTimers();
    if (!mounted) return;
    var media =
        row?['media']?.toString() ??
        row?['media_type']?.toString() ??
        _mediaType;
    try {
      media = await _calls.chooseCallMedia(callId, _mediaType);
    } catch (_) {
      try {
        media = await _calls.callMedia(callId) ?? media;
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _searching = false;
      _rejoinCallId = null;
    });
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CallPage(
          profile: widget.profile,
          callId: callId,
          topicId: row?['topic_id']?.toString(),
          topicTitle: row?['topic_title']?.toString(),
          mediaType: media,
          ratePaise: media == 'video' ? _videoRate : _audioRate,
        ),
      ),
    );
    if (mounted) await _refresh();
  }

  Future<void> _joinQueue() async {
    if (_searching || _balancePaise < _rate) return;
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final callId = await _calls.joinQueue(_gender, null);
      if (!mounted) return;
      if (callId != null) {
        await _openCall(callId);
        return;
      }
      _pollTimer = Timer.periodic(
        const Duration(seconds: 2),
        (_) => _pollCurrentCall(),
      );
      _timeoutTimer = Timer(const Duration(seconds: 60), _searchExpired);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _error = AuthService.friendlyMessage(e);
      });
    }
  }

  Future<void> _pollCurrentCall() async {
    if (!mounted || !_searching) return;
    try {
      final row = await _calls.currentCall();
      if (!mounted || !_searching || row == null) return;
      final id = row['call_id']?.toString();
      if (id != null && id.isNotEmpty) await _openCall(id, row);
    } catch (_) {}
  }

  Future<void> _searchExpired() async {
    if (!_searching) return;
    _cancelTimers();
    try {
      await _calls.leaveQueue();
    } catch (_) {}
    if (!mounted) return;
    setState(() => _searching = false);
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('No one is available')));
  }

  Future<void> _cancelSearch() async {
    _cancelTimers();
    try {
      await _calls.leaveQueue();
    } catch (_) {}
    if (mounted) setState(() => _searching = false);
  }

  void _cancelTimers() {
    _pollTimer?.cancel();
    _timeoutTimer?.cancel();
    _pollTimer = null;
    _timeoutTimer = null;
  }

  Future<void> _openWallet() async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const WalletPage()));
    if (mounted) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final short = _balancePaise < _rate;
    return GlassBackground(
      child: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 100),
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Talk',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const FriendsPage()),
                    ),
                    icon: const Icon(
                      Icons.people_alt_outlined,
                      color: Colors.white,
                    ),
                    label: const Text(
                      'Friends',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SegmentedButton<String>(
                segments: [
                  const ButtonSegment(
                    value: 'audio',
                    label: Text('Audio'),
                    icon: Icon(Icons.mic),
                  ),
                  ButtonSegment(
                    value: 'video',
                    label: Text('Video'),
                    icon: Icon(Icons.videocam),
                    enabled: _videoSupported,
                  ),
                ],
                selected: {_mediaType},
                onSelectionChanged: (value) =>
                    setState(() => _mediaType = value.first),
                style: ButtonStyle(
                  foregroundColor: const WidgetStatePropertyAll(Colors.white),
                  backgroundColor: WidgetStateProperty.resolveWith(
                    (states) => states.contains(WidgetState.selected)
                        ? Colors.white24
                        : Colors.white10,
                  ),
                ),
              ),
              if (!_videoSupported)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                    'Video calls are currently available on Android.',
                    style: TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                ),
              const SizedBox(height: 16),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(28),
                  child: Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
                )
              else if (_error != null)
                GlassCard(
                  child: Column(
                    children: [
                      Text(
                        _error!,
                        style: const TextStyle(color: Colors.white70),
                        textAlign: TextAlign.center,
                      ),
                      TextButton(
                        onPressed: _refresh,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              else ...[
                _choice('any', 'Anyone', Icons.public),
                _choice('female', 'Female', Icons.female),
                _choice('male', 'Male', Icons.male),
                const SizedBox(height: 12),
                GlassCard(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      _summary('Your wallet', formatRupees(_balancePaise)),
                      const Divider(color: Colors.white24),
                      _summary('Rate per minute', formatRupees(_rate)),
                      const SizedBox(height: 4),
                      Text(
                        'Minutes you can talk: $_minutes',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                if (short && !_searching && _rejoinCallId == null) ...[
                  GlassButton(label: 'Start', onPressed: null),
                  const SizedBox(height: 6),
                  const Text(
                    'Add money to start a call.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 8),
                  GlassButton(label: 'Add money', onPressed: _openWallet),
                ] else if (_rejoinCallId != null)
                  GlassButton(
                    label: 'Rejoin call',
                    onPressed: () => _openCall(_rejoinCallId!),
                  )
                else if (_searching)
                  GlassButton(label: 'Cancel search', onPressed: _cancelSearch)
                else
                  GlassButton(label: 'Start', onPressed: _joinQueue),
              ],
              const SizedBox(height: 20),
              const Text(
                'Never share your phone number, address, or financial information with strangers.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white60, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _choice(String value, String label, IconData icon) {
    final selected = _gender == value;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () => setState(() => _gender = value),
        child: GlassCard(
          padding: const EdgeInsets.all(18),
          child: Column(
            children: [
              Row(
                children: [
                  Icon(icon, color: Colors.white, size: 28),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    '${formatRupees(_rate)}/min',
                    style: const TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    color: Colors.white,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Wallet ${formatRupees(_balancePaise)} · Minutes you can talk: $_minutes',
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _summary(String title, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: const TextStyle(color: Colors.white70)),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}
