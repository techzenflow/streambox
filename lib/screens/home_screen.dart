import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:video_player/video_player.dart';

import '../models/media_item.dart';
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
  String _path = '/';
  String _filter = '全部';
  WebDavService? _service;
  List<MediaItem> _items = [];
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
          password: _pass.text);
      final items = await service.list('/');
      setState(() {
        _service = service;
        _items = items;
      });
    } catch (e) {
      setState(() => _error = _friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open(MediaItem item) async {
    if (item.isDirectory) {
      _browse(item);
      return;
    }
    if (!item.isMedia) {
      _showMessage('暂不支持此文件格式');
      return;
    }
    await _player?.dispose();
    setState(() {
      _playing = item;
      _player = null;
    });
    try {
      final uri = Uri.parse(item.url);
      final headers = <String, String>{};
      if (_user.text.isNotEmpty || _pass.text.isNotEmpty) {
        headers['Authorization'] =
            'Basic ${base64Encode(utf8.encode('${_user.text}:${_pass.text}'))}';
      }
      final controller =
          VideoPlayerController.networkUrl(uri, httpHeaders: headers);
      await controller.initialize();
      await controller.play();
      if (mounted) setState(() => _player = controller);
    } catch (e) {
      setState(() {
        _playing = null;
        _error = '无法播放此文件：${_friendlyError(e)}';
      });
    }
  }

  void _browse(MediaItem item) {
    final next = '$_path${_path.endsWith('/') ? '' : '/'}${item.name}/';
    setState(() {
      _path = next;
      _loading = true;
      _error = null;
    });
    _service!.list(next).then((items) {
      if (mounted) {
        setState(() {
          _items = items;
          _loading = false;
        });
      }
    }).catchError((Object e) {
      if (mounted) {
        setState(() {
          _error = _friendlyError(e);
          _loading = false;
        });
      }
    });
  }

  Future<void> _back() async {
    if (_path == '/') return;
    final parts = _path.split('/')..removeWhere((p) => p.isEmpty);
    if (parts.isNotEmpty) parts.removeLast();
    final next = parts.isEmpty ? '/' : '/${parts.join('/')}/';
    setState(() {
      _path = next;
      _loading = true;
    });
    try {
      final items = await _service!.list(next);
      setState(() => _items = items);
    } catch (e) {
      setState(() => _error = _friendlyError(e));
    }
    setState(() => _loading = false);
  }

  List<MediaItem> get _visible {
    final list =
        _items.where((item) => item.isDirectory || item.isMedia).toList();
    if (_filter == '视频') {
      return list.where((e) => e.isDirectory || e.isVideo).toList();
    }
    if (_filter == '音频') {
      return list.where((e) => e.isDirectory || e.isAudio).toList();
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    return Scaffold(
        body: SafeArea(
            child: Column(children: [
      _header(),
      Expanded(
          child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 6, 24, 24),
              child: wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                          SizedBox(width: 340, child: _libraryPanel()),
                          const SizedBox(width: 18),
                          Expanded(child: _playerPanel()),
                        ])
                  : Column(children: [
                      Expanded(
                          flex: _playing == null ? 1 : 2,
                          child: _libraryPanel()),
                      const SizedBox(height: 14),
                      if (_playing != null)
                        SizedBox(height: 220, child: _playerPanel())
                    ]))),
    ])));
  }

  Widget _header() => Padding(
      padding: const EdgeInsets.fromLTRB(26, 20, 26, 16),
      child: Row(children: [
        Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
                color: _green, borderRadius: BorderRadius.circular(13)),
            child: const Icon(Icons.play_arrow_rounded, color: _ink, size: 27)),
        const SizedBox(width: 11),
        const Text('streambox',
            style: TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w800,
                letterSpacing: -.7,
                color: _ink)),
        const Spacer(),
        Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
                color: Colors.white, borderRadius: BorderRadius.circular(30)),
            child: const Row(children: [
              Icon(Icons.cloud_outlined, size: 15),
              SizedBox(width: 7),
              Text('YOUR MEDIA, ANYWHERE',
                  style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2))
            ])),
      ]));

  Widget _libraryPanel() => Container(
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(25)),
      padding: const EdgeInsets.all(22),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('媒体库',
              style: TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w800, color: _ink)),
          const Spacer(),
          if (_service != null)
            IconButton(
                tooltip: '刷新',
                onPressed: _connect,
                icon: const Icon(Icons.refresh_rounded, size: 20))
        ]),
        const SizedBox(height: 3),
        Text(_service == null ? '连接你的 WebDAV 服务器' : _path,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: Colors.black.withValues(alpha: .48), fontSize: 12)),
        const SizedBox(height: 19),
        if (_service == null) ...[
          _field(_url, '服务器地址',
              hint: 'https://cloud.example.com/remote.php/dav/files/name/',
              icon: Icons.link_rounded),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
                child:
                    _field(_user, '用户名', icon: Icons.person_outline_rounded)),
            const SizedBox(width: 9),
            Expanded(
                child: _field(_pass, '密码',
                    icon: Icons.lock_outline_rounded, obscure: true))
          ]),
          const SizedBox(height: 13),
          SizedBox(
              width: double.infinity,
              height: 47,
              child: FilledButton(
                  onPressed: _loading ? null : _connect,
                  style: FilledButton.styleFrom(
                      backgroundColor: _ink,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14))),
                  child: _loading
                      ? const SizedBox(
                          width: 19,
                          height: 19,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: _green))
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                              Text('连接服务器'),
                              SizedBox(width: 8),
                              Icon(Icons.arrow_forward_rounded, size: 17)
                            ]))),
          const SizedBox(height: 18),
        ] else
          Row(children: [
            if (_path != '/')
              IconButton(
                  onPressed: _back,
                  icon: const Icon(Icons.arrow_back_rounded, size: 19)),
            Expanded(
                child: Text(
                    '${_visible.where((e) => !e.isDirectory).length} 个媒体文件',
                    style: TextStyle(
                        fontSize: 11,
                        color: Colors.black.withValues(alpha: .45)))),
            _filterMenu()
          ]),
        if (_error != null)
          Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(_error!,
                  style:
                      const TextStyle(fontSize: 12, color: Color(0xFFB54736)))),
        if (_service != null)
          Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _visible.isEmpty
                      ? _empty()
                      : ListView.separated(
                          itemCount: _visible.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 5),
                          itemBuilder: (context, index) =>
                              _mediaRow(_visible[index]))),
        if (_service == null) Expanded(child: _connectHint()),
      ]));

  Widget _field(TextEditingController ctl, String label,
          {String? hint, IconData? icon, bool obscure = false}) =>
      TextField(
          controller: ctl,
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
                  borderSide: BorderSide.none),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(13),
                  borderSide: BorderSide.none),
              labelStyle: const TextStyle(fontSize: 11)));

  Widget _filterMenu() => Wrap(
        spacing: 4,
        children: ['全部', '视频', '音频'].map((filter) {
          final selected = _filter == filter;
          return InkWell(
            onTap: () => setState(() => _filter = filter),
            borderRadius: BorderRadius.circular(20),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: selected ? _ink : const Color(0xFFF2F3EF),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(filter,
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: selected ? Colors.white : _ink)),
            ),
          );
        }).toList(),
      );

  Widget _mediaRow(MediaItem item) {
    final active = _playing?.url == item.url;
    return InkWell(
        onTap: () => _open(item),
        borderRadius: BorderRadius.circular(15),
        child: Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
                color: active ? const Color(0xFFF0F8E7) : Colors.transparent,
                borderRadius: BorderRadius.circular(15)),
            child: Row(children: [
              Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                      color: item.isDirectory
                          ? const Color(0xFFF1F0E8)
                          : const Color(0xFFE8F3DC),
                      borderRadius: BorderRadius.circular(12)),
                  child: Icon(
                      item.isDirectory
                          ? Icons.folder_rounded
                          : item.isAudio
                              ? Icons.music_note_rounded
                              : Icons.movie_outlined,
                      color: item.isDirectory
                          ? const Color(0xFF9B843D)
                          : const Color(0xFF527B30),
                      size: 20)),
              const SizedBox(width: 11),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: _ink)),
                    const SizedBox(height: 4),
                    Text(
                        item.isDirectory
                            ? '文件夹'
                            : '${item.extension.toUpperCase()} · ${item.prettySize}',
                        style: TextStyle(
                            fontSize: 10,
                            color: Colors.black.withValues(alpha: .45)))
                  ])),
              Icon(
                  active
                      ? Icons.equalizer_rounded
                      : item.isDirectory
                          ? Icons.chevron_right_rounded
                          : Icons.play_circle_outline_rounded,
                  color: active ? const Color(0xFF6C9F3A) : Colors.black26,
                  size: 20),
            ])));
  }

  Widget _playerPanel() => Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
          color: const Color(0xFF17211C),
          borderRadius: BorderRadius.circular(25)),
      child: _playing == null
          ? _playerPlaceholder()
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(
                  child: Center(
                      child: _player == null
                          ? const CircularProgressIndicator(color: _green)
                          : AspectRatio(
                              aspectRatio: _player!.value.aspectRatio,
                              child: VideoPlayer(_player!)))),
              Container(
                  padding: const EdgeInsets.fromLTRB(20, 15, 20, 18),
                  color: const Color(0xFF202C25),
                  child: Row(children: [
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text(_playing!.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700)),
                          const SizedBox(height: 4),
                          const Text('NOW PLAYING',
                              style: TextStyle(
                                  color: Colors.white54,
                                  fontSize: 9,
                                  letterSpacing: 1.4))
                        ])),
                    if (_player != null)
                      IconButton(
                          onPressed: () => setState(() =>
                              _player!.value.isPlaying
                                  ? _player!.pause()
                                  : _player!.play()),
                          icon: Icon(
                              _player!.value.isPlaying
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                              color: _green,
                              size: 27))
                  ])),
            ]));

  Widget _playerPlaceholder() => Stack(children: [
        Positioned(
            right: -80,
            top: -100,
            child: Container(
                width: 330,
                height: 330,
                decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _green.withValues(alpha: .05)))),
        Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 70,
              height: 70,
              decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .06),
                  borderRadius: BorderRadius.circular(23)),
              child: const Icon(Icons.play_arrow_rounded,
                  color: _green, size: 38)),
          const SizedBox(height: 18),
          const Text('准备好播放',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 7),
          const Text('从左侧媒体库选择一个视频',
              style: TextStyle(color: Colors.white54, fontSize: 12))
        ])),
        Positioned(
            left: 22,
            bottom: 20,
            child: Row(children: [
              Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                      color: _green, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              const Text('STREAMBOX PLAYER',
                  style: TextStyle(
                      color: Colors.white38, fontSize: 9, letterSpacing: 1.6))
            ]))
      ]);

  Widget _connectHint() => Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: 55,
            height: 55,
            decoration: BoxDecoration(
                color: const Color(0xFFF4F5F0),
                borderRadius: BorderRadius.circular(18)),
            child: const Icon(Icons.cloud_queue_rounded,
                color: Color(0xFF8D9A81), size: 25)),
        const SizedBox(height: 13),
        Text('连接后开始探索',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: _ink.withValues(alpha: .8))),
        const SizedBox(height: 5),
        Text('支持标准 WebDAV 服务器',
            style: TextStyle(
                fontSize: 10, color: Colors.black.withValues(alpha: .4)))
      ]));
  Widget _empty() => Center(
      child: Text('这个文件夹里没有媒体文件',
          style: TextStyle(
              fontSize: 12, color: Colors.black.withValues(alpha: .45))));
  void _showMessage(String message) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(message)));
  String _friendlyError(Object e) => e
      .toString()
      .replaceFirst('Exception: ', '')
      .replaceFirst('DioException [bad response]: ', '服务器返回异常：');
}
