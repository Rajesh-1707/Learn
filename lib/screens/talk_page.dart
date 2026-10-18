import 'dart:async';

import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/call_service.dart';
import '../services/wallet_service.dart';
import '../models/wallet_models.dart';
import '../utils/money.dart';
import '../widgets/glass.dart';
import 'call_page.dart';

class TalkPage extends StatefulWidget {
  final Map<String, dynamic>? profile;
  const TalkPage({super.key, this.profile});

  @override
  State<TalkPage> createState() => _TalkPageState();
}

class _TalkPageState extends State<TalkPage> {
  final _calls = CallService();
  final _wallet = WalletService();
  Timer? _pollTimer;
  Timer? _timeoutTimer;
  String _gender = 'any';
  int _feePaise = 0;
  bool _feeLoaded = false;
  int _balancePaise = 0;
  bool _loading = true;
  bool _searching = false;
  String? _error;
  String? _rejoinCallId;

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
    if (mounted) {
      setState(() {
        _loading = true;
        _feeLoaded = false;
        _error = null;
      });
    }
    try {
      final results = await Future.wait([
        _calls.fee(),
        _wallet.fetchWallet(),
        _calls.currentCall(),
      ]);
      if (!mounted) return;
      final fee = results[0] as int;
      final wallet = results[1] as WalletRow;
      final current = results[2] as Map<String, dynamic>?;
      setState(() {
        _feePaise = fee;
        _feeLoaded = true;
        _balancePaise = wallet.balancePaise;
        _rejoinCallId = current?['call_id']?.toString();
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = AuthService.friendlyMessage(e);
      });
    }
  }

  bool get _paidDisabled => !_feeLoaded || _balancePaise < _feePaise;

  Future<void> _openCall(String callId, [Map<String, dynamic>? row]) async {
    _cancelTimers();
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
        ),
      ),
    );
    if (!mounted) return;
    await _refresh();
  }

  Future<void> _joinQueue() async {
    if (_searching || (_gender != 'any' && _paidDisabled)) return;
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
      _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
        _pollCurrentCall();
      });
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

  Widget _choice(String gender, String label, String price) {
    final selected = _gender == gender;
    final disabled = gender != 'any' && _paidDisabled;
    final priceLabel = disabled
        ? (_feeLoaded && _balancePaise < _feePaise
              ? 'Insufficient balance'
              : 'Unavailable')
        : price;
    return Expanded(
      child: InkWell(
        onTap: disabled ? null : () => setState(() => _gender = gender),
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          decoration: BoxDecoration(
            color: selected ? Colors.white24 : Colors.white10,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? Colors.white70 : Colors.white24,
            ),
          ),
          child: Column(
            children: [
              Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
              const SizedBox(height: 4),
              Text(
                priceLabel,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: disabled ? Colors.white54 : Colors.white70,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GlassBackground(
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: GlassCard(
              padding: const EdgeInsets.all(22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Talk',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Practice speaking with a new partner.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 22),
                  if (_loading)
                    const CircularProgressIndicator(color: Colors.white)
                  else
                    Row(
                      children: [
                        _choice('any', 'Anyone (Free)', 'Free'),
                        const SizedBox(width: 8),
                        _choice('female', 'Female', formatRupees(_feePaise)),
                        const SizedBox(width: 8),
                        _choice('male', 'Male', formatRupees(_feePaise)),
                      ],
                    ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.orangeAccent),
                    ),
                    const SizedBox(height: 12),
                    GlassButton(label: 'Retry', onPressed: _refresh),
                  ],
                  const SizedBox(height: 20),
                  if (_rejoinCallId != null)
                    GlassButton(
                      label: 'Rejoin call',
                      onPressed: () => _openCall(_rejoinCallId!),
                    )
                  else if (_searching)
                    GlassButton(label: 'Cancel', onPressed: _cancelSearch)
                  else
                    GlassButton(label: 'Find partner', onPressed: _joinQueue),
                  const SizedBox(height: 18),
                  const Text(
                    'Never share personal details such as your phone number, address, social accounts, or financial information.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, fontSize: 13),
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
