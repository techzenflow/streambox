import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../models/media_item.dart';
import '../models/player_settings.dart';
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
  VideoPlayerController? _controller;
  late int _index = widget.initialIndex;
  late double _speed = widget.settings.defaultSpeed;
  BoxFit _fit = BoxFit.contain;
  bool _loading = true;
  bool _fullscreen = false;
  bool _controlsVisible = true;
  bool _locked = false;
  String? _error;
  Timer? _hideTimer;
  Timer? _sleepTimer;

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
    final previous = _controller;
    _hideTimer?.cancel();
    setState(() {
      _controller = null;
      _loading = true;
      _error = null;
      _controlsVisible = true;
    });
    await previous?.dispose();

    VideoPlayerController? next;
    try {
      if (_item.isLocal && !kIsWeb) {
        next = createLocalVideoController(_item.url);
      } else {
        next = VideoPlayerController.networkUrl(
          Uri.parse(_item.url),
          httpHeaders: widget.headers,
        );
      }
      await next.initialize();
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
    if (_isMobilePlatform && widget.settings.landscapeOnFullscreen) {
      await SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
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
    if (_isMobilePlatform && widget.settings.landscapeOnFullscreen) {
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
      _hideTimer?.cancel();
      if (mounted) setState(() => _controlsVisible = true);
    } else {
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

  Future<void> _changeTrack(int index) async {
    if (index < 0 || index >= widget.queue.length) return;
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
              AspectRatio(
                aspectRatio: 16 / 9,
                child: _videoSurface(fullscreen: false),
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
                    onDoubleTap: () => _seekBy(const Duration(seconds: -10)),
                    child: const SizedBox.expand(),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onDoubleTap: () => _seekBy(const Duration(seconds: 10)),
                    child: const SizedBox.expand(),
                  ),
                ),
              ],
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
        tooltip: '后退 10 秒',
        onPressed: () => _seekBy(const Duration(seconds: -10)),
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
        tooltip: '前进 10 秒',
        onPressed: () => _seekBy(const Duration(seconds: 10)),
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
              label: '后退 10 秒',
              onPressed: () => _seekBy(const Duration(seconds: -10)),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: _actionButton(
              icon: Icons.forward_10_rounded,
              label: '前进 10 秒',
              onPressed: () => _seekBy(const Duration(seconds: 10)),
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

