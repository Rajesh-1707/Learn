import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_config.dart';
import '../models/wallet_models.dart';

/// All Wallet reads live here. Screens never call Supabase directly.
class WalletService {
  final SupabaseClient _client;

  WalletService([SupabaseClient? client])
    : _client = client ?? Supabase.instance.client;

  Future<WalletRow> fetchWallet() async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Not signed in. Please log in again.');
    }
    final row = await _client
        .from('wallets')
        .select('user_id, balance_paise, earnings_paise, updated_at')
        .eq('user_id', user.id)
        .maybeSingle();
    if (row == null) {
      // No wallet row yet — return zeros rather than erroring.
      return WalletRow(
        userId: user.id,
        balancePaise: 0,
        earningsPaise: 0,
        updatedAt: null,
      );
    }
    return WalletRow.fromJson(Map<String, dynamic>.from(row as Map));
  }

  Future<List<TransactionRow>> fetchTransactions({int limit = 50}) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Not signed in. Please log in again.');
    }
    final rows = await _client
        .from('transactions')
        .select('id, user_id, type, amount_paise, ref, note, created_at')
        .eq('user_id', user.id)
        .order('created_at', ascending: false)
        .limit(limit);
    return (rows as List)
        .map(
          (r) => TransactionRow.fromJson(Map<String, dynamic>.from(r as Map)),
        )
        .toList();
  }

  Future<PaymentOrder> createPaymentOrder(int amountRupees) async {
    final accessToken = _client.auth.currentSession?.accessToken;
    if (accessToken == null || accessToken.isEmpty) {
      throw const AuthException('Not signed in. Please log in again.');
    }

    final response = await http
        .post(
          Uri.parse('${AppConfig.apiBaseUrl}/api/payments/create-order'),
          headers: {
            'Authorization': 'Bearer $accessToken',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'amount_rupees': amountRupees}),
        )
        .timeout(const Duration(seconds: 20));

    if (response.statusCode == 401) {
      throw Exception('Your session expired. Please sign in again.');
    }
    if (response.statusCode == 404) {
      throw Exception(
        'Payment service is still deploying. Please try again shortly.',
      );
    }
    if (response.statusCode == 400) {
      throw Exception('Please choose a valid amount and try again.');
    }
    if (response.statusCode != 200) {
      throw Exception(
        'Payment service could not create an order. Please try again later.',
      );
    }

    try {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) throw const FormatException();
      final orderId = decoded['order_id'];
      final keyId = decoded['key_id'];
      final amountPaise = decoded['amount_paise'];
      if (orderId is! String ||
          orderId.isEmpty ||
          keyId is! String ||
          keyId.isEmpty ||
          amountPaise is! num ||
          amountPaise.toInt() != amountRupees * 100) {
        throw const FormatException();
      }
      return PaymentOrder(
        orderId: orderId,
        keyId: keyId,
        amountPaise: amountPaise.toInt(),
      );
    } catch (_) {
      throw Exception('Could not start payment. Please try again.');
    }
  }
}

class PaymentOrder {
  final String orderId;
  final String keyId;
  final int amountPaise;

  const PaymentOrder({
    required this.orderId,
    required this.keyId,
    required this.amountPaise,
  });
}
