import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/owner_service.dart';
import '../services/friends_service.dart';
import '../services/call_service.dart';
import '../widgets/avatar_picker.dart';

import '../screens/talk_page.dart';

import '../widgets/glass.dart';
import 'learn_page.dart';
import 'wallet_page.dart';
import 'owner_users_page.dart';
import 'my_rates_page.dart';
import 'owner_pricing_page.dart';
import 'owner_dashboard_page.dart';
import '../utils/money.dart';
import 'call_page.dart';

class HomePage extends StatefulWidget {
  final Map<String, dynamic>? profile;
  const HomePage({super.key, this.profile});
  @override
  State<HomePage> createState() => _H();
}

class _H extends State<HomePage> with WidgetsBindingObserver {
  final _a = AuthService();
  final _friends = FriendsService();
  final _calls = CallService();
  Timer? _presenceTimer;
  Timer? _incomingTimer;
  bool _openingIncoming = false;
  String? _avatar;
  String _lang = 'English';
  String _name = '';
  String _role = 'user';

  // Owner dashboard state
  final _owner = OwnerService();
  bool _ownerLoading = false;
  Object? _ownerError;
  Map<String, dynamic>? _ownerStats;

  int _tab = 0;
  int _talkTabEpoch = 0;
  int _walletTabEpoch = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _read(widget.profile);
  }

  @override
  void didUpdateWidget(HomePage old) {
    super.didUpdateWidget(old);
    if (old.profile != widget.profile) _read(widget.profile);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startPresence();
    } else {
      _stopPresence();
    }
  }

  void _startPresence() {
    if (_role == 'owner' || _a.currentUser == null) return;
    _friends.setPresence(true).catchError((_) {});
    _presenceTimer ??= Timer.periodic(
      const Duration(seconds: 25),
      (_) => _friends.setPresence(true).catchError((_) {}),
    );
    _incomingTimer ??= Timer.periodic(
      const Duration(seconds: 3),
      (_) => _checkIncomingCall(),
    );
  }

  Future<void> _stopPresence() async {
    _presenceTimer?.cancel();
    _presenceTimer = null;
    _incomingTimer?.cancel();
    _incomingTimer = null;
    try {
      await _friends.setPresence(false);
    } catch (_) {}
  }

  Future<void> _checkIncomingCall() async {
    if (!mounted || _openingIncoming) return;
    try {
      final call = await _friends.pendingCall();
      final id = call?['call_id']?.toString();
      if (id == null || id.isEmpty || !mounted) return;
      _openingIncoming = true;
      final media = call?['media_type']?.toString() ?? 'audio';
      final canAccept =
          media != 'video' ||
          (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);
      final accept = await showModalBottomSheet<bool>(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (context) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: GlassCard(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Incoming friend call',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (!canAccept)
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text(
                        'Video calls are currently available on Android.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white70),
                      ),
                    ),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Decline'),
                        ),
                      ),
                      Expanded(
                        child: GlassButton(
                          label: 'Accept',
                          onPressed: canAccept
                              ? () => Navigator.pop(context, true)
                              : null,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      if (accept == true && mounted) {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) =>
                CallPage(callId: id, mediaType: media, isFriendCall: true),
          ),
        );
      } else {
        await _calls.endCall(id);
      }
    } catch (_) {
      // The next poll retries transient RPC or network failures.
    } finally {
      _openingIncoming = false;
    }
  }

  void _read(Map<String, dynamic>? p) {
    _avatar = (p?['avatar_url'] as String?)?.trim();
    if (_avatar != null && _avatar!.isEmpty) _avatar = null;
    final l = (p?['native_language'] as String?)?.trim() ?? '';
    if (l.isNotEmpty) _lang = l;
    final n = (p?['full_name'] as String?)?.trim() ?? '';
    _name = n.isNotEmpty ? n : (_a.currentUser?.email ?? '');
    final r = (p?['role'] as String?)?.trim() ?? 'user';
    _role = r;
    if (_role == 'owner') _loadOwnerStats();
    if (_role == 'owner') {
      _stopPresence();
    } else {
      _startPresence();
    }
  }

  Future<void> _loadOwnerStats() async {
    setState(() {
      _ownerLoading = true;
      _ownerError = null;
    });
    try {
      final stats = await _owner.ownerStats();
      if (!mounted) return;
      setState(() {
        _ownerStats = stats;
        _ownerLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _ownerError = e;
        _ownerLoading = false;
      });
    }
  }

  Future<void> _refresh() async {
    try {
      final p = await _a.getMyProfile();
      if (!mounted) return;
      setState(() => _read(p));
    } catch (_) {}
  }

  Future<void> _out() async {
    try {
      await _stopPresence();
      await _a.signOut();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(AuthService.friendlyMessage(e))));
    }
  }

  Widget _profileTab() {
    return GlassBackground(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: GlassCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: AvatarPicker(
                    avatarUrl: _avatar,
                    fallbackName: _name,
                    radius: 52,
                    onChanged: (u) {
                      if (!mounted) return;
                      setState(() => _avatar = u);
                    },
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _name.isEmpty ? 'Your profile' : _name,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      _lang,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Tap the photo to change it.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const SizedBox(height: 20),
                GlassButton(
                  label: 'My rates',
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const MyRatesPage()),
                  ),
                ),
                const SizedBox(height: 12),
                if (_role == 'owner') ...[
                  const Text(
                    'Owner dashboard',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_ownerLoading)
                    const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
                  if (_ownerError != null)
                    GlassCard(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Error loading owner stats',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            AuthService.friendlyMessage(_ownerError!),
                            style: const TextStyle(color: Colors.white70),
                          ),
                          const SizedBox(height: 16),
                          GlassButton(
                            label: 'Retry',
                            onPressed: _loadOwnerStats,
                          ),
                        ],
                      ),
                    ),
                  if (_ownerStats != null && !_ownerLoading)
                    _ownerDashboardCard(),
                ],
                GlassButton(label: 'Log out', onPressed: _out),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _ownerDashboardCard() {
    final s = _ownerStats!;
    return GlassCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _statRow('Total money collected', s['total_collected_paise']),
          _statRow('Call payments received', s['call_fees_paise']),
          _statRow('Paid to users (user earnings)', s['user_earnings_paise']),
          _statRow('Ads income', s['ad_income_paise']),
          _statRow('My net income (platform)', s['platform_income_paise']),
          _statRow(
            'Total users',
            s['users_count'] is int
                ? s['users_count']
                : (s['users_count'] as num?)?.toInt() ?? 0,
            isRupees: false,
          ),
          const Divider(color: Colors.white24, height: 28),
          const Text(
            'Money owed to users',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          _statRow('Wallet balances', s['wallet_balances_paise']),
          _statRow('Unpaid earnings', s['earnings_owed_paise']),
          const SizedBox(height: 12),
          GlassButton(
            label: 'Users',
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const OwnerUsersPage())),
          ),
          const SizedBox(height: 10),
          GlassButton(
            label: 'Pricing',
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const OwnerPricingPage())),
          ),
        ],
      ),
    );
  }

  Widget _statRow(String label, dynamic value, {bool isRupees = true}) {
    final text = isRupees
        ? formatRupees((value as num?)?.toInt() ?? 0)
        : '$value';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_role == 'owner') return const OwnerDashboardPage();
    final prof = {
      'full_name': _name,
      'native_language': _lang,
      'avatar_url': _avatar,
    };
    final pages = [
      LearnPage(
        profile: prof,
        onLanguageChanged: (l) {
          if (!mounted) return;
          setState(() => _lang = l);
          _refresh();
        },
      ),
      TalkPage(key: ValueKey('talk-$_talkTabEpoch'), profile: prof),
      WalletPage(key: ValueKey('wallet-$_walletTabEpoch')),
      _profileTab(),
    ];
    return Scaffold(
      extendBody: true,
      body: IndexedStack(index: _tab, children: pages),
      bottomNavigationBar: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: BottomNavigationBar(
            currentIndex: _tab,
            onTap: (i) => setState(() {
              _tab = i;
              if (i == 1) _talkTabEpoch++;
              if (i == 2) _walletTabEpoch++;
            }),
            type: BottomNavigationBarType.fixed,
            backgroundColor: Colors.transparent,
            elevation: 0,
            selectedItemColor: Colors.white,
            unselectedItemColor: Colors.white.withValues(alpha: 0.55),
            items: const [
              BottomNavigationBarItem(icon: Icon(Icons.school), label: 'Learn'),
              BottomNavigationBarItem(icon: Icon(Icons.call), label: 'Talk'),
              BottomNavigationBarItem(
                icon: Icon(Icons.wallet),
                label: 'Wallet',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.person),
                label: 'Profile',
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _presenceTimer?.cancel();
    _incomingTimer?.cancel();
    _stopPresence();
    super.dispose();
  }
}
