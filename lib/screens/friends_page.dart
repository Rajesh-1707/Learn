import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/friends_service.dart';
import '../services/wallet_service.dart';
import '../models/wallet_models.dart';
import '../utils/money.dart';
import '../widgets/glass.dart';
import 'call_page.dart';
import 'chat_page.dart';
import 'wallet_page.dart';

class FriendsPage extends StatefulWidget {
  const FriendsPage({super.key});
  @override
  State<FriendsPage> createState() => _FriendsPageState();
}

class _FriendsPageState extends State<FriendsPage> {
  final _friends = FriendsService();
  final _search = TextEditingController();
  bool _loading = true;
  Object? _error;
  List<Map<String, dynamic>> _rows = [];
  List<Map<String, dynamic>> _requests = [];
  List<Map<String, dynamic>> _searchResults = [];
  bool _querying = false;
  int _balance = 0;
  Timer? _refreshTimer;
  bool get _videoSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  void initState() {
    super.initState();
    _load();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _load(showLoader: false),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool showLoader = true}) async {
    if (showLoader) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final values = await Future.wait<Object>([
        _friends.friends(),
        _friends.requests(),
        WalletService().fetchWallet(),
      ]);
      if (!mounted) return;
      setState(() {
        _rows = values[0] as List<Map<String, dynamic>>;
        _requests = values[1] as List<Map<String, dynamic>>;
        _balance = (values[2] as WalletRow).balancePaise;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e;
      });
    }
  }

  Future<void> _searchUsers() async {
    final query = _search.text.trim();
    if (query.isEmpty) return;
    setState(() => _querying = true);
    try {
      final results = await _friends.searchUsers(query);
      if (mounted) {
        setState(() {
          _searchResults = results;
          _querying = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _querying = false;
          _searchResults = [];
        });
      }
    }
  }

  Future<void> _addCandidate(Map<String, dynamic> row) async {
    try {
      await _friends.sendRequest('${row['user_id']}');
      if (!mounted) return;
      setState(() {
        _searchResults.remove(row);
        _search.clear();
      });
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Friend request sent')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not send friend request')),
        );
      }
    }
  }

  Future<void> _respond(Map<String, dynamic> request, bool accept) async {
    try {
      await _friends.respond('${request['user_id']}', accept: accept);
      await _load(showLoader: false);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update friend request')),
        );
      }
    }
  }

  Future<void> _startCall(Map<String, dynamic> friend, String type) async {
    if (type == 'video' && !_videoSupported) return;
    if (friend['online'] != true) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Not available')));
      return;
    }
    final rate =
        ((type == 'audio'
                    ? friend['audio_rate_paise']
                    : friend['video_rate_paise'])
                as num?)
            ?.toInt() ??
        (type == 'audio' ? 1000 : 2000);
    final affordable = _balance >= rate;
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: GlassCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${type == 'audio' ? 'Audio' : 'Video'} call with ${friend['full_name'] ?? 'Friend'}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Their rate: ${formatRupees(rate)} per minute',
                  style: const TextStyle(color: Colors.white70),
                ),
                Text(
                  'Your balance: ${formatRupees(_balance)}',
                  style: const TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 12),
                if (affordable)
                  GlassButton(
                    label: 'Start call',
                    onPressed: () => Navigator.pop(context, 'call'),
                  ),
                if (!affordable)
                  GlassButton(
                    label: 'Add money',
                    onPressed: () => Navigator.pop(context, 'wallet'),
                  ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'wallet') {
      await Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const WalletPage()));
      if (mounted) await _load();
      return;
    }
    if (action == 'call') {
      try {
        final callId = await _friends.startCall('${friend['user_id']}', type);
        if (!mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => CallPage(
              callId: callId,
              mediaType: type,
              ratePaise: rate,
              isFriendCall: true,
            ),
          ),
        );
        if (mounted) await _load();
      } catch (e) {
        if (mounted) {
          final message = e.toString().contains('Not available')
              ? 'Not available'
              : 'Could not start this call';
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(message)));
        }
      }
    }
  }

  Widget _avatar(Map<String, dynamic> row) {
    final url = row['avatar_url'] as String?;
    return Stack(
      children: [
        CircleAvatar(
          radius: 24,
          backgroundColor: Colors.white24,
          backgroundImage: url == null || url.isEmpty
              ? null
              : NetworkImage(url),
          child: url == null || url.isEmpty
              ? const Icon(Icons.person, color: Colors.white)
              : null,
        ),
        Positioned(
          right: 0,
          bottom: 0,
          child: Container(
            width: 11,
            height: 11,
            decoration: BoxDecoration(
              color: row['online'] == true
                  ? Colors.greenAccent
                  : Colors.white38,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Friends'),
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
                child: Text(
                  'Could not load friends',
                  style: const TextStyle(color: Colors.white),
                ),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 72, 16, 24),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _search,
                          onSubmitted: (_) => _searchUsers(),
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            hintText: 'Search by name or user ID',
                            hintStyle: const TextStyle(color: Colors.white70),
                            filled: true,
                            fillColor: Colors.white.withValues(alpha: 0.17),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        onPressed: _querying ? null : _searchUsers,
                        icon: _querying
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.search),
                      ),
                    ],
                  ),
                  for (final candidate in _searchResults)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: GlassCard(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${candidate['full_name'] ?? 'SpeakEarn user'}',
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                            TextButton(
                              onPressed: () => _addCandidate(candidate),
                              child: const Text('Add'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 20),
                  const Text(
                    'Requests',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (_requests.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: Text(
                        'No friend requests',
                        style: TextStyle(color: Colors.white60),
                      ),
                    ),
                  for (final request in _requests)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: GlassCard(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${request['full_name'] ?? 'SpeakEarn user'}',
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                            TextButton(
                              onPressed: () => _respond(request, false),
                              child: const Text('Decline'),
                            ),
                            TextButton(
                              onPressed: () => _respond(request, true),
                              child: const Text('Accept'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 20),
                  const Text(
                    'Friends',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (_rows.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 22),
                      child: Text(
                        'Add friends after a call to talk anytime',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white70),
                      ),
                    ),
                  for (final friend in _rows)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: GlassCard(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            _avatar(friend),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${friend['full_name'] ?? 'Friend'}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    'Audio ${formatRupees((friend['audio_rate_paise'] as num?)?.toInt() ?? 1000)} · Video ${formatRupees((friend['video_rate_paise'] as num?)?.toInt() ?? 2000)}',
                                    style: const TextStyle(
                                      color: Colors.white60,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: 'Audio call',
                              onPressed: () => _startCall(friend, 'audio'),
                              icon: const Icon(Icons.call, color: Colors.white),
                            ),
                            IconButton(
                              tooltip: 'Video call',
                              onPressed: _videoSupported
                                  ? () => _startCall(friend, 'video')
                                  : null,
                              icon: const Icon(
                                Icons.videocam,
                                color: Colors.white,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Chat',
                              onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => ChatPage(
                                    friendName:
                                        '${friend['full_name'] ?? 'Friend'}',
                                    friendId: '${friend['user_id']}',
                                  ),
                                ),
                              ),
                              icon: const Icon(
                                Icons.chat_bubble_outline,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
      ),
    ),
  );
}
