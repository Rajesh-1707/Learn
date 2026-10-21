import 'package:supabase_flutter/supabase_flutter.dart';

/// Owner-only calls. Screens never call Supabase directly.
class OwnerService {
  final SupabaseClient _client;

  OwnerService([SupabaseClient? client])
    : _client = client ?? Supabase.instance.client;

  /// Calls the owner_stats() RPC. Raises an error for non-owner roles
  /// (enforced by the database / RLS).
  Future<Map<String, dynamic>> ownerStats() async {
    final data = await _client.rpc('owner_stats');
    final row = data is List
        ? (data.isEmpty
              ? throw Exception('No owner stats returned')
              : data.first)
        : data;
    return Map<String, dynamic>.from(row as Map);
  }

  Future<List<Map<String, dynamic>>> listUsers({
    String search = '',
    int limit = 30,
    int offset = 0,
  }) async {
    final data = await _client.rpc(
      'owner_list_users',
      params: {'p_search': search, 'p_limit': limit, 'p_offset': offset},
    );
    return (data as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  Future<void> setGenderVerified(String userId, bool verified) async {
    await _client.rpc(
      'owner_set_gender_verified',
      params: {'p_user_id': userId, 'p_verified': verified},
    );
  }

  Future<int> ownerTodayCollected() async {
    final value = await _client.rpc('owner_today_collected_paise');
    return (value as num?)?.toInt() ?? 0;
  }
}
