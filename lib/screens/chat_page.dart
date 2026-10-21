import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/chat_service.dart';
import '../services/pricing_service.dart';
import '../services/wallet_service.dart';
import '../utils/money.dart';
import '../widgets/glass.dart';
import 'wallet_page.dart';

class ChatPage extends StatefulWidget {
  final String friendName;
  final String friendId;

  const ChatPage({super.key, required this.friendName, required this.friendId});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _chat = ChatService();
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _messages = <Map<String, dynamic>>[];
  RealtimeChannel? _channel;
  Timer? _expiryTimer;
  String? _chatId;
  int _price = 500;
  int _balance = 0;
  bool _paidToday = false;
  bool _loading = true;
  bool _sending = false;
  bool _paywallOpen = false;
  String? _error;

  String? get _myId => Supabase.instance.client.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    final channel = _channel;
    if (channel != null) _chat.unsubscribe(channel);
    _expiryTimer?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final settings = await PricingService().fetchSettings();
      final wallet = await WalletService().fetchWallet();
      final chatId = await _chat.ensureChat(widget.friendId);
      final paid = await _chat.paidToday(widget.friendId);
      if (!mounted) return;
      setState(() {
        _price = settings['chat_per_day_paise'] ?? 500;
        _balance = wallet.balancePaise;
        _chatId = chatId;
        _paidToday = paid;
        _loading = false;
      });
      if (paid) {
        await _activateChat(chatId);
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) => _showPaywall());
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _activateChat(String chatId) async {
    _expiryTimer ??= Timer.periodic(
      const Duration(minutes: 1),
      (_) => _refreshMessages(chatId),
    );
    _channel ??= _chat.subscribe(
      chatId,
      onInsert: _upsertMessage,
      onDelete: () => _refreshMessages(chatId),
    );
    await _refreshMessages(chatId);
  }

  Future<void> _refreshMessages(String chatId) async {
    try {
      final rows = await _chat.messages(chatId);
      if (!mounted) return;
      setState(() {
        _messages
          ..clear()
          ..addAll(rows);
      });
      _scrollToEnd();
    } catch (_) {}
  }

  void _upsertMessage(Map<String, dynamic> row) {
    final id = row['id']?.toString();
    if (id == null || id.isEmpty || !mounted) return;
    setState(() {
      final index = _messages.indexWhere((message) => message['id'] == id);
      if (index < 0) {
        _messages.add(row);
        _messages.sort(
          (a, b) => '${a['created_at']}'.compareTo('${b['created_at']}'),
        );
      } else {
        _messages[index] = row;
      }
    });
    _scrollToEnd();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _showPaywall() async {
    if (!mounted || _paidToday || _paywallOpen || _chatId == null) return;
    _paywallOpen = true;
    final canPay = _balance >= _price;
    final action = await showModalBottomSheet<String>(
      context: context,
      isDismissible: true,
      backgroundColor: Colors.transparent,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: GlassCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Unlock chat for today',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 21,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Price: ${formatRupees(_price)} · Wallet: ${formatRupees(_balance)}',
                  style: const TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 14),
                GlassButton(
                  label: canPay ? 'Pay from wallet' : 'Insufficient balance',
                  onPressed: canPay
                      ? () => Navigator.pop(context, 'pay')
                      : null,
                ),
                if (!canPay) ...[
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: () => Navigator.pop(context, 'wallet'),
                    child: const Text('Add money'),
                  ),
                ],
                TextButton(
                  onPressed: () => Navigator.pop(context, 'later'),
                  child: const Text(
                    'Maybe later',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    _paywallOpen = false;
    if (!mounted || action == null || action == 'later') return;
    if (action == 'wallet') {
      await Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const WalletPage()));
      if (mounted) {
        final wallet = await WalletService().fetchWallet();
        setState(() => _balance = wallet.balancePaise);
        _showPaywall();
      }
      return;
    }
    try {
      final result = await _chat.payForChat(widget.friendId);
      if (!mounted) return;
      if (result == 'insufficient_balance') {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Insufficient balance')));
        final wallet = await WalletService().fetchWallet();
        if (mounted) setState(() => _balance = wallet.balancePaise);
        return;
      }
      final wallet = await WalletService().fetchWallet();
      if (!mounted) return;
      setState(() {
        _balance = wallet.balancePaise;
        _paidToday = true;
      });
      final chatId = _chatId;
      if (chatId != null) await _activateChat(chatId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Chat unlocked for today')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Could not unlock chat')));
      }
    }
  }

  Future<void> _send() async {
    final body = _input.text.trim();
    final chatId = _chatId;
    if (body.isEmpty || _sending) return;
    if (!_paidToday) {
      _showPaywall();
      return;
    }
    if (chatId == null) return;
    setState(() => _sending = true);
    try {
      final message = await _chat.sendMessage(chatId, body);
      if (!mounted) return;
      _input.clear();
      _upsertMessage(message);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Could not send message')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _clearChat() async {
    final chatId = _chatId;
    if (chatId == null) return;
    final clear = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear chat?'),
        content: const Text('This removes all messages for both people.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (clear != true) return;
    try {
      await _chat.clearChat(chatId);
      if (!mounted) return;
      setState(_messages.clear);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Could not clear chat')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.friendName),
      backgroundColor: Colors.transparent,
      foregroundColor: Colors.white,
      elevation: 0,
      actions: [
        PopupMenuButton<String>(
          onSelected: (_) => _clearChat(),
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'clear', child: Text('Clear chat')),
          ],
        ),
      ],
    ),
    extendBodyBehindAppBar: true,
    body: GlassBackground(
      child: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 68, 16, 8),
              child: GlassCard(
                padding: EdgeInsets.all(10),
                child: Text(
                  'Messages disappear after 24 hours',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    )
                  : _error != null
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Could not open chat',
                            style: const TextStyle(color: Colors.white),
                          ),
                          TextButton(
                            onPressed: _load,
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.all(16),
                      itemCount: _messages.length,
                      itemBuilder: (context, index) {
                        final message = _messages[index];
                        final mine = message['sender_id'] == _myId;
                        final sentAt = DateTime.tryParse(
                          '${message['created_at']}',
                        )?.toLocal();
                        return Align(
                          alignment: mine
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 5),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            constraints: const BoxConstraints(maxWidth: 300),
                            decoration: BoxDecoration(
                              color: mine
                                  ? Colors.white.withValues(alpha: 0.26)
                                  : Colors.white.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  '${message['body'] ?? ''}',
                                  style: const TextStyle(color: Colors.white),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  sentAt == null
                                      ? ''
                                      : '${sentAt.hour.toString().padLeft(2, '0')}:${sentAt.minute.toString().padLeft(2, '0')}',
                                  style: const TextStyle(
                                    color: Colors.white54,
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      enabled: _paidToday && !_loading,
                      onSubmitted: (_) => _send(),
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: _paidToday
                            ? 'Message'
                            : 'Unlock chat to message',
                        hintStyle: const TextStyle(color: Colors.white60),
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.16),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(22),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _sending ? null : _send,
                    icon: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
