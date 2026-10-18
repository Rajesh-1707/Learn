import 'package:flutter/material.dart';
import '../models/learn_models.dart';
import '../services/auth_service.dart';
import '../services/learn_service.dart';
import '../widgets/glass.dart';
import 'topic_page.dart';

const learnLanguages = [
  'Telugu', 'Hindi', 'Tamil', 'Kannada', 'Malayalam', 'Bengali',
  'Marathi', 'Gujarati', 'Urdu', 'Odia', 'Punjabi', 'English', 'Other',
];

class LearnPage extends StatefulWidget {
  final Map<String, dynamic>? profile;
  final ValueChanged<String>? onLanguageChanged;
  const LearnPage({super.key, this.profile, this.onLanguageChanged});
  @override
  State<LearnPage> createState() => _LearnState();
}

class _LearnState extends State<LearnPage> {
  final _learn = LearnService();
  final _auth = AuthService();
  List<Topic> _topics = [];
  bool _loading = true;
  String? _error;

  String get _lang =>
      (widget.profile?['native_language'] as String?)?.trim().isNotEmpty == true
          ? (widget.profile!['native_language'] as String).trim()
          : 'English';

  String get _first {
    final full = (widget.profile?['full_name'] as String?)?.trim() ?? '';
    if (full.isEmpty) return 'there';
    return full.split(RegExp(r'\s+')).first;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
      _loading = true;
      _error = null;
    });
    }
    try {
      final topics = await _learn.fetchTopics();
      if (!mounted) return;
      setState(() {
        _topics = topics;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = AuthService.friendlyMessage(e);
      });
    }
  }

  Future<void> _changeLang() async {
    String? picked;
    await showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF3B2A6E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final l in learnLanguages)
              ListTile(
                title:
                    Text(l, style: const TextStyle(color: Colors.white)),
                trailing: l == _lang
                    ? const Icon(Icons.check, color: Colors.white)
                    : null,
                onTap: () {
                  picked = l;
                  Navigator.of(ctx).pop();
                },
              ),
          ],
        ),
      ),
    );
    if (!mounted || picked == null || picked == _lang) return;
    try {
      await _auth.updateNativeLanguage(picked!);
      if (!mounted) return;
      widget.onLanguageChanged?.call(picked!);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Language set to $picked')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AuthService.friendlyMessage(e))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return GlassBackground(
      child: RefreshIndicator(
        color: Colors.white,
        backgroundColor: const Color(0xFF5B3BA8),
        onRefresh: _load,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('Hi, $_first',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 26,
                              fontWeight: FontWeight.bold)),
                    ),
                    GestureDetector(
                      onTap: _changeLang,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: Colors.white
                                  .withValues(alpha: 0.35)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_lang,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13)),
                            const SizedBox(width: 4),
                            const Icon(Icons.edit,
                                color: Colors.white70, size: 14),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_loading)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                    child: CircularProgressIndicator(
                        color: Colors.white)),
              )
            else if (_error != null)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: GlassCard(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_error!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  color: Colors.white)),
                          const SizedBox(height: 16),
                          GlassButton(
                              label: 'Retry', onPressed: _load),
                        ],
                      ),
                    ),
                  ),
                ),
              )
            else if (_topics.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Text('No topics yet. Check back soon.',
                      style: TextStyle(color: Colors.white70)),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                sliver: SliverList.separated(
                  itemCount: _topics.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: 12),
                  itemBuilder: (ctx, i) {
                    final t = _topics[i];
                    final tr = t.titleFor(_lang);
                    return GestureDetector(
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              TopicPage(topic: t, language: _lang),
                        ),
                      ),
                      child: GlassCard(
                        padding: const EdgeInsets.all(18),
                        child: Row(
                          children: [
                            Text(t.emoji.isEmpty ? '📚' : t.emoji,
                                style: const TextStyle(fontSize: 36)),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(t.title,
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 17,
                                          fontWeight: FontWeight.w600)),
                                  if (tr != null) ...[
                                    const SizedBox(height: 2),
                                    Text(tr,
                                        style: TextStyle(
                                            color: Colors.white
                                                .withValues(
                                                    alpha: 0.75),
                                            fontSize: 14)),
                                  ],
                                ],
                              ),
                            ),
                            Container(
                              padding:
                                  const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(
                                    alpha: 0.2),
                                borderRadius:
                                    BorderRadius.circular(12),
                              ),
                              child: Text(t.level,
                                  style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 12)),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

