import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/media_item.dart';
import '../models/player_settings.dart';
import 'local_media_scan.dart';
import 'player_screen.dart';
import 'settings_screen.dart';
import 'webdav_screen.dart';

const _green = Color(0xFFB9F36B);
const _ink = Color(0xFF19251F);

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _historyKey = 'streambox.localHistory';
  static const _libraryKey = 'streambox.localLibrary';
  static const _favoritesKey = 'streambox.favoriteMedia';

  int _tab = 0;
  bool _loading = true;
  bool _scanning = false;
  bool _showAllLibrary = false;
  PlayerSettings _settings = const PlayerSettings();
  List<MediaItem> _recent = [];
  List<MediaItem> _library = [];
  Set<String> _favorites = {};
  final TextEditingController _librarySearch = TextEditingController();
  String _libraryFilter = '全部';
  String _librarySort = '最近添加';

  bool get _supportsFolderScan =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.linux);

  @override
  void initState() {
    super.initState();
    _loadSavedData();
  }

  @override
  void dispose() {
    _librarySearch.dispose();
    super.dispose();
  }

  Future<void> _loadSavedData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final settings = await PlayerSettings.load();
      final raw = prefs.getString(_historyKey);
      final decoded = raw == null ? <dynamic>[] : jsonDecode(raw) as List;
      final recent = decoded.whereType<Map>().map(_itemFromJson).toList();
      final savedLibrary = prefs.getString(_libraryKey);
      final libraryJson = savedLibrary == null
          ? <dynamic>[]
          : jsonDecode(savedLibrary) as List;
      final favorites = prefs.getStringList(_favoritesKey) ?? const <String>[];
      if (!settings.saveHistory) recent.clear();
      if (!mounted) return;
      setState(() {
        _settings = settings;
        _recent = recent;
        _library = libraryJson.whereType<Map>().map(_itemFromJson).toList();
        _favorites = favorites.toSet();
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  MediaItem _itemFromJson(Map<dynamic, dynamic> entry) => MediaItem(
    name: entry['name'] as String? ?? '视频',
    url: entry['url'] as String? ?? '',
    size: entry['size'] as int? ?? 0,
    modified: DateTime.tryParse(entry['modified'] as String? ?? ''),
    isLocal: true,
  );

  Map<String, Object?> _itemToJson(MediaItem item) => {
    'name': item.name,
    'url': item.url,
    'size': item.size,
    'modified': item.modified?.toIso8601String(),
  };

  Future<void> _saveLibrary() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _libraryKey,
      jsonEncode(_library.map(_itemToJson).toList()),
    );
    await prefs.setStringList(_favoritesKey, _favorites.toList());
  }

  Future<void> _saveHistory() async {
    final prefs = await SharedPreferences.getInstance();
    if (!_settings.saveHistory || kIsWeb) {
      await prefs.remove(_historyKey);
      return;
    }
    final value = _recent
        .map((item) => {'name': item.name, 'url': item.url, 'size': item.size})
        .toList();
    await prefs.setString(_historyKey, jsonEncode(value));
  }

  Future<void> _openVideos() async {
    try {
      final files = await FilePicker.pickFiles(
        dialogTitle: '选择视频文件',
        type: FileType.custom,
        allowedExtensions: const [
          'mp4',
          'm4v',
          'mkv',
          'mov',
          'webm',
          'avi',
          'mpg',
          'mpeg',
          '3gp',
          'ts',
          'm2ts',
          'flv',
          'wmv',
          'ogv',
          'vob',
          'rmvb',
          'mp3',
          'm4a',
          'aac',
          'flac',
          'wav',
          'ogg',
          'opus',
        ],
      );
      if (files.isEmpty) return;
      final items = <MediaItem>[];
      for (final file in files) {
        final path = file.path ?? file.uri.toString();
        if (path.isEmpty) continue;
        items.add(
          MediaItem(
            name: file.name,
            url: path,
            size: await file.length() ?? 0,
            modified: null,
            isLocal: true,
          ),
        );
      }
      if (items.isEmpty) {
        _message('读取文件失败，请重新选择');
        return;
      }
      await _addToLibrary(items);
      await _remember(items);
      await _launchPlayer(items, 0);
    } catch (error) {
      if (mounted) _message('打开视频失败：${_friendlyError(error)}');
    }
  }

  Future<void> _scanFolder() async {
    if (!_supportsFolderScan) {
      _message('请使用“打开视频”选择本地文件');
      return;
    }
    try {
      final path = await FilePicker.getDirectoryPath(dialogTitle: '选择视频文件夹');
      if (path == null || path.isEmpty) return;
      setState(() => _scanning = true);
      final found = await scanLocalMedia(path);
      if (!mounted) return;
      if (found.isEmpty) {
        _message('这个文件夹中没有找到支持的视频');
        return;
      }
      await _addToLibrary(found);
      await _remember(found);
      await _launchPlayer(found, 0);
    } catch (error) {
      if (mounted) _message('扫描文件夹失败：${_friendlyError(error)}');
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _addToLibrary(List<MediaItem> items) async {
    final unique = <String>{};
    _library = [
      ...items,
      ..._library,
    ].where((item) => unique.add(item.url)).take(500).toList();
    if (mounted) setState(() {});
    await _saveLibrary();
  }

  List<MediaItem> get _visibleLibrary {
    final query = _librarySearch.text.trim().toLowerCase();
    final items = _library.where((item) {
      if (_libraryFilter == '收藏' && !_favorites.contains(item.url)) {
        return false;
      }
      if (_libraryFilter == '视频' && !item.isVideo) return false;
      if (_libraryFilter == '音频' && !item.isAudio) return false;
      return query.isEmpty ||
          item.name.toLowerCase().contains(query) ||
          item.url.toLowerCase().contains(query);
    }).toList();
    if (_librarySort == '名称') {
      items.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
    } else if (_librarySort == '文件大小') {
      items.sort((a, b) => b.size.compareTo(a.size));
    }
    return items;
  }

  Future<void> _openLibraryItem(MediaItem item) async {
    final queue = _visibleLibrary;
    final index = queue.indexWhere((candidate) => candidate.url == item.url);
    await _remember([item]);
    await _launchPlayer(queue, index < 0 ? 0 : index);
  }

  Future<void> _toggleFavorite(MediaItem item) async {
    setState(() {
      if (!_favorites.add(item.url)) _favorites.remove(item.url);
    });
    await _saveLibrary();
  }

  Future<void> _removeFromLibrary(MediaItem item) async {
    setState(() {
      _library.removeWhere((entry) => entry.url == item.url);
      _favorites.remove(item.url);
    });
    await _saveLibrary();
  }

  Future<void> _showMediaInfo(MediaItem item) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.name,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 15),
              _infoLine('格式', item.extension.toUpperCase()),
              _infoLine('大小', item.prettySize),
              _infoLine('位置', item.url),
              if (item.modified != null)
                _infoLine(
                  '修改时间',
                  item.modified!.toLocal().toString().split('.').first,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoLine(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 70,
          child: Text(
            label,
            style: const TextStyle(color: Color(0xFF828A80), fontSize: 12),
          ),
        ),
        Expanded(
          child: SelectableText(
            value,
            style: const TextStyle(color: _ink, fontSize: 12),
          ),
        ),
      ],
    ),
  );

  Future<void> _remember(List<MediaItem> items) async {
    final next = [...items, ..._recent];
    final unique = <String>{};
    _recent = next.where((item) => unique.add(item.url)).take(60).toList();
    if (mounted) setState(() {});
    await _saveHistory();
  }

  Future<void> _openRecent(MediaItem item) async {
    final index = _recent.indexWhere((candidate) => candidate.url == item.url);
    await _launchPlayer(_recent, index < 0 ? 0 : index);
  }

  Future<void> _launchPlayer(
    List<MediaItem> queue,
    int index, {
    Map<String, String> headers = const {},
  }) async {
    if (queue.isEmpty) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          queue: List<MediaItem>.unmodifiable(queue),
          initialIndex: index,
          settings: _settings,
          headers: headers,
        ),
      ),
    );
    final refreshedSettings = await PlayerSettings.load();
    if (mounted) setState(() => _settings = refreshedSettings);
  }

  Future<void> _loadSettingsOnly() async {
    final settings = await PlayerSettings.load();
    if (!mounted) return;
    setState(() {
      _settings = settings;
      if (!settings.saveHistory) _recent = [];
    });
    if (!settings.saveHistory) await _saveHistory();
  }

  Future<void> _clearHistory() async {
    setState(() => _recent.clear());
    await _saveHistory();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF5F5F0),
    body: _tab == 0
        ? _homePage()
        : SettingsScreen(
            initialSettings: _settings,
            onChanged: (settings) {
              setState(() {
                _settings = settings;
                if (!settings.saveHistory) _recent = [];
              });
              if (!settings.saveHistory) _saveHistory();
            },
          ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: _tab,
      backgroundColor: Colors.white,
      indicatorColor: _green.withValues(alpha: .55),
      onDestinationSelected: (index) async {
        setState(() => _tab = index);
        if (index == 1) await _loadSettingsOnly();
      },
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.video_library_outlined),
          selectedIcon: Icon(Icons.video_library_rounded),
          label: '视频',
        ),
        NavigationDestination(icon: Icon(Icons.tune_rounded), label: '设置'),
      ],
    ),
  );

  Widget _homePage() => SafeArea(
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
              sliver: SliverList.list(
                children: [
                  _header(),
                  const SizedBox(height: 23),
                  _heroCard(),
                  const SizedBox(height: 24),
                  _quickActions(),
                  const SizedBox(height: 27),
                  _librarySection(),
                  const SizedBox(height: 30),
                  _recentHeader(),
                  const SizedBox(height: 10),
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Center(
                        child: CircularProgressIndicator(color: _ink),
                      ),
                    )
                  else if (_recent.isEmpty)
                    _emptyHistory()
                  else
                    ..._recent.take(12).map(_recentRow),
                  const SizedBox(height: 22),
                  _webDavCard(),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _header() => Row(
    children: [
      Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: _green,
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(Icons.play_arrow_rounded, color: _ink, size: 28),
      ),
      const SizedBox(width: 11),
      const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'streambox',
            style: TextStyle(
              color: _ink,
              fontSize: 20,
              fontWeight: FontWeight.w900,
              letterSpacing: -.7,
            ),
          ),
          SizedBox(height: 1),
          Text(
            'VIDEO PLAYER',
            style: TextStyle(
              color: Color(0xFF8C948A),
              fontSize: 8,
              letterSpacing: 1.4,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
      const Spacer(),
      IconButton.filledTonal(
        tooltip: '设置',
        onPressed: () async {
          setState(() => _tab = 1);
          await _loadSettingsOnly();
        },
        style: IconButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: _ink,
        ),
        icon: const Icon(Icons.tune_rounded),
      ),
    ],
  );

  Widget _heroCard() => Container(
    padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
    decoration: BoxDecoration(
      color: _ink,
      borderRadius: BorderRadius.circular(25),
      gradient: const LinearGradient(
        colors: [Color(0xFF202E26), Color(0xFF111A15)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: _green.withValues(alpha: .14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.folder_open_rounded,
                color: _green,
                size: 21,
              ),
            ),
            const SizedBox(width: 11),
            const Text(
              '从设备中打开',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 11),
        const Text(
          '选择一个视频，或一次添加多个文件组成播放队列。',
          style: TextStyle(color: Colors.white60, fontSize: 11),
        ),
        const SizedBox(height: 19),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _loading ? null : _openVideos,
            icon: const Icon(Icons.video_file_outlined, size: 19),
            label: const Text('打开视频'),
            style: FilledButton.styleFrom(
              backgroundColor: _green,
              foregroundColor: _ink,
              padding: const EdgeInsets.symmetric(vertical: 15),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
              textStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _quickActions() => Row(
    children: [
      Expanded(
        child: _quickAction(
          icon: _supportsFolderScan
              ? Icons.folder_copy_outlined
              : Icons.video_file_outlined,
          label: _supportsFolderScan
              ? _scanning
                    ? '正在扫描…'
                    : '扫描文件夹'
              : '浏览本地文件',
          onPressed: _supportsFolderScan
              ? (_scanning ? null : _scanFolder)
              : _openVideos,
        ),
      ),
      const SizedBox(width: 11),
      Expanded(
        child: _quickAction(
          icon: Icons.cloud_outlined,
          label: 'WebDAV',
          onPressed: () async {
            final result = await Navigator.of(context).push<WebDavPlayback>(
              MaterialPageRoute(builder: (_) => const WebDavScreen()),
            );
            if (result != null) {
              await _launchPlayer(
                result.queue,
                result.index,
                headers: result.headers,
              );
            }
          },
        ),
      ),
    ],
  );

  Widget _quickAction({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
  }) => OutlinedButton.icon(
    onPressed: onPressed,
    icon: Icon(icon, size: 17),
    label: Text(label),
    style: OutlinedButton.styleFrom(
      foregroundColor: _ink,
      backgroundColor: Colors.white,
      side: BorderSide.none,
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
    ),
  );

  Widget _librarySection() {
    final items = _visibleLibrary;
    final limit = _showAllLibrary ? 500 : 6;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              '本地媒体库',
              style: TextStyle(
                color: _ink,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(width: 7),
            Text(
              '${_library.length}',
              style: const TextStyle(color: Color(0xFF8A9288), fontSize: 11),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: _openVideos,
              icon: const Icon(Icons.add_rounded, size: 17),
              label: const Text('添加媒体'),
              style: TextButton.styleFrom(foregroundColor: _ink),
            ),
          ],
        ),
        const SizedBox(height: 7),
        TextField(
          controller: _librarySearch,
          onChanged: (_) => setState(() => _showAllLibrary = false),
          decoration: InputDecoration(
            hintText: '搜索名称或文件路径',
            prefixIcon: const Icon(Icons.search_rounded, size: 19),
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: ['全部', '视频', '音频', '收藏'].map((filter) {
              final selected = _libraryFilter == filter;
              return Padding(
                padding: const EdgeInsets.only(right: 7),
                child: ChoiceChip(
                  label: Text(filter),
                  selected: selected,
                  onSelected: (_) => setState(() => _libraryFilter = filter),
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
        Row(
          children: [
            Text(
              '${items.length} 项',
              style: const TextStyle(color: Color(0xFF8A9288), fontSize: 10),
            ),
            const Spacer(),
            const Text(
              '排序',
              style: TextStyle(color: Color(0xFF8A9288), fontSize: 10),
            ),
            const SizedBox(width: 7),
            DropdownButton<String>(
              value: _librarySort,
              underline: const SizedBox.shrink(),
              isDense: true,
              borderRadius: BorderRadius.circular(12),
              items: const ['最近添加', '名称', '文件大小']
                  .map(
                    (sort) => DropdownMenuItem(value: sort, child: Text(sort)),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) setState(() => _librarySort = value);
              },
            ),
          ],
        ),
        if (_library.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 17),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(17),
            ),
            child: const Text(
              '添加视频后会保存在媒体库中，支持搜索、收藏和继续播放。',
              style: TextStyle(color: Color(0xFF737D72), fontSize: 11),
            ),
          )
        else if (items.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: Text(
                '没有匹配的媒体',
                style: TextStyle(color: Color(0xFF858D83), fontSize: 12),
              ),
            ),
          )
        else
          ...items.take(limit).map(_libraryRow),
        if (items.length > 6)
          Center(
            child: TextButton(
              onPressed: () =>
                  setState(() => _showAllLibrary = !_showAllLibrary),
              child: Text(_showAllLibrary ? '收起' : '显示全部 ${items.length} 项'),
            ),
          ),
      ],
    );
  }

  Widget _libraryRow(MediaItem item) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(15),
      child: InkWell(
        onTap: () => _openLibraryItem(item),
        borderRadius: BorderRadius.circular(15),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 9, 4, 9),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F4EA),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  item.isAudio
                      ? Icons.music_note_rounded
                      : Icons.movie_outlined,
                  color: const Color(0xFF617E48),
                  size: 21,
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
                      '${item.extension.toUpperCase()} · ${item.prettySize}',
                      style: const TextStyle(
                        color: Color(0xFF8A9288),
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: _favorites.contains(item.url) ? '取消收藏' : '收藏',
                onPressed: () => _toggleFavorite(item),
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  _favorites.contains(item.url)
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  color: _favorites.contains(item.url)
                      ? const Color(0xFFB04C42)
                      : const Color(0xFF8A9288),
                  size: 19,
                ),
              ),
              PopupMenuButton<String>(
                tooltip: '更多操作',
                onSelected: (action) {
                  if (action == 'info') _showMediaInfo(item);
                  if (action == 'remove') _removeFromLibrary(item);
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'info', child: Text('媒体信息')),
                  PopupMenuItem(value: 'remove', child: Text('从媒体库移除')),
                ],
                icon: const Icon(
                  Icons.more_vert_rounded,
                  color: Color(0xFF8A9288),
                  size: 19,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _recentHeader() => Row(
    children: [
      const Text(
        '最近播放',
        style: TextStyle(
          color: _ink,
          fontSize: 16,
          fontWeight: FontWeight.w800,
        ),
      ),
      const SizedBox(width: 7),
      Text(
        '${_recent.length}',
        style: const TextStyle(color: Color(0xFF8A9288), fontSize: 11),
      ),
      const Spacer(),
      if (_recent.isNotEmpty)
        TextButton(
          onPressed: _clearHistory,
          style: TextButton.styleFrom(foregroundColor: _ink),
          child: const Text('清空', style: TextStyle(fontSize: 11)),
        ),
    ],
  );

  Widget _recentRow(MediaItem item) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () => _openRecent(item),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(11),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F4EA),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(
                  Icons.movie_outlined,
                  color: Color(0xFF617E48),
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
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
                      '${item.extension.toUpperCase()} · ${item.prettySize}',
                      style: const TextStyle(
                        color: Color(0xFF8A9288),
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                tooltip: '从记录中移除',
                onPressed: () => _removeRecent(item),
                visualDensity: VisualDensity.compact,
                icon: const Icon(
                  Icons.close_rounded,
                  color: Color(0xFF9AA197),
                  size: 19,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Future<void> _removeRecent(MediaItem item) async {
    setState(() => _recent.removeWhere((entry) => entry.url == item.url));
    await _saveHistory();
  }

  Widget _emptyHistory() => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(vertical: 23, horizontal: 18),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
    ),
    child: const Row(
      children: [
        Icon(Icons.history_rounded, color: Color(0xFF9CA498), size: 23),
        SizedBox(width: 12),
        Expanded(
          child: Text(
            '打开过的视频会保存在这里，方便下次继续播放。',
            style: TextStyle(color: Color(0xFF737D72), fontSize: 11),
          ),
        ),
      ],
    ),
  );

  Widget _webDavCard() => Container(
    padding: const EdgeInsets.fromLTRB(17, 15, 12, 15),
    decoration: BoxDecoration(
      color: const Color(0xFFEDEFE8),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Row(
      children: [
        const Icon(Icons.cloud_outlined, color: _ink, size: 21),
        const SizedBox(width: 11),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'WebDAV 网络媒体库',
                style: TextStyle(
                  color: _ink,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
              SizedBox(height: 3),
              Text(
                '需要时再连接，账号信息不会保存',
                style: TextStyle(color: Color(0xFF7C857A), fontSize: 10),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: '连接 WebDAV',
          onPressed: () async {
            final result = await Navigator.of(context).push<WebDavPlayback>(
              MaterialPageRoute(builder: (_) => const WebDavScreen()),
            );
            if (result != null) {
              await _launchPlayer(
                result.queue,
                result.index,
                headers: result.headers,
              );
            }
          },
          icon: const Icon(Icons.chevron_right_rounded, color: _ink),
        ),
      ],
    ),
  );

  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  String _friendlyError(Object error) => error
      .toString()
      .replaceFirst('Exception: ', '')
      .replaceFirst('DioException [bad response]: ', '服务器返回异常：');
}

