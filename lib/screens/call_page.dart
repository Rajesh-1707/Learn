import 'dart:async';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/call_service.dart';
import '../services/friends_service.dart';
import '../utils/money.dart';
import '../widgets/glass.dart';

class CallPage extends StatefulWidget {
  final Map<String, dynamic>? profile;
  final String callId;
  final String? topicId;
  final String? topicTitle;
  final String mediaType;
  final int ratePaise;
  final bool isFriendCall;

  const CallPage({
    super.key,
    required this.callId,
    this.topicId,
    this.topicTitle,
    this.profile,
    this.mediaType = 'audio',
    this.ratePaise = 1000,
    this.isFriendCall = false,
  });

  @override
  State<CallPage> createState() => _CallPageState();
}

class _CallPageState extends State<CallPage>
    with SingleTickerProviderStateMixin {
  final _calls = CallService();
  RtcEngine? _engine;
  Timer? _ringTimer;
  Timer? _chargeTimer;
  Timer? _elapsedTimer;
  int _elapsedSeconds = 0;
  int? _remoteUid;
  Offset _previewOffset = const Offset(16, 90);
  bool _connected = false;
  bool _ending = false;
  bool _muted = false;
  bool _speaker = false;
  bool _camera = true;
  bool _friendPromptShown = false;
  bool _billing = false;
  String _status = 'Connecting securely...';
  String? _error;
  String? _otherUserId;
  String? _partnerName;
  String? _partnerAvatarUrl;
  String? _callTopicTitle;
  bool _partnerDetailsLoaded = false;
  late final AnimationController _pulseController;
  bool get _video => widget.mediaType == 'video';
  bool get _videoSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  int get _spentPaise => _elapsedSeconds * widget.ratePaise ~/ 60;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
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
    var step = 'requesting microphone access';
    try {
      final permission = await Permission.microphone.request();
      if (!mounted) return;
      if (!permission.isGranted) {
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Microphone permission required'),
            content: const Text(
              'Allow microphone access in settings to make a call.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () async {
                  Navigator.of(dialogContext).pop();
                  await openAppSettings();
                },
                child: const Text('Open settings'),
              ),
            ],
          ),
        );
        throw Exception('Microphone permission is required to call.');
      }
      step = 'requesting call credentials';
      if (_video && !_videoSupported) {
        throw Exception('Video calls are currently available on Android.');
      }
      final tokenData = await _calls.fetchToken(widget.callId);
      if (!mounted) return;
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
      if (!RegExp(r'^[0-9a-fA-F]{32}$').hasMatch(appId)) {
        throw const FormatException(
          'The call server returned an invalid Agora App ID.',
        );
      }
      final engine = createAgoraRtcEngine();
      _engine = engine;
      step = 'initializing Agora';
      await engine.initialize(RtcEngineContext(appId: appId));
      if (!mounted) return;
      step = 'enabling audio';
      await engine.enableAudio();
      if (!mounted) return;
      if (_video) {
        final cameraPermission = await Permission.camera.request();
        if (!cameraPermission.isGranted) {
          throw Exception('Camera permission is required for video calls.');
        }
        await engine.enableVideo();
        await engine.startPreview();
      }
      engine.registerEventHandler(
        RtcEngineEventHandler(
          onJoinChannelSuccess: (connection, elapsed) {
            if (!mounted) return;
            setState(() {
              _status = 'Waiting for your partner...';
            });
            // Routing is optional and only supported on Android/iOS. Apply it
            // after joining, and never let a device routing failure block RTC.
            if (!kIsWeb) _setSpeakerRoute(engine, true);
          },
          onUserJoined: (connection, remoteUid, elapsed) {
            if (!mounted || _connected) return;
            _ringTimer?.cancel();
            setState(() {
              _connected = true;
              _status = 'Connected';
              _remoteUid = remoteUid;
            });
            _calls.markConnected(widget.callId).catchError((_) {});
            _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
              if (!mounted) return;
              setState(() => _elapsedSeconds++);
              if (_elapsedSeconds >= 40 &&
                  !_friendPromptShown &&
                  !widget.isFriendCall) {
                _showAddFriend();
              }
            });
            _billMinute();
            _chargeTimer = Timer.periodic(
              const Duration(minutes: 1),
              (_) => _billMinute(),
            );
          },
          onUserOffline: (connection, remoteUid, reason) => _partnerLeft(),
          onTokenPrivilegeWillExpire: (connection, token) => _renewToken(),
          onError: (error, message) {
            debugPrint('Agora onError: code=$error, message=$message');
            if (!mounted) return;
            setState(() {
              _error = 'Agora error code $error: $message';
              _status = 'Could not start call';
            });
          },
          onConnectionStateChanged: (connection, state, reason) {
            debugPrint('Agora connection state: $state, reason: $reason');
            if (!mounted ||
                state != ConnectionStateType.connectionStateFailed) {
              return;
            }
            setState(() => _status = 'Agora connection failed: $reason');
          },
        ),
      );
      step = 'configuring the call';
      await engine.setChannelProfile(
        ChannelProfileType.channelProfileCommunication,
      );
      if (!mounted) return;
      await engine.setClientRole(role: ClientRoleType.clientRoleBroadcaster);
      if (!mounted) return;
      step = 'joining the call';
      await engine.joinChannel(
        token: token,
        channelId: channel,
        uid: uid,
        options: ChannelMediaOptions(
          clientRoleType: ClientRoleType.clientRoleBroadcaster,
          channelProfile: ChannelProfileType.channelProfileCommunication,
          publishMicrophoneTrack: true,
          publishCameraTrack: _video,
          autoSubscribeAudio: true,
          autoSubscribeVideo: _video,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (e is AgoraRtcException) {
          final hint = e.code == -3 && step == 'initializing Agora'
              ? ' Check that the Agora App ID is active and matches the app certificate configured on the call server.'
              : '';
          _error =
              'Agora error code ${e.code} while $step: ${e.message ?? e.toString()}$hint';
        } else {
          _error = e.toString().replaceFirst('Exception: ', '');
        }
        _status = 'Could not start call';
      });
    }
  }

  Future<void> _billMinute() async {
    if (!mounted || !_connected || _ending || _billing) return;
    _billing = true;
    try {
      final result = (await _calls.billMinute(widget.callId)).toLowerCase();
      if (!mounted || _ending) return;
      if (result == 'low_balance') {
        await _showLowBalanceDialog();
      } else if (result == 'ended') {
        await _finish(showMessage: 'This call has ended.');
      }
    } catch (error) {
      if (mounted && !_ending) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not process call payment.')),
        );
      }
    } finally {
      _billing = false;
    }
  }

  Future<void> _showLowBalanceDialog() async {
    if (!mounted || _ending) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF553A91),
        title: const Text('Call ended', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Your balance is too low for the next minute.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (mounted && !_ending) {
      await _finish(showMessage: 'Call ended because your balance is low.');
    }
  }

  Future<void> _showAddFriend() async {
    _friendPromptShown = true;
    final partnerId = _otherUserId;
    if (partnerId == null || partnerId.isEmpty || !mounted) return;
    final add = await showDialog<bool>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: GlassCard(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Add as friend?',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text(
                          'Not now',
                          style: TextStyle(color: Colors.white70),
                        ),
                      ),
                    ),
                    Expanded(
                      child: GlassButton(
                        label: 'Add',
                        onPressed: () => Navigator.pop(context, true),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (add == true) {
      try {
        await FriendsService().addFromCall(
          id: partnerId,
          name: _partnerName ?? 'Friend',
          avatarUrl: _partnerAvatarUrl,
        );
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Friend request sent')));
        }
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not send friend request')),
          );
        }
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
    _elapsedTimer?.cancel();
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
    try {
      await _engine?.muteLocalAudioStream(next);
      if (!mounted) return;
      setState(() => _muted = next);
    } catch (error) {
      if (mounted) _showActionError('Microphone control failed', error);
    }
  }

  Future<void> _toggleSpeaker() async {
    if (kIsWeb) return;
    final next = !_speaker;
    await _setSpeakerRoute(_engine, next, reportError: true);
  }

  Future<void> _toggleCamera() async {
    final next = !_camera;
    try {
      await _engine?.muteLocalVideoStream(!next);
      if (!mounted) return;
      setState(() => _camera = next);
    } catch (error) {
      if (mounted) _showActionError('Camera control failed', error);
    }
  }

  Future<void> _switchCamera() async {
    try {
      await _engine?.switchCamera();
    } catch (error) {
      if (mounted) _showActionError('Could not switch camera', error);
    }
  }

  Future<void> _setSpeakerRoute(
    RtcEngine? engine,
    bool enabled, {
    bool reportError = false,
  }) async {
    try {
      await engine?.setEnableSpeakerphone(enabled);
      if (!mounted) return;
      setState(() => _speaker = enabled);
    } catch (error) {
      debugPrint('Agora speaker routing unavailable: $error');
      if (reportError && mounted) {
        _showActionError('Speaker control failed', error);
      }
    }
  }

  Future<void> _report() async {
    final otherId = _otherUserId?.trim();
    if (!_partnerDetailsLoaded || otherId == null || otherId.isEmpty) {
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
    final otherId = _otherUserId?.trim();
    if (!_partnerDetailsLoaded || otherId == null || otherId.isEmpty) {
      return;
    }
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
    _pulseController.dispose();
    _ringTimer?.cancel();
    _chargeTimer?.cancel();
    _elapsedTimer?.cancel();
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
  Widget build(BuildContext context) {
    final topicTitle = _callTopicTitle?.isNotEmpty == true
        ? _callTopicTitle
        : widget.topicTitle;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _finish();
      },
      child: Scaffold(
        body: _video ? _videoCallBody(topicTitle) : _audioCallBody(topicTitle),
      ),
    );
  }

  Widget _audioCallBody(String? topicTitle) => GlassBackground(
    child: SafeArea(
      child: Column(
        children: [
          Align(alignment: Alignment.topRight, child: _callMenu()),
          const Spacer(),
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) => Transform.scale(
              scale: _connected ? 1 + _pulseController.value * 0.045 : 1,
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(
                      alpha: _connected ? 0.65 : 0.25,
                    ),
                    width: _connected ? 5 : 2,
                  ),
                  boxShadow: [
                    if (_connected)
                      BoxShadow(
                        color: Colors.white.withValues(
                          alpha: 0.15 + _pulseController.value * 0.2,
                        ),
                        blurRadius: 20 + _pulseController.value * 12,
                        spreadRadius: 3 + _pulseController.value * 4,
                      ),
                  ],
                ),
                child: child,
              ),
            ),
            child: _partnerAvatar(),
          ),
          const SizedBox(height: 20),
          Text(
            _firstName(_partnerName),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 25,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (topicTitle != null && topicTitle.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(topicTitle, style: const TextStyle(color: Colors.white70)),
          ],
          const SizedBox(height: 10),
          Text(
            _error ?? _status,
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 22),
          Text(
            _elapsedLabel(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '₹ spent ${formatRupees(_spentPaise)}',
            style: const TextStyle(color: Colors.white70, fontSize: 16),
          ),
          const Spacer(),
          _controlBar(),
          const SizedBox(height: 24),
        ],
      ),
    ),
  );

  Widget _videoCallBody(String? topicTitle) => GlassBackground(
    child: SafeArea(
      child: Stack(
        children: [
          Positioned.fill(
            child: _connected && _remoteUid != null && _engine != null
                ? AgoraVideoView(
                    controller: VideoViewController.remote(
                      rtcEngine: _engine!,
                      canvas: VideoCanvas(uid: _remoteUid!),
                      connection: RtcConnection(channelId: widget.callId),
                    ),
                  )
                : Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _partnerAvatar(),
                        const SizedBox(height: 14),
                        Text(
                          _firstName(_partnerName),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          topicTitle ?? _error ?? _status,
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
          ),
          Positioned(top: 8, right: 8, child: _callMenu()),
          if (_engine != null && _connected)
            Positioned(
              left: _previewOffset.dx,
              top: _previewOffset.dy,
              child: GestureDetector(
                onPanUpdate: (d) => setState(
                  () => _previewOffset = Offset(
                    (_previewOffset.dx + d.delta.dx).clamp(
                      0,
                      MediaQuery.sizeOf(context).width - 140,
                    ),
                    (_previewOffset.dy + d.delta.dy).clamp(
                      0,
                      MediaQuery.sizeOf(context).height - 240,
                    ),
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Container(
                    width: 120,
                    height: 170,
                    color: Colors.black54,
                    child: _camera
                        ? AgoraVideoView(
                            controller: VideoViewController(
                              rtcEngine: _engine!,
                              canvas: const VideoCanvas(uid: 0),
                            ),
                          )
                        : const Center(
                            child: Icon(
                              Icons.videocam_off,
                              color: Colors.white,
                              size: 36,
                            ),
                          ),
                  ),
                ),
              ),
            ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 112,
            child: Column(
              children: [
                Text(
                  '${_firstName(_partnerName)}${topicTitle == null ? '' : ' · $topicTitle'}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
                Text(
                  '${_elapsedLabel()} · ${formatRupees(_spentPaise)} spent',
                  style: const TextStyle(color: Colors.white),
                ),
              ],
            ),
          ),
          Positioned(left: 12, right: 12, bottom: 16, child: _controlBar()),
        ],
      ),
    ),
  );

  Widget _controlBar() => GlassCard(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _control(
          _muted ? Icons.mic_off : Icons.mic,
          _muted ? 'Unmute' : 'Mute',
          _toggleMute,
        ),
        if (!kIsWeb)
          _control(
            _speaker ? Icons.volume_up : Icons.hearing,
            'Speaker',
            _toggleSpeaker,
          ),
        if (_video) ...[
          _control(
            _camera ? Icons.videocam : Icons.videocam_off,
            'Camera',
            _toggleCamera,
          ),
          _control(Icons.flip_camera_android, 'Switch camera', _switchCamera),
        ],
        IconButton.filled(
          onPressed: () => _finish(),
          style: IconButton.styleFrom(
            backgroundColor: Colors.redAccent,
            foregroundColor: Colors.white,
          ),
          tooltip: 'End call',
          icon: const Icon(Icons.call_end),
        ),
      ],
    ),
  );

  Widget _control(IconData icon, String label, VoidCallback action) =>
      IconButton(
        onPressed: action,
        tooltip: label,
        icon: Icon(icon, color: Colors.white),
      );

  Widget _callMenu() => PopupMenuButton<String>(
    iconColor: Colors.white,
    color: const Color(0xFF5B3BA8),
    onSelected: (value) => value == 'report' ? _report() : _block(),
    itemBuilder: (_) => const [
      PopupMenuItem(
        value: 'report',
        child: Text('Report user', style: TextStyle(color: Colors.white)),
      ),
      PopupMenuItem(
        value: 'block',
        child: Text('Block user', style: TextStyle(color: Colors.white)),
      ),
    ],
  );

  String _elapsedLabel() {
    final minutes = _elapsedSeconds ~/ 60;
    final seconds = _elapsedSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

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
