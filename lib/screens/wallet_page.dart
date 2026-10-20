import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

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
  Razorpay? _razorpay;
  bool _paymentBusy = false;
  int? _paymentBalanceBefore;
  int? _paymentAmountPaise;

  @override
  void initState() {
    super.initState();
    _load(showLoader: true);
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      _razorpay = Razorpay()
        ..on(Razorpay.EVENT_PAYMENT_SUCCESS, _onPaymentSuccess)
        ..on(Razorpay.EVENT_PAYMENT_ERROR, _onPaymentFailure)
        ..on(Razorpay.EVENT_EXTERNAL_WALLET, _onExternalWallet);
    }
  }

  @override
  void dispose() {
    _razorpay?.clear();
    super.dispose();
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _addMoney() async {
    if (kIsWeb) {
      _showMessage('Add money is available in the app');
      return;
    }
    if (defaultTargetPlatform != TargetPlatform.android || _razorpay == null) {
      _showMessage('Add money is available in the Android app');
      return;
    }

    final amountRupees = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _AddMoneySheet(),
    );
    if (!mounted || amountRupees == null) return;

    setState(() => _paymentBusy = true);
    try {
      final order = await _service.createPaymentOrder(amountRupees);
      if (!mounted) return;
      _paymentBalanceBefore = _wallet?.balancePaise ?? 0;
      _paymentAmountPaise = order.amountPaise;
      _razorpay!.open({
        'key': order.keyId,
        'amount': order.amountPaise,
        'currency': 'INR',
        'name': 'SpeakEarn',
        'description': 'Add money to wallet',
        'order_id': order.orderId,
        'theme': {'color': '#6C4CCF'},
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _paymentBusy = false);
      final message = error.toString().replaceFirst('Exception: ', '');
      _showMessage(message);
    }
  }

  void _onPaymentSuccess(PaymentSuccessResponse response) {
    if (!mounted) return;
    final before = _paymentBalanceBefore;
    final amount = _paymentAmountPaise;
    setState(() {
      _paymentBusy = false;
      _paymentBalanceBefore = null;
      _paymentAmountPaise = null;
    });
    _showMessage('Payment received, updating balance');
    if (before != null && amount != null) {
      unawaited(_refreshAfterPayment(before, amount));
    }
  }

  void _onPaymentFailure(PaymentFailureResponse response) {
    if (!mounted) return;
    setState(() {
      _paymentBusy = false;
      _paymentBalanceBefore = null;
      _paymentAmountPaise = null;
    });
    if (response.code == Razorpay.PAYMENT_CANCELLED) {
      _showMessage('Payment cancelled');
    } else {
      _showMessage('Payment failed. Please try again.');
    }
  }

  void _onExternalWallet(ExternalWalletResponse response) {
    _showMessage('Continue payment in ${response.walletName ?? 'your wallet'}');
  }

  Future<void> _refreshAfterPayment(
    int previousBalance,
    int amountPaise,
  ) async {
    for (var attempt = 0; attempt < 10; attempt++) {
      await Future<void>.delayed(const Duration(seconds: 2));
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      if ((_wallet?.balancePaise ?? 0) >= previousBalance + amountPaise) {
        _showMessage('Wallet balance updated');
        return;
      }
    }
    if (mounted) {
      _showMessage(
        'Payment received. Your balance is still updating; pull to refresh shortly.',
      );
    }
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
    return GlassBackground(child: SafeArea(child: _buildBody()));
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
                GlassButton(
                  label: 'Retry',
                  onPressed: () => _load(showLoader: true),
                ),
              ],
            ),
          ),
        ),
      );
    }

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
            onPressed:
                !kIsWeb && defaultTargetPlatform == TargetPlatform.android
                ? _addMoney
                : null,
            isLoading: _paymentBusy,
            helperText: kIsWeb
                ? 'Add money is available in the app'
                : defaultTargetPlatform == TargetPlatform.android
                ? null
                : 'Add money is available in the Android app',
          ),
          const SizedBox(height: 24),
          const _SectionTitle('Earnings'),
          const SizedBox(height: 12),
          _AmountCard(
            amountPaise: _wallet?.earningsPaise ?? 0,
            buttonLabel: 'Withdraw',
            helperText: 'Coming soon',
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 14,
                  ),
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

class _SectionTitle extends StatelessWidget {
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

class _AmountCard extends StatelessWidget {
  final int amountPaise;
  final String buttonLabel;
  final VoidCallback? onPressed;
  final bool isLoading;
  final String? helperText;

  const _AmountCard({
    required this.amountPaise,
    required this.buttonLabel,
    this.onPressed,
    this.isLoading = false,
    this.helperText,
  });

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
              onPressed: isLoading ? null : onPressed,
              child: isLoading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : Text(
                      buttonLabel,
                      style: const TextStyle(color: Colors.white, fontSize: 15),
                    ),
            ),
          ),
          const SizedBox(height: 8),
          if (helperText != null)
            Text(
              helperText!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
        ],
      ),
    );
  }
}

class _AddMoneySheet extends StatefulWidget {
  const _AddMoneySheet();

  @override
  State<_AddMoneySheet> createState() => _AddMoneySheetState();
}

class _AddMoneySheetState extends State<_AddMoneySheet> {
  final _amountController = TextEditingController(text: '10');
  int? _selectedChip = 10;

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  int? get _amount => int.tryParse(_amountController.text.trim());

  bool get _validAmount => (_amount ?? 0) >= 10 && (_amount ?? 5001) <= 5000;

  void _selectAmount(int amount) {
    setState(() {
      _selectedChip = amount;
      _amountController.text = '$amount';
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: GlassCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Add money',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Choose an amount from ₹10 to ₹5,000.',
                  style: TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [10, 50, 100, 500].map((amount) {
                    final selected = _selectedChip == amount;
                    return ChoiceChip(
                      label: Text('₹$amount'),
                      selected: selected,
                      onSelected: (_) => _selectAmount(amount),
                      selectedColor: Colors.white,
                      backgroundColor: Colors.white.withValues(alpha: 0.14),
                      labelStyle: TextStyle(
                        color: selected
                            ? const Color(0xFF553A9B)
                            : Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                      side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.35),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _amountController,
                  onChanged: (_) => setState(() => _selectedChip = null),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Custom amount (₹)',
                    labelStyle: const TextStyle(color: Colors.white70),
                    prefixIcon: const Icon(
                      Icons.currency_rupee,
                      color: Colors.white,
                    ),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.16),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                GlassButton(
                  label: _validAmount
                      ? 'Continue · ₹${_amount!}'
                      : 'Enter ₹10 to ₹5,000',
                  onPressed: _validAmount
                      ? () => Navigator.of(context).pop(_amount)
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
