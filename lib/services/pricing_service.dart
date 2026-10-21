import 'package:supabase_flutter/supabase_flutter.dart';

class PricingService {
  final SupabaseClient _client;

  PricingService([SupabaseClient? client])
    : _client = client ?? Supabase.instance.client;

  Future<Map<String, int>> fetchSettings() async {
    final rows = await _client
        .from('app_settings')
        .select('key, value')
        .order('key');
    return {
      for (final row in rows) '${row['key']}': (row['value'] as num).toInt(),
    };
  }

  Future<Map<String, DateTime?>> fetchSettingUpdates() async {
    final rows = await _client.from('app_settings').select('key, updated_at');
    return {
      for (final row in rows)
        '${row['key']}': DateTime.tryParse('${row['updated_at']}')?.toLocal(),
    };
  }

  Future<Map<String, dynamic>> fetchOwnRates() async {
    final user = _client.auth.currentUser;
    if (user == null) throw Exception('Not signed in');
    final row = await _client
        .from('profiles')
        .select('audio_rate_paise, video_rate_paise')
        .eq('id', user.id)
        .single();
    return Map<String, dynamic>.from(row);
  }

  Future<void> setMyRates({int? audioPaise, int? videoPaise}) async {
    await _client.rpc(
      'set_my_rates',
      params: {'p_audio': audioPaise, 'p_video': videoPaise},
    );
  }

  Future<void> setSetting(String key, int value) async {
    await _client.rpc(
      'owner_set_setting',
      params: {'p_key': key, 'p_value': value},
    );
  }
}
