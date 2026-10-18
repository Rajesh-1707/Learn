import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_config.dart';

/// Thin service layer over Supabase RPCs. Screens never call Supabase directly.
class CallService {
  final SupabaseClient _client;

  CallService([SupabaseClient? client])
    : _client = client ?? Supabase.instance.client;

  /// RPC: join_call_queue(p_want_gender text 'any'|'male'|'female', p_topic uuid default null)
  /// Returns call_id or null when the current user is waiting.
  Future<String?> joinQueue(String wantGender, String? topicId) async {
    final data = await _client.rpc(
      'join_call_queue',
      params: {
        'p_want_gender': wantGender,
        'p_topic': topicId != null && topicId.isNotEmpty ? topicId : null,
      },
    );
    if (data is String && data.isNotEmpty) return data;
    if (data == null) return null;
    if (data is! Map) return null;
    final v = data['call_id'];
    if (v == null) return null;
    return v is String ? v : (v as num?)?.toString();
  }

  /// RPC: leave_call_queue()
  Future<void> leaveQueue() async {
    await _client.rpc('leave_call_queue');
  }

  /// RPC: current_call() returns 0 or 1 row.
  Future<Map<String, dynamic>?> currentCall() async {
    final data = await _client.rpc('current_call');
    if (data == null) return null;
    final row = data is List ? (data.isEmpty ? null : data[0]) : data;
    if (row == null) return null;
    return Map<String, dynamic>.from(row as Map);
  }

  /// RPC: mark_call_connected(p_call)
  Future<void> markConnected(String callId) async {
    await _client.rpc('mark_call_connected', params: {'p_call': callId});
  }

  /// RPC: end_call(p_call)
  Future<void> endCall(String callId) async {
    await _client.rpc('end_call', params: {'p_call': callId});
  }

  /// RPC: charge_call(p_call) returns 'free' | 'already' | 'too_early' | 'charged'.
  /// Raises 'insufficient balance'.
  Future<String> chargeCall(String callId) async {
    final data = await _client.rpc('charge_call', params: {'p_call': callId});
    if (data is String) return data;
    if (data is Map) {
      final v = data['status'] ?? data['result'];
      if (v != null) return '$v';
    }
    return 'unknown';
  }

  /// RPC: call_fee_paise() returns fee in paise.
  Future<int> fee() async {
    final data = await _client.rpc('call_fee_paise');
    if (data is num) return data.toInt();
    if (data is int) return data;
    if (data is Map) {
      final v = data['fee_paise'] ?? data['call_fee_paise'];
      if (v != null) return (v as num).toInt();
    }
    return 0;
  }

  /// POST the token endpoint with the current bearer access token.
  Future<Map<String, dynamic>> fetchToken(String callId) async {
    if (AppConfig.apiBaseUrl.toUpperCase().contains('YOUR')) {
      throw Exception('App server address is not set');
    }
    try {
      await _client.auth.refreshSession();
    } catch (_) {}
    final token = _client.auth.currentSession?.accessToken;
    if (token == null || token.isEmpty) {
      throw Exception('Not signed in, please log in again');
    }
    final uri = Uri.parse('${AppConfig.apiBaseUrl}/api/calls/token');
    Future<http.Response> sendRequest() => http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'call_id': callId}),
    );

    late final http.Response response;
    try {
      response = await sendRequest();
    } on http.ClientException {
      response = await sendRequest();
    } on TimeoutException {
      response = await sendRequest();
    }
    if (response.statusCode != 200) {
      throw Exception(
        'Failed to fetch Agora token: ${response.statusCode} ${response.body}',
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw const FormatException('Invalid token response from server.');
    }
    return Map<String, dynamic>.from(decoded);
  }

  /// Insert a report into public.reports (reporter is current user).
  Future<void> reportUser({
    required String reportedId,
    required String callId,
    required String reason,
    String? details,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) throw const AuthException('Not signed in.');
    await _client.from('reports').insert({
      'reporter_id': user.id,
      'reported_id': reportedId,
      'call_id': callId,
      'reason': reason,
      if (details != null && details.isNotEmpty) 'details': details,
    });
  }

  /// Insert a block into public.blocks (reporter is current user).
  Future<void> blockUser({required String blockedId}) async {
    final user = _client.auth.currentUser;
    if (user == null) throw const AuthException('Not signed in.');
    await _client.from('blocks').upsert({
      'blocker_id': user.id,
      'blocked_id': blockedId,
    }, onConflict: 'blocker_id,blocked_id');
  }

  static String friendlyInsufficientBalance() =>
      'Your balance is too low. Please add money first.';
}
