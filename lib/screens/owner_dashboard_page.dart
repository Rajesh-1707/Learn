import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/owner_service.dart';
import '../utils/money.dart';
import '../widgets/glass.dart';
import 'owner_pricing_page.dart';
import 'owner_users_page.dart';
import 'owner_verification_page.dart';

class OwnerDashboardPage extends StatefulWidget {
  const OwnerDashboardPage({super.key});
  @override
  State<OwnerDashboardPage> createState() => _OwnerDashboardPageState();
}

class _OwnerDashboardPageState extends State<OwnerDashboardPage> {
  final _owner = OwnerService();
  final _auth = AuthService();
  Map<String, dynamic>? _stats;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final values = await Future.wait<Object>([
        _owner.ownerStats(),
        _owner.ownerTodayCollected(),
      ]);
      final stats = Map<String, dynamic>.from(values[0] as Map);
      stats['today_collected_paise'] = values[1];
      if (mounted) {
        setState(() {
          _stats = stats;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  int _num(String key) => (_stats?[key] as num?)?.toInt() ?? 0;

  Future<void> _logout() async {
    try {
      await _auth.signOut();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Could not log out')));
      }
    }
  }

  Widget _tile(String title, String value, IconData icon) => GlassCard(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: Colors.white70),
        const SizedBox(height: 12),
        Text(
          title,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    ),
  );

  Widget _navCard(String title, String subtitle, IconData icon, Widget page) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: () =>
              Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => page)),
          child: GlassCard(
            padding: const EdgeInsets.all(17),
            child: Row(
              children: [
                Icon(icon, color: Colors.white, size: 26),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
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
                        subtitle,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: Colors.white70),
              ],
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
    body: GlassBackground(
      child: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Owner dashboard',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 27,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _logout,
                    icon: const Icon(Icons.logout, color: Colors.white),
                    tooltip: 'Log out',
                  ),
                ],
              ),
              if (_stats == null && _error == null)
                const Padding(
                  padding: EdgeInsets.all(26),
                  child: Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
                ),
              if (_error != null)
                GlassCard(
                  child: Column(
                    children: [
                      const Text(
                        'Could not load dashboard',
                        style: TextStyle(color: Colors.white),
                      ),
                      TextButton(onPressed: _load, child: const Text('Retry')),
                    ],
                  ),
                ),
              if (_stats != null) ...[
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 2,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 1.45,
                  children: [
                    _tile(
                      'Total collected',
                      formatRupees(_num('total_collected_paise')),
                      Icons.account_balance_wallet,
                    ),
                    _tile(
                      'Today',
                      formatRupees(_num('today_collected_paise')),
                      Icons.today,
                    ),
                    _tile('Users', '${_num('users_count')}', Icons.people_alt),
                    _tile(
                      'Earnings payable',
                      formatRupees(_num('earnings_owed_paise')),
                      Icons.payments,
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const Text(
                  'Manage',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                _navCard(
                  'Users',
                  'Name, gender, city and state',
                  Icons.people,
                  const OwnerUsersPage(),
                ),
                _navCard(
                  'Pricing',
                  'Minimum rates, earner shares and chat price',
                  Icons.price_change,
                  const OwnerPricingPage(),
                ),
                _navCard(
                  'Verification queue',
                  'Review unverified profiles',
                  Icons.verified_user,
                  const OwnerVerificationPage(),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}
