import 'package:supabase_flutter/supabase_flutter.dart';

/// Owner-only calls. Screens never call Supabase directly.
class OwnerService {
  final SupabaseClient _client;

  OwnerService([SupabaseClient? client])
      : _client = client ?? Supabase.instance.client;

  /// Calls the owner_stats() RPC. Raises an error for non-owner roles
  /// (enforced by the database / RLS).
  Future<Map<String, dynamic>> ownerStats() async {
    final result = await _client.rpc('owner_stats');
    return Map<String, dynamic>.from(result.data as Map);
  }
}
