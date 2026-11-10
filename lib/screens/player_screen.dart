import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';

import '../models/media_item.dart';
import '../models/player_settings.dart';
import '../services/device_video_scanner.dart';
import '../services/local_video_controller.dart';

const _green = Color(0xFFB9F36B);
const _ink = Color(0xFF19251F);

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({
    super.key,
    required this.queue,
    required this.initialIndex,
    required this.settings,
    this.headers = const {},
  });

  final List<MediaItem> queue;
  final int initialIndex;
  final PlayerSettings settings;
  final Map<String, String> headers;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  static const _progressKey = 'streambox.playbackProgress';

  VideoPlayerController? _controller;
  late int _index = widget.initialIndex;
  late double _speed = widget.settings.defaultSpeed;
  late int _repeatMode = widget.settings.repeatMode;
  BoxFit _fit = BoxFit.contain;
  bool _loading = true;
  bool _fullscreen = false;
  bool _fullscreenLandscape = false;
  bool _controlsVisible = true;
  bool _locked = false;
  bool _handlingCompletion = false;
  bool _gestureIndicatorVisible = false;
  double _volume = 1;
  double _scrubDeltaMilliseconds = 0;
  Duration? _scrubStart;
  Duration? _scrubTarget;
  String? _gestureLabel;
  String? _error;
  String? _subtitleName;
  String? _activeUrl;
  bool _activeIsLocal = false;
  Duration _subtitleDelay = Duration.zero;
  List<_SubtitleCue> _subtitles = [];
  Timer? _hideTimer;
  Timer? _sleepTimer;
  Timer? _positionTimer;
  Timer? _gestureTimer;

  MediaItem get _item => widget.queue[_index];

  @override
  void initState() {
    super.initState();
    _openCurrent();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _sleepTimer?.cancel();
    _positionTimer?.cancel();
    _gestureTimer?.cancel();
    unawaited(_savePlaybackPosition());
    _controller?.removeListener(_handleControllerUpdate);
    _controller?.dispose();
    _restoreSystemUi();
    super.dispose();
  }

  Future<void> _restoreSystemUi() async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    if (_isMobilePlatform) {
      await SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
      ]);
    }
  }

  bool get _isMobilePlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  Future<void> _openCurrent() async {
    await _savePlaybackPosition();
    final previous = _controller;
    _hideTimer?.cancel();
    _positionTimer?.cancel();
    previous?.removeListener(_handleControllerUpdate);
    _activeUrl = null;
    _activeIsLocal = false;
    setState(() {
      _controller = null;
      _loading = true;
      _error = null;
      _controlsVisible = true;
      _subtitles = [];
      _subtitleName = null;
      _subtitleDelay = Duration.zero;
    });
    await previous?.dispose();

    VideoPlayerController? next;
    try {
      if (_item.isLocal && !kIsWeb) {
        final localPath = _item.assetId == null
            ? _item.url
            : await resolveDeviceVideo(_item.assetId!);
        if (localPath == null || localPath.isEmpty) {
          throw Exception('无法访问该视频，请检查媒体库权限后重新扫描');
        }
        next = createLocalVideoController(localPath);
      } else {
        next = VideoPlayerController.networkUrl(
          Uri.parse(_item.url),
          httpHeaders: widget.headers,
        );
      }
      await next.initialize();
      final resumePosition = await _resumePositionFor(
        _item,
        next.value.duration,
      );
      if (resumePosition != null && mounted) {
        final resume = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('继续播放？'),
            content: Text('上次播放到 ${_formatTime(resumePosition)}，要从这里继续吗？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('从头播放'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('继续播放'),
              ),
            ],
          ),
        );
        if (resume == true) await next.seekTo(resumePosition);
        if (resume != true) await _clearSavedPosition(_item.url);
      }
      await next.setPlaybackSpeed(_speed);
      await next.play();
      if (!mounted) {
        await next.dispose();
        return;
      }
      setState(() {
        _controller = next;
        _loading = false;
      });
      _activeUrl = _item.url;
      _activeIsLocal = _item.isLocal;
      _handlingCompletion = false;
      _volume = next.value.volume;
      next.addListener(_handleControllerUpdate);
      _positionTimer = Timer.periodic(
        const Duration(seconds: 5),
        (_) => unawaited(_savePlaybackPosition()),
      );
      _scheduleHide();
    } catch (error) {
      await next?.dispose();
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _toggleFullscreen() async {
    if (_fullscreen) {
      await _leaveFullscreen();
      return;
    }
    final viewport = MediaQuery.sizeOf(context);
    _fullscreenLandscape = widget.settings.landscapeOnFullscreen
        ? _videoAspect >= 1
        : viewport.width > viewport.height;
    if (_isMobilePlatform) {
      if (widget.settings.landscapeOnFullscreen) {
        await _applyFullscreenOrientation(_fullscreenLandscape);
      } else {
        await SystemChrome.setPreferredOrientations(const []);
      }
    }
    if (widget.settings.hideSystemUi) {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
    if (!mounted) return;
    setState(() {
      _fullscreen = true;
      _controlsVisible = true;
    });
    _scheduleHide();
  }

  Future<void> _leaveFullscreen() async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    if (_isMobilePlatform) {
      await SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
      ]);
    }
    if (!mounted) return;
    setState(() {
      _fullscreen = false;
      _controlsVisible = true;
    });
    _scheduleHide();
  }

  double get _videoAspect {
    final videoSize = _controller?.value.size;
    if (videoSize != null && videoSize.width > 0 && videoSize.height > 0) {
      return videoSize.width / videoSize.height;
    }
    final width = _item.width;
    final height = _item.height;
    if (width != null && height != null && width > 0 && height > 0) {
      return width / height;
    }
    return 16 / 9;
  }

  Future<void> _applyFullscreenOrientation(bool landscape) async {
    await SystemChrome.setPreferredOrientations(
      landscape
          ? const [
              DeviceOrientation.landscapeLeft,
              DeviceOrientation.landscapeRight,
            ]
          : const [DeviceOrientation.portraitUp],
    );
  }

  Future<void> _rotateFullscreen() async {
    if (!_isMobilePlatform) return;
    final nextLandscape = !_fullscreenLandscape;
    await _applyFullscreenOrientation(nextLandscape);
    if (!mounted) return;
    setState(() => _fullscreenLandscape = nextLandscape);
  }

  double _inlinePlayerHeight(BuildContext context, double width) {
    final screenHeight = MediaQuery.sizeOf(context).height;
    final maxHeight = math.min(width * 1.15, screenHeight * .62);
    final minHeight = math.min(190.0, maxHeight);
    return (width / _videoAspect).clamp(minHeight, maxHeight).toDouble();
  }

  Future<void> _handleBack() async {
    if (_fullscreen) {
      await _leaveFullscreen();
    } else if (mounted) {
      Navigator.of(context).maybePop();
    }
  }

  void _toggleControls() {
    if (_locked) {
      setState(() => _controlsVisible = !_controlsVisible);
      _scheduleHide();
      return;
    }
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) _scheduleHide();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    if (!widget.settings.autoHideControls || !_controlsVisible || _locked) {
      return;
    }
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted) return;
      final playing = _controller?.value.isPlaying ?? false;
      if (playing) setState(() => _controlsVisible = false);
    });
  }

  Future<void> _togglePlay() async {
    final controller = _controller;
    if (controller == null) return;
    if (controller.value.isPlaying) {
      await controller.pause();
      await _savePlaybackPosition();
      _hideTimer?.cancel();
      if (mounted) setState(() => _controlsVisible = true);
    } else {
      if (controller.value.isCompleted) {
        _handlingCompletion = false;
        await controller.seekTo(Duration.zero);
      }
      await controller.play();
      _scheduleHide();
    }
    if (mounted) setState(() {});
  }

  Future<void> _seekBy(Duration delta) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    final target = controller.value.position + delta;
    final max = controller.value.duration;
    await controller.seekTo(
      Duration(
        milliseconds: target.inMilliseconds
            .clamp(0, max.inMilliseconds)
            .toInt(),
      ),
    );
    _scheduleHide();
  }

  Future<Map<String, int>> _readSavedPositions() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_progressKey);
    if (raw == null) return {};
    try {
      final decoded = jsonDecode(raw) as Map;
      return decoded.map(
        (key, value) => MapEntry(key.toString(), (value as num).toInt()),
      );
    } catch (_) {
      return {};
    }
  }

  Future<Duration?> _resumePositionFor(
    MediaItem item,
    Duration duration,
  ) async {
    if (!widget.settings.rememberPosition || !item.isLocal || kIsWeb) {
      return null;
    }
    final positions = await _readSavedPositions();
    final milliseconds = positions[item.url];
    if (milliseconds == null ||
        milliseconds < 10000 ||
        duration.inMilliseconds - milliseconds < 15000) {
      await _clearSavedPosition(item.url);
      return null;
    }
    return Duration(milliseconds: milliseconds);
  }

  Future<void> _savePlaybackPosition() async {
    final url = _activeUrl;
    final controller = _controller;
    if (!widget.settings.rememberPosition ||
        kIsWeb ||
        !_activeIsLocal ||
        url == null ||
        controller == null ||
        !controller.value.isInitialized) {
      return;
    }
    final value = controller.value;
    final positions = await _readSavedPositions();
    if (value.duration.inMilliseconds - value.position.inMilliseconds < 10000 ||
        value.position.inSeconds < 5) {
      positions.remove(url);
    } else {
      positions[url] = value.position.inMilliseconds;
    }
    while (positions.length > 100) {
      positions.remove(positions.keys.first);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_progressKey, jsonEncode(positions));
  }

  Future<void> _clearSavedPosition(String url) async {
    final positions = await _readSavedPositions();
    if (positions.remove(url) == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_progressKey, jsonEncode(positions));
  }

  void _handleControllerUpdate() {
    final controller = _controller;
    if (controller == null ||
        !controller.value.isCompleted ||
        _handlingCompletion) {
      return;
    }
    _handlingCompletion = true;
    unawaited(_handlePlaybackCompleted());
  }

  Future<void> _handlePlaybackCompleted() async {
    await _savePlaybackPosition();
    if (!mounted) return;
    if (_repeatMode == 2) {
      await _controller?.seekTo(Duration.zero);
      await _controller?.play();
      _handlingCompletion = false;
      return;
    }
    final shouldLoop = _repeatMode == 1;
    final nextIndex = _index + 1;
    if (nextIndex < widget.queue.length &&
        (widget.settings.autoPlayNext || _repeatMode == 1)) {
      await _changeTrack(nextIndex);
    } else if (shouldLoop && widget.queue.isNotEmpty) {
      await _changeTrack(0);
    } else {
      setState(() => _controlsVisible = true);
    }
  }

  void _startScrub(DragStartDetails details) {
    final controller = _controller;
    if (_locked || controller == null || !controller.value.isInitialized) {
      return;
    }
    _hideTimer?.cancel();
    _scrubStart = controller.value.position;
    _scrubTarget = _scrubStart;
    _scrubDeltaMilliseconds = 0;
    _gestureLabel = '拖动定位';
    _gestureIndicatorVisible = true;
  }

  void _updateScrub(DragUpdateDetails details) {
    final controller = _controller;
    final start = _scrubStart;
    if (controller == null || start == null) return;
    _scrubDeltaMilliseconds += details.delta.dx * 300;
    final duration = controller.value.duration.inMilliseconds;
    final target = (start.inMilliseconds + _scrubDeltaMilliseconds.round())
        .clamp(0, duration)
        .toInt();
    setState(() {
      _scrubTarget = Duration(milliseconds: target);
      _gestureLabel = '${_formatTime(_scrubTarget!)}  ·  拖动定位';
      _gestureIndicatorVisible = true;
    });
  }

  Future<void> _endScrub(DragEndDetails details) async {
    final target = _scrubTarget;
    _scrubStart = null;
    _scrubTarget = null;
    if (target != null) await _controller?.seekTo(target);
    if (mounted) setState(() => _gestureIndicatorVisible = false);
    _scheduleHide();
  }

  bool _volumeGesture = false;
  double _volumeAtDragStart = 1;

  void _startVerticalGesture(DragStartDetails details) {
    final width = MediaQuery.sizeOf(context).width;
    _volumeGesture = details.localPosition.dx >= width * .55 && !_locked;
    _volumeAtDragStart = _controller?.value.volume ?? _volume;
    if (_volumeGesture) {
      _hideTimer?.cancel();
      setState(() {
        _volume = _volumeAtDragStart;
        _gestureLabel = '音量 ${(100 * _volume).round()}%';
        _gestureIndicatorVisible = true;
      });
    }
  }

  void _updateVerticalGesture(DragUpdateDetails details) {
    if (!_volumeGesture || _locked) return;
    setState(() {
      _volume = (_volume - details.delta.dy / 180).clamp(0, 1).toDouble();
      _gestureLabel = '音量 ${(100 * _volume).round()}%';
      _gestureIndicatorVisible = true;
    });
    unawaited(_controller?.setVolume(_volume));
  }

  void _endVerticalGesture(DragEndDetails details) {
    if (!_volumeGesture) return;
    _volumeGesture = false;
    _gestureTimer?.cancel();
    _gestureTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _gestureIndicatorVisible = false);
    });
    _scheduleHide();
  }

  Future<void> _setTemporarySpeed(bool enabled) async {
    if (_locked) return;
    final speed = enabled ? 2.0 : _speed;
    if (enabled) {
      _hideTimer?.cancel();
      setState(() {
        _gestureLabel = '2.0x 快进';
        _gestureIndicatorVisible = true;
      });
    } else {
      setState(() => _gestureIndicatorVisible = false);
      _scheduleHide();
    }
    await _controller?.setPlaybackSpeed(speed);
  }

  Future<void> _showSubtitleOptions() async {
    _hideTimer?.cancel();
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 2, 20, 10),
              child: Text(
                _subtitleName == null ? '字幕' : '字幕 · $_subtitleName',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _ink,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.file_open_outlined),
              title: const Text('加载本地字幕'),
              subtitle: const Text('支持 SRT、VTT'),
              onTap: () => Navigator.pop(context, 'load'),
            ),
            if (_subtitles.isNotEmpty) ...[
              ListTile(
                leading: const Icon(Icons.fast_rewind_rounded),
                title: const Text('字幕提前 0.5 秒'),
                onTap: () => Navigator.pop(context, 'earlier'),
              ),
              ListTile(
                leading: const Icon(Icons.fast_forward_rounded),
                title: const Text('字幕延后 0.5 秒'),
                onTap: () => Navigator.pop(context, 'later'),
              ),
              ListTile(
                leading: const Icon(Icons.subtitles_off_outlined),
                title: const Text('关闭字幕'),
                onTap: () => Navigator.pop(context, 'off'),
              ),
            ],
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'load') {
      await _loadSubtitleFile();
    } else if (action == 'off') {
      setState(() {
        _subtitles = [];
        _subtitleName = null;
        _subtitleDelay = Duration.zero;
      });
    } else if (action == 'earlier') {
      setState(() => _subtitleDelay -= const Duration(milliseconds: 500));
    } else if (action == 'later') {
      setState(() => _subtitleDelay += const Duration(milliseconds: 500));
    }
    _scheduleHide();
  }

  Future<void> _cycleRepeatMode() async {
    setState(() => _repeatMode = (_repeatMode + 1) % 3);
    await widget.settings.copyWith(repeatMode: _repeatMode).save();
  }

  Future<void> _loadSubtitleFile() async {
    try {
      final files = await FilePicker.pickFiles(
        dialogTitle: '选择字幕文件',
        type: FileType.custom,
        allowedExtensions: const ['srt', 'vtt'],
      );
      if (files.isEmpty) return;
      final file = files.first;
      final bytes = await file.readAsBytes();
      final parsed = _SubtitleCue.parse(
        utf8.decode(bytes, allowMalformed: true),
      );
      if (parsed.isEmpty) throw Exception('没有识别到有效字幕时间轴');
      if (!mounted) return;
      setState(() {
        _subtitles = parsed;
        _subtitleName = file.name;
        _subtitleDelay = Duration.zero;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已加载字幕：${file.name}（${parsed.length} 条）')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '加载字幕失败：${error.toString().replaceFirst('Exception: ', '')}',
          ),
        ),
      );
    }
  }

  Future<void> _changeTrack(int index) async {
    if (index < 0 || index >= widget.queue.length) return;
    await _savePlaybackPosition();
    if (_fullscreen) await _leaveFullscreen();
    setState(() => _index = index);
    await _openCurrent();
  }

  Future<void> _showQueue() async {
    _hideTimer?.cancel();
    final index = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.white,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: math.min(MediaQuery.sizeOf(context).height * .7, 520),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 3, 20, 12),
                child: Text(
                  '播放列表',
                  style: TextStyle(
                    color: _ink,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: widget.queue.length,
                  itemBuilder: (context, index) {
                    final item = widget.queue[index];
                    return ListTile(
                      leading: Icon(
                        item.isAudio
                            ? Icons.music_note_rounded
                            : Icons.play_circle_outline_rounded,
                        color: index == _index ? const Color(0xFF659638) : _ink,
                      ),
                      title: Text(item.name, maxLines: 1),
                      subtitle: Text(item.isLocal ? '本地文件' : 'WebDAV'),
                      trailing: index == _index
                          ? const Icon(Icons.graphic_eq_rounded, color: _ink)
                          : null,
                      onTap: () => Navigator.pop(context, index),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (index != null && index != _index) await _changeTrack(index);
    _scheduleHide();
  }

  Future<void> _showSpeedPicker() async {
    _hideTimer?.cancel();
    final speed = await showModalBottomSheet<double>(
      context: context,
      backgroundColor: Colors.white,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 2, 20, 8),
              child: Text(
                '播放速度',
                style: TextStyle(
                  color: _ink,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            for (final speed in const [
              0.25,
              0.5,
              0.75,
              1.0,
              1.25,
              1.5,
              2.0,
              3.0,
              4.0,
            ])
              ListTile(
                title: Text('${speed}x'),
                trailing: speed == _speed
                    ? const Icon(Icons.check_rounded, color: _ink)
                    : null,
                onTap: () => Navigator.pop(context, speed),
              ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
    if (speed != null) {
      setState(() => _speed = speed);
      await _controller?.setPlaybackSpeed(speed);
    }
    _scheduleHide();
  }

  Future<void> _showDisplayPicker() async {
    _hideTimer?.cancel();
    final fit = await showModalBottomSheet<BoxFit>(
      context: context,
      backgroundColor: Colors.white,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 2, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '画面比例',
                  style: TextStyle(
                    color: _ink,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            _fitOption(context, '适应屏幕', BoxFit.contain),
            _fitOption(context, '铺满并裁切', BoxFit.cover),
            _fitOption(context, '拉伸画面', BoxFit.fill),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
    if (fit != null) setState(() => _fit = fit);
    _scheduleHide();
  }

  Future<void> _showSleepTimer() async {
    _hideTimer?.cancel();
    final minutes = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.white,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 2, 20, 8),
              child: Text(
                '定时停止',
                style: TextStyle(
                  color: _ink,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            for (final minutes in const [15, 30, 45, 60])
              ListTile(
                leading: const Icon(Icons.timer_outlined, color: _ink),
                title: Text('$minutes 分钟后停止'),
                onTap: () => Navigator.pop(context, minutes),
              ),
            ListTile(
              leading: const Icon(Icons.timer_off_outlined, color: _ink),
              title: const Text('关闭定时停止'),
              onTap: () => Navigator.pop(context, 0),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (minutes == null || !mounted) return;
    _sleepTimer?.cancel();
    if (minutes == 0) {
      setState(() {});
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已关闭定时停止')));
    } else {
      setState(() {});
      _sleepTimer = Timer(Duration(minutes: minutes), () async {
        await _controller?.pause();
        await _savePlaybackPosition();
        if (!mounted) return;
        setState(() => _controlsVisible = true);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('定时结束，已停止播放')));
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('将在 $minutes 分钟后停止播放')));
    }
    _scheduleHide();
  }

  Widget _fitOption(BuildContext context, String label, BoxFit fit) => ListTile(
    title: Text(label),
    trailing: fit == _fit ? const Icon(Icons.check_rounded, color: _ink) : null,
    onTap: () => Navigator.pop(context, fit),
  );

  @override
  Widget build(BuildContext context) {
    if (_fullscreen) {
      return PopScope<void>(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _leaveFullscreen();
        },
        child: Scaffold(
          backgroundColor: Colors.black,
          body: widget.settings.hideSystemUi
              ? _videoSurface(fullscreen: true)
              : SafeArea(child: _videoSurface(fullscreen: true)),
        ),
      );
    }
    return PopScope<void>(
      canPop: true,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F5F0),
        appBar: AppBar(
          leading: IconButton(
            onPressed: _handleBack,
            icon: const Icon(Icons.arrow_back_rounded, color: _ink),
          ),
          title: Text(
            _item.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: _ink,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          backgroundColor: const Color(0xFFF5F5F0),
          surfaceTintColor: Colors.transparent,
        ),
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              LayoutBuilder(
                builder: (context, constraints) => SizedBox(
                  height: _inlinePlayerHeight(context, constraints.maxWidth),
                  width: double.infinity,
                  child: _videoSurface(fullscreen: false),
                ),
              ),
              Expanded(child: _detailsPanel()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _videoSurface({required bool fullscreen}) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: _toggleControls,
    onHorizontalDragStart: _startScrub,
    onHorizontalDragUpdate: _updateScrub,
    onHorizontalDragEnd: _endScrub,
    onVerticalDragStart: _startVerticalGesture,
    onVerticalDragUpdate: _updateVerticalGesture,
    onVerticalDragEnd: _endVerticalGesture,
    onLongPressStart: (_) => unawaited(_setTemporarySpeed(true)),
    onLongPressEnd: (_) => unawaited(_setTemporarySpeed(false)),
    child: Stack(
      fit: StackFit.expand,
      children: [
        Container(color: Colors.black, child: _videoContent()),
        if (_controller != null && !_item.isAudio)
          Positioned.fill(
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onDoubleTap: _locked
                        ? null
                        : () => _seekBy(
                            Duration(seconds: -widget.settings.seekSeconds),
                          ),
                    child: const SizedBox.expand(),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onDoubleTap: _locked
                        ? null
                        : () => _seekBy(
                            Duration(seconds: widget.settings.seekSeconds),
                          ),
                    child: const SizedBox.expand(),
                  ),
                ),
              ],
            ),
          ),
        if (_subtitles.isNotEmpty && !_item.isAudio)
          _subtitleOverlay(fullscreen: fullscreen),
        if (_gestureIndicatorVisible && _gestureLabel != null)
          Positioned.fill(
            child: IgnorePointer(
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: .68),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Text(
                    _gestureLabel!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ),
        if (_controlsVisible) _controlsOverlay(fullscreen: fullscreen),
        if (_loading)
          const Center(child: CircularProgressIndicator(color: _green)),
        if (_error != null) _errorOverlay(),
        if (_locked && !_controlsVisible)
          Positioned(
            left: 16,
            top: 0,
            bottom: 0,
            child: Center(
              child: IconButton.filledTonal(
                tooltip: '显示控制按钮',
                onPressed: _toggleControls,
                icon: const Icon(Icons.lock_outline_rounded),
              ),
            ),
          ),
      ],
    ),
  );

  Widget _subtitleOverlay({required bool fullscreen}) => Positioned(
    left: 18,
    right: 18,
    bottom: fullscreen ? 82 : 12,
    child: IgnorePointer(
      child: ValueListenableBuilder<VideoPlayerValue>(
        valueListenable: _controller ?? _emptyController,
        builder: (context, value, child) {
          final position =
              value.position.inMilliseconds - _subtitleDelay.inMilliseconds;
          String? text;
          for (final cue in _subtitles) {
            if (position >= cue.startMilliseconds &&
                position <= cue.endMilliseconds) {
              text = cue.text;
              break;
            }
          }
          if (text == null || text.isEmpty) return const SizedBox.shrink();
          return Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: .72),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                text,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: widget.settings.subtitleFontSize,
                  height: 1.2,
                  fontWeight: FontWeight.w600,
                  shadows: const [Shadow(color: Colors.black, blurRadius: 3)],
                ),
              ),
            ),
          );
        },
      ),
    ),
  );

  Widget _videoContent() {
    final controller = _controller;
    if (_item.isAudio) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.graphic_eq_rounded, color: _green, size: 60),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                _item.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
          ],
        ),
      );
    }
    if (controller == null || !controller.value.isInitialized) {
      return const SizedBox.expand();
    }
    final size = controller.value.size;
    return Center(
      child: FittedBox(
        fit: _fit,
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: VideoPlayer(controller),
        ),
      ),
    );
  }

  Widget _controlsOverlay({required bool fullscreen}) => Positioned.fill(
    child: IgnorePointer(
      ignoring: false,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withValues(alpha: .62),
              Colors.transparent,
              Colors.black.withValues(alpha: .72),
            ],
            stops: const [0, .48, 1],
          ),
        ),
        child: Column(
          children: [
            _topControls(fullscreen),
            const Spacer(),
            _centerControls(),
            const Spacer(),
            _bottomControls(fullscreen),
          ],
        ),
      ),
    ),
  );

  Widget _topControls(bool fullscreen) => Padding(
    padding: EdgeInsets.fromLTRB(
      fullscreen ? 18 : 8,
      fullscreen ? 10 : 4,
      fullscreen ? 18 : 8,
      0,
    ),
    child: Row(
      children: [
        IconButton(
          tooltip: fullscreen ? '退出全屏' : '返回',
          onPressed: fullscreen ? _toggleFullscreen : _handleBack,
          icon: Icon(
            fullscreen ? Icons.close_rounded : Icons.arrow_back,
            color: Colors.white,
          ),
        ),
        Expanded(
          child: Text(
            _item.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        if (!_item.isAudio)
          IconButton(
            tooltip: _locked ? '解锁控制' : '锁定控制',
            onPressed: () {
              setState(() {
                _locked = !_locked;
                _controlsVisible = !_locked;
              });
              _scheduleHide();
            },
            icon: Icon(
              _locked ? Icons.lock_rounded : Icons.lock_open_rounded,
              color: Colors.white,
            ),
          ),
        if (!_item.isAudio)
          IconButton(
            tooltip: _subtitleName == null ? '加载字幕' : '字幕设置',
            onPressed: _showSubtitleOptions,
            icon: Icon(
              _subtitleName == null
                  ? Icons.subtitles_outlined
                  : Icons.subtitles_rounded,
              color: Colors.white,
            ),
          ),
        if (fullscreen && _isMobilePlatform)
          IconButton(
            tooltip: _fullscreenLandscape ? '切换竖屏' : '切换横屏',
            onPressed: _rotateFullscreen,
            icon: const Icon(
              Icons.screen_rotation_alt_rounded,
              color: Colors.white,
            ),
          ),
        IconButton(
          tooltip: '画面比例',
          onPressed: _showDisplayPicker,
          icon: const Icon(Icons.aspect_ratio_rounded, color: Colors.white),
        ),
      ],
    ),
  );

  Widget _centerControls() => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      IconButton(
        tooltip: '上一条',
        onPressed: _index > 0 ? () => _changeTrack(_index - 1) : null,
        icon: const Icon(
          Icons.skip_previous_rounded,
          color: Colors.white,
          size: 27,
        ),
      ),
      const SizedBox(width: 4),
      IconButton(
        tooltip: '后退 ${widget.settings.seekSeconds} 秒',
        onPressed: () =>
            _seekBy(Duration(seconds: -widget.settings.seekSeconds)),
        icon: const Icon(
          Icons.replay_10_rounded,
          color: Colors.white,
          size: 38,
        ),
      ),
      const SizedBox(width: 4),
      ValueListenableBuilder<VideoPlayerValue>(
        valueListenable: _controller ?? _emptyController,
        builder: (context, value, child) => Container(
          width: 57,
          height: 57,
          decoration: const BoxDecoration(
            color: _green,
            shape: BoxShape.circle,
          ),
          child: IconButton(
            tooltip: value.isPlaying ? '暂停' : '播放',
            onPressed: _togglePlay,
            icon: Icon(
              value.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              color: _ink,
              size: 34,
            ),
          ),
        ),
      ),
      const SizedBox(width: 4),
      IconButton(
        tooltip: '前进 ${widget.settings.seekSeconds} 秒',
        onPressed: () =>
            _seekBy(Duration(seconds: widget.settings.seekSeconds)),
        icon: const Icon(
          Icons.forward_10_rounded,
          color: Colors.white,
          size: 38,
        ),
      ),
      IconButton(
        tooltip: '下一条',
        onPressed: _index < widget.queue.length - 1
            ? () => _changeTrack(_index + 1)
            : null,
        icon: const Icon(
          Icons.skip_next_rounded,
          color: Colors.white,
          size: 27,
        ),
      ),
    ],
  );

  static final VideoPlayerController _emptyController =
      VideoPlayerController.networkUrl(Uri.parse('https://invalid.local/'));

  Widget _bottomControls(bool fullscreen) => Padding(
    padding: EdgeInsets.fromLTRB(
      fullscreen ? 24 : 14,
      0,
      fullscreen ? 24 : 14,
      fullscreen ? 15 : 9,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _positionSlider(),
        Row(
          children: [
            ValueListenableBuilder<VideoPlayerValue>(
              valueListenable: _controller ?? _emptyController,
              builder: (context, value, child) => Text(
                '${_formatTime(value.position)} / ${_formatTime(value.duration)}',
                style: const TextStyle(color: Colors.white70, fontSize: 10),
              ),
            ),
            const Spacer(),
            IconButton(
              tooltip: _sleepTimer?.isActive == true ? '关闭定时停止' : '定时停止',
              onPressed: _showSleepTimer,
              visualDensity: VisualDensity.compact,
              icon: Icon(
                _sleepTimer?.isActive == true
                    ? Icons.timer_rounded
                    : Icons.timer_outlined,
                color: _sleepTimer?.isActive == true ? _green : Colors.white,
                size: 20,
              ),
            ),
            IconButton(
              tooltip: switch (_repeatMode) {
                1 => '列表循环',
                2 => '单曲循环',
                _ => '不循环',
              },
              onPressed: _cycleRepeatMode,
              visualDensity: VisualDensity.compact,
              icon: Icon(
                _repeatMode == 2
                    ? Icons.repeat_one_rounded
                    : Icons.repeat_rounded,
                color: _repeatMode == 0 ? Colors.white : _green,
                size: 20,
              ),
            ),
            TextButton(
              onPressed: _showSpeedPicker,
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                minimumSize: const Size(42, 34),
                padding: const EdgeInsets.symmetric(horizontal: 6),
              ),
              child: Text(
                '${_speed}x',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            IconButton(
              tooltip: '播放列表',
              onPressed: _showQueue,
              visualDensity: VisualDensity.compact,
              icon: const Icon(
                Icons.queue_music_rounded,
                color: Colors.white,
                size: 21,
              ),
            ),
            IconButton(
              tooltip: fullscreen ? '退出全屏' : '全屏播放',
              onPressed: _toggleFullscreen,
              visualDensity: VisualDensity.compact,
              icon: Icon(
                fullscreen
                    ? Icons.fullscreen_exit_rounded
                    : Icons.fullscreen_rounded,
                color: Colors.white,
                size: 24,
              ),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _positionSlider() => ValueListenableBuilder<VideoPlayerValue>(
    valueListenable: _controller ?? _emptyController,
    builder: (context, value, child) {
      final duration = value.duration.inMilliseconds;
      final position = value.position.inMilliseconds.clamp(0, duration);
      return SliderTheme(
        data: SliderTheme.of(context).copyWith(
          trackHeight: 3,
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
          overlayShape: const RoundSliderOverlayShape(overlayRadius: 11),
          activeTrackColor: _green,
          inactiveTrackColor: Colors.white38,
          thumbColor: _green,
          overlayColor: _green.withValues(alpha: .18),
        ),
        child: Slider(
          min: 0,
          max: duration <= 0 ? 1 : duration.toDouble(),
          value: duration <= 0 ? 0 : position.toDouble(),
          onChangeStart: (_) => _hideTimer?.cancel(),
          onChanged: duration <= 0
              ? null
              : (milliseconds) => _controller?.seekTo(
                  Duration(milliseconds: milliseconds.round()),
                ),
          onChangeEnd: (_) => _scheduleHide(),
        ),
      );
    },
  );

  Widget _detailsPanel() => ListView(
    padding: const EdgeInsets.fromLTRB(20, 21, 20, 28),
    children: [
      Text(
        _item.name,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: _ink,
          fontSize: 19,
          fontWeight: FontWeight.w800,
        ),
      ),
      const SizedBox(height: 5),
      Text(
        _item.isLocal
            ? '本地文件 · ${_item.prettySize}'
            : 'WebDAV · ${_item.prettySize}',
        style: const TextStyle(color: Color(0xFF7E867D), fontSize: 12),
      ),
      const SizedBox(height: 19),
      Row(
        children: [
          Expanded(
            child: _actionButton(
              icon: Icons.replay_10_rounded,
              label: '后退 ${widget.settings.seekSeconds} 秒',
              onPressed: () =>
                  _seekBy(Duration(seconds: -widget.settings.seekSeconds)),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: _actionButton(
              icon: Icons.forward_10_rounded,
              label: '前进 ${widget.settings.seekSeconds} 秒',
              onPressed: () =>
                  _seekBy(Duration(seconds: widget.settings.seekSeconds)),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: _actionButton(
              icon: Icons.speed_rounded,
              label: '${_speed}x 速度',
              onPressed: _showSpeedPicker,
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          const Icon(Icons.volume_up_rounded, color: _ink, size: 18),
          Expanded(
            child: Slider(
              min: 0,
              max: 1,
              value: _volume.clamp(0, 1).toDouble(),
              activeColor: _ink,
              onChanged: (value) {
                setState(() => _volume = value);
                _controller?.setVolume(value);
              },
            ),
          ),
          Text(
            '${(_volume * 100).round()}%',
            style: const TextStyle(color: Color(0xFF7E867D), fontSize: 10),
          ),
        ],
      ),
      Container(
        margin: const EdgeInsets.only(top: 4, bottom: 12),
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: const Color(0xFFEDEFE8),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Text(
          '手势：双击左右跳转，横向拖动精确定位；长按 2 倍速，画面右侧上下滑动调音量。',
          style: TextStyle(color: Color(0xFF59635B), fontSize: 11, height: 1.4),
        ),
      ),
      if (!_item.isAudio)
        _actionButton(
          icon: Icons.subtitles_outlined,
          label: _subtitleName == null
              ? '加载外部字幕（SRT / VTT）'
              : '字幕：$_subtitleName',
          onPressed: _showSubtitleOptions,
          expanded: false,
        ),
      if (!_item.isAudio) const SizedBox(height: 10),
      _actionButton(
        icon: Icons.playlist_play_rounded,
        label: '打开播放列表（${widget.queue.length}）',
        onPressed: _showQueue,
        expanded: false,
      ),
      if (_error != null) ...[
        const SizedBox(height: 17),
        Text(
          _error!,
          style: const TextStyle(color: Color(0xFFB54736), fontSize: 12),
        ),
        TextButton(onPressed: _openCurrent, child: const Text('重试')),
      ],
    ],
  );

  Widget _actionButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    bool expanded = true,
  }) {
    final button = OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 17),
      label: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: _ink,
        backgroundColor: Colors.white,
        side: BorderSide.none,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
    return expanded ? SizedBox(width: double.infinity, child: button) : button;
  }

  Widget _errorOverlay() => Positioned.fill(
    child: Container(
      color: Colors.black.withValues(alpha: .82),
      padding: const EdgeInsets.all(22),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: Colors.white70,
              size: 34,
            ),
            const SizedBox(height: 10),
            const Text(
              '无法播放此文件',
              style: TextStyle(color: Colors.white, fontSize: 14),
            ),
            const SizedBox(height: 6),
            Text(
              _error!,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white60, fontSize: 10),
            ),
            const SizedBox(height: 10),
            FilledButton.tonal(
              onPressed: _openCurrent,
              child: const Text('重试'),
            ),
          ],
        ),
      ),
    ),
  );

  String _formatTime(Duration duration) {
    final seconds = duration.inSeconds;
    final hours = seconds ~/ 3600;
    final minutes = seconds ~/ 60 % 60;
    final remainder = seconds % 60;
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${remainder.toString().padLeft(2, '0')}';
    }
    return '${seconds ~/ 60}:${remainder.toString().padLeft(2, '0')}';
  }
}

class _SubtitleCue {
  const _SubtitleCue({
    required this.startMilliseconds,
    required this.endMilliseconds,
    required this.text,
  });

  final int startMilliseconds;
  final int endMilliseconds;
  final String text;

  static List<_SubtitleCue> parse(String source) {
    final lines = source
        .replaceFirst('\uFEFF', '')
        .replaceAll('\r', '')
        .split('\n');
    final cues = <_SubtitleCue>[];
    for (var index = 0; index < lines.length; index++) {
      final separator = lines[index].indexOf('-->');
      if (separator < 0) continue;
      final start = _parseTimestamp(lines[index].substring(0, separator));
      final end = _parseTimestamp(lines[index].substring(separator + 3));
      if (start == null || end == null || end <= start) continue;
      final textLines = <String>[];
      for (
        var textIndex = index + 1;
        textIndex < lines.length && lines[textIndex].trim().isNotEmpty;
        textIndex++
      ) {
        textLines.add(lines[textIndex]);
      }
      final text = textLines
          .join('\n')
          .replaceAll(RegExp(r'<[^>]+>'), '')
          .replaceAll('&nbsp;', ' ')
          .replaceAll('&amp;', '&')
          .replaceAll('&lt;', '<')
          .replaceAll('&gt;', '>')
          .trim();
      if (text.isNotEmpty) {
        cues.add(
          _SubtitleCue(
            startMilliseconds: start,
            endMilliseconds: end,
            text: text,
          ),
        );
      }
    }
    cues.sort((a, b) => a.startMilliseconds.compareTo(b.startMilliseconds));
    return cues;
  }

  static int? _parseTimestamp(String source) {
    final match = RegExp(
      r'(?:(\d{1,2}):)?(\d{1,2}):(\d{2})[,.](\d{1,3})',
    ).firstMatch(source.trim());
    if (match == null) return null;
    final hours = int.tryParse(match.group(1) ?? '0') ?? 0;
    final minutes = int.tryParse(match.group(2) ?? '') ?? 0;
    final seconds = int.tryParse(match.group(3) ?? '') ?? 0;
    final millis = int.tryParse((match.group(4) ?? '').padRight(3, '0')) ?? 0;
    return ((hours * 60 + minutes) * 60 + seconds) * 1000 + millis;
  }
}

