import 'package:supabase_flutter/supabase_flutter.dart';
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
        .select(
            'id, user_id, type, amount_paise, ref, note, created_at')
        .eq('user_id', user.id)
        .order('created_at', ascending: false)
        .limit(limit);
    return (rows as List)
        .map((r) => TransactionRow.fromJson(Map<String, dynamic>.from(r as Map)))
        .toList();
  }
}
