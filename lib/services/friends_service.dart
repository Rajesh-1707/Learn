import 'package:supabase_flutter/supabase_flutter.dart';

class FriendsService {
  final SupabaseClient _client;

  FriendsService([SupabaseClient? client])
    : _client = client ?? Supabase.instance.client;

  Future<List<Map<String, dynamic>>> friends() async {
    final data = await _client.rpc('list_friends');
    return (data as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  Future<List<Map<String, dynamic>>> requests() async {
    final data = await _client.rpc('list_friend_requests');
    return (data as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  Future<List<Map<String, dynamic>>> searchUsers(String query) async {
    final data = await _client.rpc(
      'search_friend_candidates',
      params: {'p_query': query.trim()},
    );
    return (data as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  Future<void> sendRequest(String userId) async {
    await _client.rpc('request_friend', params: {'p_user': userId});
  }

  Future<void> addFromCall({
    required String id,
    String? name,
    String? avatarUrl,
  }) => sendRequest(id);

  Future<void> respond(String userId, {required bool accept}) async {
    await _client.rpc(
      'respond_friend',
      params: {'p_user': userId, 'p_accept': accept},
    );
  }

  Future<String> startCall(String friendId, String mediaType) async {
    final data = await _client.rpc(
      'start_friend_call',
      params: {'p_friend_id': friendId, 'p_media_type': mediaType},
    );
    if (data is! String || data.isEmpty) {
      throw Exception('Could not start call');
    }
    return data;
  }

  Future<Map<String, dynamic>?> pendingCall() async {
    final data = await _client.rpc('pending_friend_call');
    if (data is! List || data.isEmpty) return null;
    return Map<String, dynamic>.from(data.first as Map);
  }

  Future<void> setPresence(bool online) async {
    await _client.rpc('set_my_presence', params: {'p_online': online});
  }

  Future<bool> isBlocked(String userId) async {
    final value = await _client.rpc('is_blocked', params: {'p_user': userId});
    return value == true;
  }
}
