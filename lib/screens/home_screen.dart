import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../models/media_item.dart';
import '../services/local_video_controller.dart';
import '../services/webdav_service.dart';

const _green = Color(0xFFB9F36B);
const _ink = Color(0xFF19251F);

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _url = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();

  String _source = 'local';
  String _path = '/';
  String _filter = '全部';
  WebDavService? _service;
  List<MediaItem> _webDavItems = [];
  final List<MediaItem> _recentLocal = [];
  MediaItem? _playing;
  VideoPlayerController? _player;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _url.dispose();
    _user.dispose();
    _pass.dispose();
    _player?.dispose();
    super.dispose();
  }

  Future<void> _pickLocalVideo() async {
    try {
      final file = await FilePicker.pickFile(type: FileType.video);
      if (file == null) return;

      final path = kIsWeb ? file.uri.toString() : file.path;
      if (path == null || path.isEmpty) {
        _showMessage('无法读取这个视频文件');
        return;
      }

      final item = MediaItem(
        name: file.name,
        url: path,
        size: 0,
        modified: null,
        isLocal: true,
      );
      setState(() {
        _source = 'local';
        _recentLocal.removeWhere((recent) => recent.url == item.url);
        _recentLocal.insert(0, item);
        _error = null;
      });
      await _play(item);
    } catch (error) {
      if (mounted) _showMessage('打开视频失败：${_friendlyError(error)}');
    }
  }

  Future<void> _play(MediaItem item) async {
    if (item.isDirectory) {
      await _browse(item);
      return;
    }
    if (!item.isMedia) {
      _showMessage('暂不支持此文件格式');
      return;
    }

    final oldPlayer = _player;
    setState(() {
      _playing = item;
      _player = null;
      _error = null;
    });
    await oldPlayer?.dispose();

    VideoPlayerController? controller;
    try {
      if (item.isLocal && !kIsWeb) {
        controller = createLocalVideoController(item.url);
      } else {
        final headers = <String, String>{};
        if (!item.isLocal && (_user.text.isNotEmpty || _pass.text.isNotEmpty)) {
          headers['Authorization'] =
              'Basic ${base64Encode(utf8.encode('${_user.text}:${_pass.text}'))}';
        }
        controller = VideoPlayerController.networkUrl(
          Uri.parse(item.url),
          httpHeaders: headers,
        );
      }
      await controller.initialize();
      await controller.play();
      if (mounted) setState(() => _player = controller);
    } catch (error) {
      await controller?.dispose();
      if (!mounted) return;
      setState(() {
        _playing = null;
        _error = '无法播放此文件：${_friendlyError(error)}';
      });
    }
  }

  Future<void> _connect() async {
    if (_url.text.trim().isEmpty) {
      _showMessage('请输入 WebDAV 地址');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _path = '/';
    });
    try {
      final service = WebDavService(
        baseUrl: _url.text.trim(),
        username: _user.text,
        password: _pass.text,
      );
      final items = await service.list('/');
      if (!mounted) return;
      setState(() {
        _service = service;
        _webDavItems = items;
      });
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _browse(MediaItem folder) async {
    if (_service == null) return;
    final next = '$_path${_path.endsWith('/') ? '' : '/'}${folder.name}/';
    await _loadWebDavPath(next);
  }

  Future<void> _back() async {
    if (_path == '/') return;
    final parts = _path.split('/')..removeWhere((part) => part.isEmpty);
    if (parts.isNotEmpty) parts.removeLast();
    final next = parts.isEmpty ? '/' : '/${parts.join('/')}/';
    await _loadWebDavPath(next);
  }

  Future<void> _loadWebDavPath(String path) async {
    if (_service == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await _service!.list(path);
      if (!mounted) return;
      setState(() {
        _path = path;
        _webDavItems = items;
      });
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<MediaItem> get _visibleWebDavItems {
    final items = _webDavItems
        .where((item) => item.isDirectory || item.isMedia)
        .toList();
    if (_filter == '视频') {
      return items.where((item) => item.isDirectory || item.isVideo).toList();
    }
    if (_filter == '音频') {
      return items.where((item) => item.isDirectory || item.isAudio).toList();
    }
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _header(),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 6, 24, 24),
                child: wide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(width: 350, child: _libraryPanel()),
                          const SizedBox(width: 18),
                          Expanded(child: _playerPanel()),
                        ],
                      )
                    : Column(
                        children: [
                          Expanded(flex: 3, child: _playerPanel()),
                          const SizedBox(height: 12),
                          Expanded(flex: 2, child: _libraryPanel()),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header() => Padding(
        padding: const EdgeInsets.fromLTRB(26, 20, 26, 16),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: _green,
                borderRadius: BorderRadius.circular(13),
              ),
              child: const Icon(Icons.play_arrow_rounded, color: _ink, size: 27),
            ),
            const SizedBox(width: 11),
            const Text(
              'streambox',
              style: TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w800,
                letterSpacing: -.7,
                color: _ink,
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(30),
              ),
              child: const Row(
                children: [
                  Icon(Icons.folder_open_rounded, size: 15),
                  SizedBox(width: 7),
                  Text(
                    'LOCAL VIDEO PLAYER',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _libraryPanel() => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(25),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  '媒体库',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: _ink,
                  ),
                ),
                const Spacer(),
                if (_source == 'webdav' && _service != null)
                  IconButton(
                    tooltip: '刷新',
                    onPressed: _connect,
                    icon: const Icon(Icons.refresh_rounded, size: 20),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            _sourceSwitcher(),
            const SizedBox(height: 16),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  _error!,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFFB54736),
                  ),
                ),
              ),
            Expanded(
              child: _source == 'local' ? _localLibrary() : _webDavLibrary(),
            ),
          ],
        ),
      );

  Widget _sourceSwitcher() => Row(
        children: [
          Expanded(child: _sourceButton('local', '本地视频', Icons.folder_rounded)),
          const SizedBox(width: 8),
          Expanded(child: _sourceButton('webdav', 'WebDAV', Icons.cloud_outlined)),
        ],
      );

  Widget _sourceButton(String source, String label, IconData icon) {
    final selected = _source == source;
    return InkWell(
      onTap: () => setState(() {
        _source = source;
        _error = null;
      }),
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
        decoration: BoxDecoration(
          color: selected ? _ink : const Color(0xFFF4F5F0),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: selected ? _green : _ink),
            const SizedBox(width: 7),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: selected ? Colors.white : _ink,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _localLibrary() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton.icon(
            onPressed: _pickLocalVideo,
            icon: const Icon(Icons.video_file_outlined, size: 19),
            label: const Text('打开本地视频'),
            style: FilledButton.styleFrom(
              backgroundColor: _ink,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 15),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
            ),
          ),
          const SizedBox(height: 19),
          Row(
            children: [
              const Text(
                '最近打开',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: _ink,
                ),
              ),
              const Spacer(),
              Text(
                '本次会话 ${_recentLocal.length}',
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.black.withValues(alpha: .4),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _recentLocal.isEmpty
                ? _localHint()
                : ListView.separated(
                    itemCount: _recentLocal.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 5),
                    itemBuilder: (context, index) =>
                        _mediaRow(_recentLocal[index]),
                  ),
          ),
        ],
      );

  Widget _webDavLibrary() {
    if (_service == null) {
      return SingleChildScrollView(
        child: Column(
          children: [
            _field(
              _url,
              'WebDAV 地址',
              hint: 'https://cloud.example.com/remote.php/dav/files/name/',
              icon: Icons.link_rounded,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _field(
                    _user,
                    '用户名',
                    icon: Icons.person_outline_rounded,
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: _field(
                    _pass,
                    '密码',
                    icon: Icons.lock_outline_rounded,
                    obscure: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 45,
              child: FilledButton(
                onPressed: _loading ? null : _connect,
                style: FilledButton.styleFrom(
                  backgroundColor: _ink,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: _loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: _green,
                        ),
                      )
                    : const Text('连接 WebDAV'),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'WebDAV 是可选网络媒体库；本地文件可直接播放。',
              style: TextStyle(
                fontSize: 10,
                color: Colors.black.withValues(alpha: .42),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Row(
          children: [
            if (_path != '/')
              IconButton(
                onPressed: _back,
                icon: const Icon(Icons.arrow_back_rounded, size: 19),
              ),
            Expanded(
              child: Text(
                _path,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.black.withValues(alpha: .45),
                ),
              ),
            ),
            _filterMenu(),
          ],
        ),
        const SizedBox(height: 5),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _visibleWebDavItems.isEmpty
                  ? _webDavEmpty()
                  : ListView.separated(
                      itemCount: _visibleWebDavItems.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 5),
                      itemBuilder: (context, index) =>
                          _mediaRow(_visibleWebDavItems[index]),
                    ),
        ),
      ],
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    String? hint,
    IconData? icon,
    bool obscure = false,
  }) =>
      TextField(
        controller: controller,
        obscureText: obscure,
        style: const TextStyle(fontSize: 12),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon: icon == null ? null : Icon(icon, size: 16),
          filled: true,
          fillColor: const Color(0xFFF6F7F3),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(13),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(13),
            borderSide: BorderSide.none,
          ),
          labelStyle: const TextStyle(fontSize: 11),
        ),
      );

  Widget _filterMenu() => Wrap(
        spacing: 4,
        children: ['全部', '视频', '音频'].map((filter) {
          final selected = _filter == filter;
          return InkWell(
            onTap: () => setState(() => _filter = filter),
            borderRadius: BorderRadius.circular(20),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
              decoration: BoxDecoration(
                color: selected ? _ink : const Color(0xFFF2F3EF),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                filter,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : _ink,
                ),
              ),
            ),
          );
        }).toList(),
      );

  Widget _mediaRow(MediaItem item) {
    final active = _playing?.url == item.url;
    return InkWell(
      onTap: () => _play(item),
      borderRadius: BorderRadius.circular(15),
      child: Container(
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          color: active ? const Color(0xFFF0F8E7) : Colors.transparent,
          borderRadius: BorderRadius.circular(15),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: item.isDirectory
                    ? const Color(0xFFF1F0E8)
                    : const Color(0xFFE8F3DC),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                item.isDirectory
                    ? Icons.folder_rounded
                    : item.isAudio
                        ? Icons.music_note_rounded
                        : Icons.movie_outlined,
                color: item.isDirectory
                    ? const Color(0xFF9B843D)
                    : const Color(0xFF527B30),
                size: 20,
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _ink,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.isDirectory
                        ? '文件夹'
                        : '${item.extension.toUpperCase()} · ${item.prettySize}',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.black.withValues(alpha: .45),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              active
                  ? Icons.equalizer_rounded
                  : item.isDirectory
                      ? Icons.chevron_right_rounded
                      : Icons.play_circle_outline_rounded,
              color: active ? const Color(0xFF6C9F3A) : Colors.black26,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Widget _playerPanel() => Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: const Color(0xFF17211C),
          borderRadius: BorderRadius.circular(25),
        ),
        child: _playing == null
            ? _playerPlaceholder()
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Center(
                      child: _player == null
                          ? const CircularProgressIndicator(color: _green)
                          : _playing!.isAudio
                              ? _audioPlaceholder()
                              : AspectRatio(
                                  aspectRatio: _player!.value.aspectRatio,
                                  child: VideoPlayer(_player!),
                                ),
                    ),
                  ),
                  if (_player != null && _playing!.isVideo)
                    VideoProgressIndicator(
                      _player!,
                      allowScrubbing: true,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      colors: const VideoProgressColors(
                        playedColor: _green,
                        bufferedColor: Colors.white30,
                        backgroundColor: Colors.white12,
                      ),
                    ),
                  Container(
                    padding: const EdgeInsets.fromLTRB(20, 12, 16, 14),
                    color: const Color(0xFF202C25),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _playing!.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _playing!.isLocal ? '本地文件' : 'WEBDAV STREAM',
                                style: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 9,
                                  letterSpacing: 1.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (_player != null)
                          ValueListenableBuilder<VideoPlayerValue>(
                            valueListenable: _player!,
                            builder: (context, value, child) => IconButton(
                              tooltip: value.isPlaying ? '暂停' : '播放',
                              onPressed: () => value.isPlaying
                                  ? _player!.pause()
                                  : _player!.play(),
                              icon: Icon(
                                value.isPlaying
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                                color: _green,
                                size: 29,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
      );

  Widget _playerPlaceholder() => Stack(
        children: [
          Positioned(
            right: -80,
            top: -100,
            child: Container(
              width: 330,
              height: 330,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _green.withValues(alpha: .05),
              ),
            ),
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .06),
                    borderRadius: BorderRadius.circular(23),
                  ),
                  child: const Icon(
                    Icons.play_arrow_rounded,
                    color: _green,
                    size: 38,
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  '播放本地视频',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 7),
                const Text(
                  '选择设备中的视频文件即可开始播放',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: _pickLocalVideo,
                  icon: const Icon(Icons.folder_open_rounded, size: 17),
                  label: const Text('选择视频'),
                  style: FilledButton.styleFrom(
                    backgroundColor: _green,
                    foregroundColor: _ink,
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 22,
            bottom: 20,
            child: Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                    color: _green,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'STREAMBOX PLAYER',
                  style: TextStyle(
                    color: Colors.white38,
                    fontSize: 9,
                    letterSpacing: 1.6,
                  ),
                ),
              ],
            ),
          ),
        ],
      );

  Widget _audioPlaceholder() => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .06),
              borderRadius: BorderRadius.circular(28),
            ),
            child: const Icon(Icons.graphic_eq_rounded, color: _green, size: 48),
          ),
          const SizedBox(height: 16),
          Text(
            _playing!.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
        ],
      );

  Widget _localHint() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.video_library_outlined, color: Color(0xFF9AA394), size: 29),
            const SizedBox(height: 10),
            Text(
              '最近播放的视频会显示在这里',
              style: TextStyle(
                fontSize: 11,
                color: Colors.black.withValues(alpha: .46),
              ),
            ),
          ],
        ),
      );

  Widget _webDavEmpty() => Center(
        child: Text(
          '这个文件夹里没有媒体文件',
          style: TextStyle(
            fontSize: 12,
            color: Colors.black.withValues(alpha: .45),
          ),
        ),
      );

  void _showMessage(String message) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(message)));

  String _friendlyError(Object error) => error
      .toString()
      .replaceFirst('Exception: ', '')
      .replaceFirst('DioException [bad response]: ', '服务器返回异常：');
}
