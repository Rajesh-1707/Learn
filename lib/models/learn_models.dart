/// A learning topic row from public.topics.
class Topic {
  final String id;
  final String slug;
  final String title;
  final Map<String, String> titleTranslations;
  final String emoji;
  final String level;
  final int sortOrder;

  const Topic({
    required this.id,
    required this.slug,
    required this.title,
    required this.titleTranslations,
    required this.emoji,
    required this.level,
    required this.sortOrder,
  });

  factory Topic.fromJson(Map<String, dynamic> json) {
    return Topic(
      id: '${json['id'] ?? ''}',
      slug: '${json['slug'] ?? ''}',
      title: '${json['title'] ?? ''}',
      titleTranslations: _strMap(json['title_translations']),
      emoji: '${json['emoji'] ?? ''}',
      level: '${json['level'] ?? 'beginner'}',
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
    );
  }

  /// Title in [language] (e.g. 'Telugu'), or null when missing or English.
  String? titleFor(String language) {
    final lang = language.trim();
    if (lang.isEmpty || lang.toLowerCase() == 'english') return null;
    final v = (titleTranslations[lang] ?? '').trim();
    return v.isEmpty ? null : v;
  }
}

/// A phrase row from public.phrases.
class Phrase {
  final String id;
  final String topicId;
  final String english;
  final Map<String, String> translations;
  final int sortOrder;

  const Phrase({
    required this.id,
    required this.topicId,
    required this.english,
    required this.translations,
    required this.sortOrder,
  });

  factory Phrase.fromJson(Map<String, dynamic> json) {
    return Phrase(
      id: '${json['id'] ?? ''}',
      topicId: '${json['topic_id'] ?? ''}',
      english: '${json['english'] ?? ''}',
      translations: _strMap(json['translations']),
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
    );
  }

  /// Meaning in [language], or null when missing or English.
  String? meaningFor(String language) {
    final lang = language.trim();
    if (lang.isEmpty || lang.toLowerCase() == 'english') return null;
    final v = (translations[lang] ?? '').trim();
    return v.isEmpty ? null : v;
  }
}

Map<String, String> _strMap(dynamic raw) {
  if (raw is! Map) return const {};
  final out = <String, String>{};
  raw.forEach((k, v) {
    final value = '$v'.trim();
    if (value.isNotEmpty) out['$k'] = value;
  });
  return out;
}
