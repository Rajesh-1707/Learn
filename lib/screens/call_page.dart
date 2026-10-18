import 'dart:async';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/call_service.dart';
import '../widgets/glass.dart';

class CallPage extends StatefulWidget {
  final Map<String, dynamic>? profile;
  final String callId;
  final String? topicId;
  final String? topicTitle;

  const CallPage({
    super.key,
    required this.callId,
    this.topicId,
    this.topicTitle,
    this.profile,
  });

  @override
  State<CallPage> createState() => _CallPageState();
}

class _CallPageState extends State<CallPage> {
  final _calls = CallService();
  RtcEngine? _engine;
  Timer? _ringTimer;
  Timer? _chargeTimer;
  bool _connected = false;
  bool _ending = false;
  bool _muted = false;
  bool _speaker = true;
  String _status = 'Connecting securely...';
  String? _error;
  String? _otherUserId;
  String? _partnerName;
  String? _partnerAvatarUrl;
  String? _callTopicTitle;
  bool _partnerDetailsLoaded = false;

  @override
  void initState() {
    super.initState();
    _ringTimer = Timer(const Duration(seconds: 45), _noAnswer);
    _loadOtherUserId();
    _connect();
  }

  Future<void> _loadOtherUserId() async {
    try {
      final row = await _calls.currentCall();
      if (!mounted) return;
      setState(() {
        _otherUserId = row?['partner_id']?.toString();
        _partnerName = row?['partner_name']?.toString();
        _partnerAvatarUrl = row?['partner_avatar_url']?.toString();
        _callTopicTitle = row?['topic_title']?.toString();
        _partnerDetailsLoaded = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _partnerDetailsLoaded = true);
    }
  }

  Future<void> _connect() async {
    try {
      final tokenData = await _calls.fetchToken(widget.callId);
      if (!mounted) return;
      final permission = await Permission.microphone.request();
      if (!mounted) return;
      if (!permission.isGranted) {
        throw Exception('Microphone permission is required to call.');
      }
      final appId = tokenData['app_id']?.toString();
      final token = tokenData['token']?.toString();
      final channel = tokenData['channel']?.toString();
      final uid = (tokenData['uid'] as num?)?.toInt();
      if (appId == null ||
          appId.isEmpty ||
          token == null ||
          token.isEmpty ||
          channel == null ||
          channel.isEmpty ||
          uid == null) {
        throw const FormatException(
          'The call server returned incomplete Agora credentials.',
        );
      }
      final engine = createAgoraRtcEngine();
      _engine = engine;
      await engine.initialize(RtcEngineContext(appId: appId));
      if (!mounted) return;
      engine.registerEventHandler(
        RtcEngineEventHandler(
          onJoinChannelSuccess: (connection, elapsed) {
            if (!mounted) return;
            setState(() {
              _status = 'Waiting for your partner...';
            });
          },
          onUserJoined: (connection, remoteUid, elapsed) {
            if (!mounted || _connected) return;
            _ringTimer?.cancel();
            setState(() {
              _connected = true;
              _status = 'Connected';
            });
            _calls.markConnected(widget.callId).catchError((_) {});
            _chargeTimer = Timer(const Duration(seconds: 30), _charge);
          },
          onUserOffline: (connection, remoteUid, reason) => _partnerLeft(),
          onTokenPrivilegeWillExpire: (connection, token) => _renewToken(),
          onError: (error, message) {
            if (!mounted) return;
            setState(() => _status = 'Agora error $error: $message');
          },
          onConnectionStateChanged: (connection, state, reason) {
            if (!mounted ||
                state != ConnectionStateType.connectionStateFailed) {
              return;
            }
            setState(() => _status = 'Agora connection failed: $reason');
          },
        ),
      );
      await engine.enableAudio();
      if (!mounted) return;
      await engine.setChannelProfile(
        ChannelProfileType.channelProfileCommunication,
      );
      if (!mounted) return;
      await engine.setClientRole(role: ClientRoleType.clientRoleBroadcaster);
      if (!mounted) return;
      await engine.joinChannel(
        token: token,
        channelId: channel,
        uid: uid,
        options: const ChannelMediaOptions(
          clientRoleType: ClientRoleType.clientRoleBroadcaster,
          channelProfile: ChannelProfileType.channelProfileCommunication,
          publishMicrophoneTrack: true,
          autoSubscribeAudio: true,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _status = 'Could not start call';
      });
    }
  }

  Future<void> _charge() async {
    if (!mounted || !_connected || _ending) return;
    for (var attempt = 0; attempt < 6; attempt++) {
      try {
        final result = (await _calls.chargeCall(widget.callId)).toLowerCase();
        if (!mounted || _ending) return;
        if (result.contains('insufficient balance')) {
          await _finish(
            showMessage: 'Your balance is low. Add money to continue calling.',
          );
          return;
        }
        if (result == 'charged' || result == 'already' || result == 'free') {
          return;
        }
        if (result != 'too_early') return;
      } catch (e) {
        if (!mounted) return;
        if (e.toString().toLowerCase().contains('insufficient balance')) {
          await _finish(
            showMessage: 'Your balance is low. Add money to continue calling.',
          );
          return;
        }
        return;
      }
      if (attempt < 5) {
        await Future<void>.delayed(const Duration(seconds: 3));
        if (!mounted || _ending) return;
      }
    }
  }

  Future<void> _noAnswer() async {
    if (_connected || _ending) return;
    await _finish(showMessage: 'No answer. Try finding another partner.');
  }

  Future<void> _partnerLeft() async {
    if (!mounted || _ending) return;
    await _finish(showMessage: 'Your partner left', showAfterCall: true);
  }

  Future<void> _renewToken() async {
    try {
      final data = await _calls.fetchToken(widget.callId);
      if (!mounted) return;
      final token = data['token']?.toString();
      if (token != null) await _engine?.renewToken(token);
    } catch (_) {}
  }

  Future<void> _finish({
    String? showMessage,
    bool showAfterCall = false,
  }) async {
    if (_ending) return;
    _ending = true;
    _ringTimer?.cancel();
    _chargeTimer?.cancel();
    try {
      await _calls.endCall(widget.callId);
    } catch (_) {}
    if (!mounted) return;
    await _leaveAndRelease();
    if (!mounted) return;
    if (showMessage != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(showMessage)));
    }
    if (showAfterCall) {
      await showModalBottomSheet<void>(
        context: context,
        builder: (context) => const SafeArea(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('Call ended', textAlign: TextAlign.center),
          ),
        ),
      );
      if (!mounted) return;
    }
    Navigator.of(context).pop();
  }

  Future<void> _leaveAndRelease() async {
    final engine = _engine;
    _engine = null;
    if (engine == null) return;
    try {
      await engine.leaveChannel();
    } catch (_) {}
    try {
      await engine.release();
    } catch (_) {}
  }

  Future<void> _toggleMute() async {
    final next = !_muted;
    await _engine?.muteLocalAudioStream(next);
    if (!mounted) return;
    setState(() => _muted = next);
  }

  Future<void> _toggleSpeaker() async {
    final next = !_speaker;
    await _engine?.setEnableSpeakerphone(next);
    if (!mounted) return;
    setState(() => _speaker = next);
  }

  Future<void> _report() async {
    if (!_partnerDetailsLoaded || (_otherUserId?.trim().isEmpty ?? true)) {
      return;
    }
    final reason = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final r in [
              'abuse',
              'sexual',
              'personal_info',
              'spam',
              'underage',
              'other',
            ])
              ListTile(
                title: Text(r.replaceAll('_', ' ')),
                onTap: () => Navigator.pop(ctx, r),
              ),
          ],
        ),
      ),
    );
    if (!mounted || reason == null) return;
    final otherId = _otherUserId!.trim();
    try {
      await _calls.reportUser(
        reportedId: otherId,
        callId: widget.callId,
        reason: reason,
      );
      if (!mounted) return;
      await _finish(showMessage: 'Report submitted. The call has ended.');
    } catch (error) {
      if (mounted) _showActionError('Report failed', error);
    }
  }

  Future<void> _block() async {
    if (!_partnerDetailsLoaded || (_otherUserId?.trim().isEmpty ?? true)) {
      return;
    }
    final otherId = _otherUserId!.trim();
    try {
      await _calls.blockUser(blockedId: otherId);
      if (!mounted) return;
      await _finish(showMessage: 'User blocked. The call has ended.');
    } catch (error) {
      if (mounted) _showActionError('Block failed', error);
    }
  }

  void _showActionError(String action, Object error) {
    final detail = error.toString().replaceFirst('Exception: ', '');
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('$action: $detail')));
  }

  @override
  void dispose() {
    _ringTimer?.cancel();
    _chargeTimer?.cancel();
    final engine = _engine;
    _engine = null;
    if (engine != null) {
      engine.leaveChannel();
      engine.release();
    }
    if (!_ending) _calls.endCall(widget.callId);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) _finish();
    },
    child: Scaffold(
      body: GlassBackground(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: GlassCard(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _partnerAvatar(),
                  const SizedBox(height: 18),
                  Text(
                    _firstName(_partnerName),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _error ?? _status,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70),
                  ),
                  if (_partnerDetailsLoaded &&
                      (_otherUserId?.trim().isEmpty ?? true)) ...[
                    const SizedBox(height: 8),
                    const Text(
                      'Report and Block are unavailable because partner details could not be loaded.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                  if (_callTopicTitle?.isNotEmpty == true ||
                      widget.topicTitle?.isNotEmpty == true) ...[
                    const SizedBox(height: 6),
                    Text(
                      _callTopicTitle ?? widget.topicTitle!,
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                  const SizedBox(height: 28),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      IconButton(
                        onPressed: _toggleMute,
                        icon: Icon(_muted ? Icons.mic_off : Icons.mic),
                        color: Colors.white,
                        tooltip: _muted ? 'Unmute' : 'Mute',
                      ),
                      IconButton(
                        onPressed: _toggleSpeaker,
                        icon: Icon(_speaker ? Icons.volume_up : Icons.hearing),
                        color: Colors.white,
                        tooltip: _speaker ? 'Speaker on' : 'Speaker off',
                      ),
                      IconButton(
                        onPressed:
                            _partnerDetailsLoaded &&
                                (_otherUserId?.trim().isNotEmpty ?? false)
                            ? _report
                            : null,
                        icon: const Icon(Icons.flag),
                        color: Colors.white,
                        tooltip: 'Report',
                      ),
                      IconButton(
                        onPressed:
                            _partnerDetailsLoaded &&
                                (_otherUserId?.trim().isNotEmpty ?? false)
                            ? _block
                            : null,
                        icon: const Icon(Icons.block),
                        color: Colors.white,
                        tooltip: 'Block',
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  GlassButton(label: 'End call', onPressed: () => _finish()),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );

  String _firstName(String? name) {
    final trimmed = name?.trim() ?? '';
    if (trimmed.isEmpty) return 'Your partner';
    return trimmed.split(RegExp(r'\s+')).first;
  }

  Widget _partnerAvatar() {
    final url = _partnerAvatarUrl?.trim() ?? '';
    if (url.isEmpty) {
      return const CircleAvatar(
        radius: 48,
        child: Icon(Icons.person, size: 48),
      );
    }
    return ClipOval(
      child: Image.network(
        url,
        width: 96,
        height: 96,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) =>
            const SizedBox(width: 96, height: 96),
      ),
    );
  }
}
