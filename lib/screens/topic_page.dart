import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../models/learn_models.dart';
import '../services/auth_service.dart';
import '../services/learn_service.dart';
import '../widgets/glass.dart';

class TopicPage extends StatefulWidget {
  final Topic topic;
  final String language;
  const TopicPage({super.key, required this.topic, required this.language});
  @override
  State<TopicPage> createState() => _TopicState();
}

class _TopicState extends State<TopicPage> {
  final _learn = LearnService();
  final _tts = FlutterTts();
  List<Phrase> _phrases = [];
  bool _loading = true;
  String? _error;
  String? _speakingId;

  @override
  void initState() {
    super.initState();
    _initTts();
    _load();
  }

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }

  Future<void> _initTts() async {
    try {
      await _tts.setLanguage('en-IN');
      await _tts.setSpeechRate(0.45);
      _tts.setCompletionHandler(() {
        if (mounted) setState(() => _speakingId = null);
      });
      _tts.setCancelHandler(() {
        if (mounted) setState(() => _speakingId = null);
      });
      _tts.setErrorHandler((_) {
        if (mounted) {
          setState(() => _speakingId = null);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not play audio right now.')),
          );
        }
      });
    } catch (_) {}
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final rows = await _learn.fetchPhrases(widget.topic.id);
      if (!mounted) return;
      setState(() {
        _phrases = rows;
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

  Future<void> _speak(Phrase p) async {
    if (_speakingId == p.id) {
      try {
        await _tts.stop();
      } catch (_) {}
      if (mounted) setState(() => _speakingId = null);
      return;
    }
    if (mounted) setState(() => _speakingId = p.id);
    try {
      await _tts.stop();
      await _tts.speak(p.english);
    } catch (_) {
      if (!mounted) return;
      setState(() => _speakingId = null);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not play audio right now.')),
      );
    }
  }

  Widget _card(Phrase p) {
    final meaning = p.meaningFor(widget.language);
    final speaking = _speakingId == p.id;
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.english,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                if (meaning != null)
                  Text(
                    meaning,
                    style: TextStyle(
                      color: Colors.amber.withValues(alpha: 0.9),
                      fontSize: 15,
                    ),
                  )
                else
                  const Text(
                    'Translation not available yet',
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => _speak(p),
            icon: Icon(
              speaking ? Icons.stop_circle : Icons.volume_up,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tr = widget.topic.titleFor(widget.language);
    Widget listArea;
    if (_loading) {
      listArea = const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    } else if (_error != null) {
      listArea = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: GlassCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white),
                ),
                const SizedBox(height: 16),
                GlassButton(label: 'Retry', onPressed: _load),
              ],
            ),
          ),
        ),
      );
    } else if (_phrases.isEmpty) {
      listArea = const Center(
        child: Text(
          'No phrases in this topic yet.',
          style: TextStyle(color: Colors.white70),
        ),
      );
    } else {
      listArea = RefreshIndicator(
        color: Colors.white,
        backgroundColor: const Color(0xFF5B3BA8),
        onRefresh: _load,
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          itemCount: _phrases.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (ctx, i) => _card(_phrases[i]),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.topic.title),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
      ),
      extendBodyBehindAppBar: true,
      body: GlassBackground(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Row(
                children: [
                  Text(
                    widget.topic.emoji.isEmpty ? '📚' : widget.topic.emoji,
                    style: const TextStyle(fontSize: 28),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.topic.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (tr != null)
                          Text(
                            tr,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.75),
                              fontSize: 14,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: listArea),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: GlassButton(
                label: 'Practice — Coming soon',
                onPressed: null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
