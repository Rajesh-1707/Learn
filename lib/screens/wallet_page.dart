import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/wallet_models.dart';
import '../services/wallet_service.dart';
import '../utils/money.dart';
import '../widgets/glass.dart';

class WalletPage extends StatefulWidget {
  const WalletPage({super.key});

  @override
  State<WalletPage> createState() => _WalletPageState();
}

class _WalletPageState extends State<WalletPage> {
  final _service = WalletService();

  bool _loading = true;
  Object? _error;
  WalletRow? _wallet;
  List<TransactionRow> _transactions = [];

  @override
  void initState() {
    super.initState();
    _load(showLoader: true);
  }

  Future<void> _load({bool showLoader = false}) async {
    if (showLoader) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final wallet = await _service.fetchWallet();
      final txns = await _service.fetchTransactions(limit: 50);
      if (!mounted) return;
      setState(() {
        _wallet = wallet;
        _transactions = txns;
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

  @override
  Widget build(BuildContext context) {
    return GlassBackground(
      child: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    if (_error != null && _wallet == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: GlassCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, color: Colors.white, size: 48),
                const SizedBox(height: 12),
                const Text(
                  'Could not load your wallet',
                  style: TextStyle(color: Colors.white, fontSize: 18),
                ),
                const SizedBox(height: 8),
                Text(
                  kDebugMode
                      ? _error.toString()
                      : 'Check your internet and try again.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 16),
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
        children: [
          const _SectionTitle('Balance'),
          const SizedBox(height: 12),
          _AmountCard(
            amountPaise: _wallet?.balancePaise ?? 0,
            buttonLabel: 'Add money',
          ),
          const SizedBox(height: 24),
          const _SectionTitle('Earnings'),
          const SizedBox(height: 12),
          _AmountCard(
            amountPaise: _wallet?.earningsPaise ?? 0,
            buttonLabel: 'Withdraw',
          ),
          const SizedBox(height: 24),
          const _SectionTitle('History'),
          const SizedBox(height: 12),
          if (_transactions.isEmpty)
            GlassCard(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.history, color: Colors.white70, size: 48),
                  const SizedBox(height: 12),
                  const Text(
                    'No transactions yet.',
                    style: TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            )
          else
            Column(
              mainAxisSize: MainAxisSize.min,
              children: _transactions.map((t) {
                final positive = t.isPositive;
                return GlassCard(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(t.typeIcon, color: Colors.white, size: 20),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              t.typeLabel,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (t.note != null && t.note!.isNotEmpty)
                              Text(
                                t.note!,
                                style: const TextStyle(
                                  color: Colors.white60,
                                  fontSize: 12,
                                ),
                              ),
                            const SizedBox(height: 4),
                            Text(
                              t.createdAt ?? '',
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '${positive ? '+' : '-'}${formatRupees(t.amountPaise)}',
                        style: TextStyle(
                          color: positive
                              ? Colors.greenAccent
                              : Colors.redAccent,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }
}

class _SectionTitle extends void StatelessWidget {
  final String title;
  const _SectionTitle(this.title);

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 18,
        fontWeight: FontWeight.bold,
      ),
    );
  }
}

class _AmountCard extends void StatelessWidget {
  final int amountPaise;
  final String buttonLabel;
  const _AmountCard({required this.amountPaise, required this.buttonLabel});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Text(
            formatRupees(amountPaise),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 34,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                disabledBackgroundColor: Colors.white.withValues(alpha: 0.12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              onPressed: null,
              child: Text(
                buttonLabel,
                style: const TextStyle(color: Colors.white70, fontSize: 15),
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Coming soon',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
                void GlassButton(
                  label: 'Retry',
                  onPressed: () => _load(showLoader: true),
                ),
              ],
            ),
          ),
        ),
      );
    }