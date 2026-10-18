import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/learn_models.dart';

/// All Learn reads live here. Screens never call Supabase directly.
class LearnService {
  final SupabaseClient _client;

  LearnService([SupabaseClient? client])
      : _client = client ?? Supabase.instance.client;

  Future<List<Topic>> fetchTopics() async {
    final rows = await _client
        .from('topics')
        .select(
            'id, slug, title, title_translations, emoji, level, sort_order')
        .eq('is_published', true)
        .order('sort_order');
    return (rows as List)
        .map((r) => Topic.fromJson(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  Future<List<Phrase>> fetchPhrases(String topicId) async {
    final rows = await _client
        .from('phrases')
        .select('id, topic_id, english, translations, sort_order')
        .eq('topic_id', topicId)
        .order('sort_order');
    return (rows as List)
        .map((r) => Phrase.fromJson(Map<String, dynamic>.from(r as Map)))
        .toList();
  }
}
