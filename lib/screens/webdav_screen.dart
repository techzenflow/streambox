import 'dart:convert';

import 'package:flutter/material.dart';

import '../models/media_item.dart';
import '../services/webdav_service.dart';

const _green = Color(0xFFB9F36B);
const _ink = Color(0xFF19251F);

class WebDavPlayback {
  const WebDavPlayback({
    required this.queue,
    required this.index,
    required this.headers,
  });

  final List<MediaItem> queue;
  final int index;
  final Map<String, String> headers;
}

class WebDavScreen extends StatefulWidget {
  const WebDavScreen({super.key});

  @override
  State<WebDavScreen> createState() => _WebDavScreenState();
}

class _WebDavScreenState extends State<WebDavScreen> {
  final _url = TextEditingController();
  final _user = TextEditingController();
  final _password = TextEditingController();
  final _search = TextEditingController();

  WebDavService? _service;
  List<MediaItem> _items = [];
  String _path = '/';
  String _filter = '全部';
  String? _error;
  bool _loading = false;

  @override
  void dispose() {
    _url.dispose();
    _user.dispose();
    _password.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final address = _url.text.trim();
    final uri = Uri.tryParse(address);
    if (uri == null ||
        !uri.hasAuthority ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      setState(() => _error = '请输入有效的 HTTP 或 HTTPS WebDAV 地址');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _path = '/';
    });
    final service = WebDavService(
      baseUrl: address,
      username: _user.text,
      password: _password.text,
    );
    try {
      final items = await service.list('/');
      if (!mounted) return;
      setState(() {
        _service = service;
        _items = items;
      });
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadPath(String path) async {
    final service = _service;
    if (service == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await service.list(path);
      if (!mounted) return;
      setState(() {
        _items = items;
        _path = path;
        _search.clear();
      });
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openFolder(MediaItem folder) async {
    final next = '$_path${_path.endsWith('/') ? '' : '/'}${folder.name}/';
    await _loadPath(next);
  }

  Future<void> _goUp() async {
    final parts = _path.split('/')..removeWhere((part) => part.isEmpty);
    if (parts.isEmpty) return;
    parts.removeLast();
    await _loadPath(parts.isEmpty ? '/' : '/${parts.join('/')}/');
  }

  List<MediaItem> get _visibleItems {
    final query = _search.text.trim().toLowerCase();
    return _items.where((item) {
      if (item.isDirectory) return true;
      if (!item.isMedia) return false;
      if (_filter == '视频' && !item.isVideo) return false;
      if (_filter == '音频' && !item.isAudio) return false;
      return query.isEmpty || item.name.toLowerCase().contains(query);
    }).toList();
  }

  List<MediaItem> get _playableItems =>
      _visibleItems.where((item) => !item.isDirectory && item.isMedia).toList();

  void _play(MediaItem item) {
    final queue = _playableItems;
    final index = queue.indexWhere((entry) => entry.url == item.url);
    Navigator.of(context).pop(
      WebDavPlayback(
        queue: queue,
        index: index < 0 ? 0 : index,
        headers: _headers,
      ),
    );
  }

  Map<String, String> get _headers {
    if (_user.text.isEmpty && _password.text.isEmpty) return const {};
    return {
      'Authorization':
          'Basic ${base64Encode(utf8.encode('${_user.text}:${_password.text}'))}',
    };
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF5F5F0),
    appBar: AppBar(
      title: const Text(
        'WebDAV',
        style: TextStyle(
          color: _ink,
          fontSize: 16,
          fontWeight: FontWeight.w800,
        ),
      ),
      backgroundColor: const Color(0xFFF5F5F0),
      surfaceTintColor: Colors.transparent,
      actions: [
        if (_service != null)
          IconButton(
            tooltip: '编辑连接',
            onPressed: () => setState(() {
              _service = null;
              _items = [];
              _path = '/';
            }),
            icon: const Icon(Icons.edit_outlined, color: _ink),
          ),
      ],
    ),
    body: SafeArea(
      top: false,
      child: _service == null ? _connectionForm() : _browser(),
    ),
  );

  Widget _connectionForm() => ListView(
    padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
    children: [
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: _ink,
          borderRadius: BorderRadius.circular(23),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.cloud_outlined, color: _green, size: 29),
            SizedBox(height: 13),
            Text(
              '连接远程媒体库',
              style: TextStyle(
                color: Colors.white,
                fontSize: 19,
                fontWeight: FontWeight.w800,
              ),
            ),
            SizedBox(height: 6),
            Text(
              '输入服务器地址和凭据，浏览并播放 WebDAV 上的视频。',
              style: TextStyle(color: Colors.white60, fontSize: 11),
            ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      _field(
        controller: _url,
        label: 'WebDAV 地址',
        hint: 'https://cloud.example.com/remote.php/dav/files/name/',
        icon: Icons.link_rounded,
      ),
      const SizedBox(height: 11),
      _field(
        controller: _user,
        label: '用户名',
        icon: Icons.person_outline_rounded,
      ),
      const SizedBox(height: 11),
      _field(
        controller: _password,
        label: '密码或应用专用密码',
        icon: Icons.lock_outline_rounded,
        obscure: true,
      ),
      if (_error != null) ...[
        const SizedBox(height: 11),
        Text(
          _error!,
          style: const TextStyle(color: Color(0xFFB54736), fontSize: 12),
        ),
      ],
      const SizedBox(height: 16),
      SizedBox(
        height: 50,
        child: FilledButton.icon(
          onPressed: _loading ? null : _connect,
          icon: _loading
              ? const SizedBox(
                  width: 17,
                  height: 17,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _green,
                  ),
                )
              : const Icon(Icons.cloud_sync_outlined),
          label: Text(_loading ? '正在连接…' : '连接并浏览'),
          style: FilledButton.styleFrom(
            backgroundColor: _ink,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
          ),
        ),
      ),
      const SizedBox(height: 14),
      const Text(
        '账号信息只在本次连接中使用，离开页面后不会保存。',
        textAlign: TextAlign.center,
        style: TextStyle(color: Color(0xFF858D83), fontSize: 10),
      ),
    ],
  );

  Widget _browser() => Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
        child: Row(
          children: [
            if (_path != '/')
              IconButton(
                tooltip: '上一级',
                onPressed: _goUp,
                icon: const Icon(Icons.arrow_upward_rounded, color: _ink),
              ),
            Expanded(
              child: Text(
                _path,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFF7D867C), fontSize: 11),
              ),
            ),
            IconButton(
              tooltip: '刷新',
              onPressed: () => _loadPath(_path),
              icon: const Icon(Icons.refresh_rounded, color: _ink),
            ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: TextField(
          controller: _search,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: '搜索当前文件夹',
            prefixIcon: const Icon(Icons.search_rounded, size: 19),
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(vertical: 11),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ),
      const SizedBox(height: 10),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: Row(
          children: ['全部', '视频', '音频'].map((filter) {
            final selected = _filter == filter;
            return Padding(
              padding: const EdgeInsets.only(right: 7),
              child: ChoiceChip(
                label: Text(filter),
                selected: selected,
                onSelected: (_) => setState(() => _filter = filter),
                selectedColor: _green,
                backgroundColor: Colors.white,
                side: BorderSide.none,
                labelStyle: TextStyle(
                  color: _ink,
                  fontSize: 10,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                ),
              ),
            );
          }).toList(),
        ),
      ),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 6, 18, 6),
          child: Text(
            _error!,
            style: const TextStyle(color: Color(0xFFB54736), fontSize: 11),
          ),
        ),
      Expanded(
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: _ink))
            : _visibleItems.isEmpty
            ? const Center(
                child: Text(
                  '没有找到媒体文件',
                  style: TextStyle(color: Color(0xFF858D83), fontSize: 12),
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                itemCount: _visibleItems.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (context, index) =>
                    _mediaRow(_visibleItems[index]),
              ),
      ),
    ],
  );

  Widget _mediaRow(MediaItem item) => Material(
    color: Colors.white,
    borderRadius: BorderRadius.circular(15),
    child: InkWell(
      onTap: item.isDirectory ? () => _openFolder(item) : () => _play(item),
      borderRadius: BorderRadius.circular(15),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            Container(
              width: 43,
              height: 43,
              decoration: BoxDecoration(
                color: item.isDirectory
                    ? const Color(0xFFF4F0E5)
                    : const Color(0xFFF0F4EA),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                item.isDirectory
                    ? Icons.folder_rounded
                    : item.isAudio
                    ? Icons.music_note_rounded
                    : Icons.movie_outlined,
                color: item.isDirectory ? const Color(0xFF998143) : _ink,
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
                      color: _ink,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.isDirectory
                        ? '文件夹'
                        : '${item.extension.toUpperCase()} · ${item.prettySize}',
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Color(0xFF9AA197)),
          ],
        ),
      ),
    ),
  );

  Widget _field({
    required TextEditingController controller,
    required String label,
    String? hint,
    required IconData icon,
    bool obscure = false,
  }) => TextField(
    controller: controller,
    obscureText: obscure,
    autocorrect: false,
    keyboardType: label == 'WebDAV 地址' ? TextInputType.url : null,
    style: const TextStyle(color: _ink, fontSize: 12),
    decoration: InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon, size: 18),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
    ),
  );

  String _friendlyError(Object error) => error
      .toString()
      .replaceFirst('Exception: ', '')
      .replaceFirst('DioException [bad response]: ', '服务器返回异常：');
}

