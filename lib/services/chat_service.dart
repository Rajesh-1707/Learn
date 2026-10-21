import 'package:supabase_flutter/supabase_flutter.dart';

class ChatService {
  final SupabaseClient _client;

  ChatService([SupabaseClient? client])
    : _client = client ?? Supabase.instance.client;

  Future<String> ensureChat(String friendId) async {
    final value = await _client.rpc(
      'ensure_friend_chat',
      params: {'p_friend_id': friendId},
    );
    if (value is! String || value.isEmpty) {
      throw Exception('Could not open chat');
    }
    return value;
  }

  Future<bool> paidToday(String friendId) async {
    return await _client.rpc(
          'chat_paid_today',
          params: {'p_friend_id': friendId},
        ) ==
        true;
  }

  Future<String> payForChat(String friendId) async {
    final value = await _client.rpc(
      'pay_for_chat',
      params: {'p_friend_id': friendId},
    );
    return value?.toString() ?? 'unknown';
  }

  Future<List<Map<String, dynamic>>> messages(String chatId) async {
    final rows = await _client
        .from('messages')
        .select('id, chat_id, sender_id, body, created_at')
        .eq('chat_id', chatId)
        .gte(
          'created_at',
          DateTime.now()
              .toUtc()
              .subtract(const Duration(hours: 24))
              .toIso8601String(),
        )
        .order('created_at');
    return (rows as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  Future<Map<String, dynamic>> sendMessage(String chatId, String body) async {
    final senderId = _client.auth.currentUser?.id;
    if (senderId == null) throw Exception('Not signed in');
    final row = await _client
        .from('messages')
        .insert({'chat_id': chatId, 'sender_id': senderId, 'body': body})
        .select('id, chat_id, sender_id, body, created_at')
        .single();
    return Map<String, dynamic>.from(row);
  }

  Future<void> clearChat(String chatId) async {
    await _client.rpc('clear_chat', params: {'p_chat_id': chatId});
  }

  RealtimeChannel subscribe(
    String chatId, {
    required void Function(Map<String, dynamic> message) onInsert,
    required void Function() onDelete,
  }) {
    return _client
        .channel('messages:$chatId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'chat_id',
            value: chatId,
          ),
          callback: (payload) {
            if (payload.eventType == PostgresChangeEvent.insert) {
              onInsert(Map<String, dynamic>.from(payload.newRecord));
            } else if (payload.eventType == PostgresChangeEvent.delete) {
              onDelete();
            }
          },
        )
        .subscribe();
  }

  void unsubscribe(RealtimeChannel channel) {
    _client.removeChannel(channel);
  }
}
