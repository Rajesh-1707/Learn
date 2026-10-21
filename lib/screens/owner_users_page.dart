import 'dart:async';

import 'package:flutter/material.dart';

import '../services/owner_service.dart';
import '../utils/money.dart';
import '../widgets/glass.dart';

class OwnerUsersPage extends StatefulWidget {
  const OwnerUsersPage({super.key});

  @override
  State<OwnerUsersPage> createState() => _OwnerUsersPageState();
}

class _OwnerUsersPageState extends State<OwnerUsersPage> {
  final _owner = OwnerService();
  final _search = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>> _users = [];
  bool _loading = true;
  Object? _error;
  int _offset = 0;
  static const _pageSize = 30;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool reset = false}) async {
    if (reset) {
      _offset = 0;
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final rows = await _owner.listUsers(
        search: _search.text.trim(),
        limit: _pageSize,
        offset: _offset,
      );
      if (!mounted) return;
      setState(() {
        _users = reset ? rows : [..._users, ...rows];
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e;
      });
    }
  }

  String _joined(dynamic value) {
    final date = DateTime.tryParse('$value')?.toLocal();
    if (date == null) return 'Unknown';
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  void _showDetails(Map<String, dynamic> user) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF6243A0),
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${user['full_name'] ?? 'Unnamed user'}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              _detail('Gender', user['gender']),
              _detail('City', user['city']),
              _detail('State', user['state']),
              _detail('Role', user['role']),
              _detail('Joined', _joined(user['created_at'])),
              _detail(
                'Wallet balance',
                formatRupees((user['balance_paise'] as num?)?.toInt() ?? 0),
              ),
              _detail(
                'Earnings',
                formatRupees((user['earnings_paise'] as num?)?.toInt() ?? 0),
              ),
              _detail(
                'Gender verified',
                user['verified_gender'] == true ? 'Yes' : 'No',
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detail(String label, dynamic value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.white70)),
        Flexible(
          child: Text(
            '${value ?? '—'}',
            textAlign: TextAlign.end,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Users'),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      extendBodyBehindAppBar: true,
      body: GlassBackground(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 64, 16, 12),
                child: TextField(
                  controller: _search,
                  onChanged: (_) {
                    _debounce?.cancel();
                    _debounce = Timer(
                      const Duration(milliseconds: 350),
                      () => _load(reset: true),
                    );
                  },
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Search users',
                    hintStyle: const TextStyle(color: Colors.white70),
                    prefixIcon: const Icon(Icons.search, color: Colors.white),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.18),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: _loading && _users.isEmpty
                    ? const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      )
                    : _error != null && _users.isEmpty
                    ? Center(
                        child: GlassCard(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'Could not load users',
                                style: TextStyle(color: Colors.white),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '$_error',
                                style: const TextStyle(color: Colors.white70),
                              ),
                              TextButton(
                                onPressed: () => _load(reset: true),
                                child: const Text('Retry'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : _users.isEmpty
                    ? const Center(
                        child: Text(
                          'No users found',
                          style: TextStyle(color: Colors.white70),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                        itemCount:
                            _users.length +
                            (_users.length >= _pageSize ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index == _users.length) {
                            return Center(
                              child: TextButton(
                                onPressed: _loading
                                    ? null
                                    : () {
                                        _offset += _pageSize;
                                        _load();
                                      },
                                child: const Text(
                                  'Load more',
                                  style: TextStyle(color: Colors.white),
                                ),
                              ),
                            );
                          }
                          final user = _users[index];
                          final place = [user['city'], user['state']]
                              .where((v) => v != null && '$v'.isNotEmpty)
                              .join(', ');
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(22),
                              onTap: () => _showDetails(user),
                              child: GlassCard(
                                padding: const EdgeInsets.all(16),
                                child: Row(
                                  children: [
                                    const CircleAvatar(
                                      backgroundColor: Colors.white24,
                                      child: Icon(
                                        Icons.person,
                                        color: Colors.white,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '${user['full_name'] ?? 'Unnamed user'}',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(height: 3),
                                          Text(
                                            '${user['gender'] ?? '—'}${place.isEmpty ? '' : ' · $place'}',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: Colors.white70,
                                              fontSize: 12,
                                            ),
                                          ),
                                          Text(
                                            'Joined ${_joined(user['created_at'])}',
                                            style: const TextStyle(
                                              color: Colors.white54,
                                              fontSize: 11,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      formatRupees(
                                        (user['balance_paise'] as num?)
                                                ?.toInt() ??
                                            0,
                                      ),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
