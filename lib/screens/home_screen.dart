import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/media_item.dart';
import '../models/player_settings.dart';
import '../services/device_video_scanner.dart';
import 'local_media_scan.dart';
import 'player_screen.dart';
import 'settings_screen.dart';
import 'webdav_screen.dart';

const _green = Color(0xFFB9F36B);
const _ink = Color(0xFF19251F);
final Map<String, Future<Uint8List?>> _thumbnailCache = {};

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  static const _historyKey = 'streambox.localHistory';
  static const _favoritesKey = 'streambox.favoriteMedia';
  static const _pageSize = 60;

  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  int _tab = 0;
  int _page = 0;
  int _total = 0;
  bool _scanning = false;
  bool _scanSupported = true;
  bool _permissionGranted = false;
  bool _limitedAccess = false;
  bool _hasMore = false;
  String? _scanError;
  String _filter = '全部';
  String _sort = '最近';
  PlayerSettings _settings = const PlayerSettings();
  List<MediaItem> _videos = [];
  List<MediaItem> _recent = [];
  Set<String> _favorites = {};

  bool get _isMobileLibrary =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  bool get _supportsScanning =>
      _isMobileLibrary ||
      (!kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.windows ||
              defaultTargetPlatform == TargetPlatform.macOS ||
              defaultTargetPlatform == TargetPlatform.linux));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_onScroll);
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    await _loadSavedData();
    await _scanVideos();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _isMobileLibrary) {
      unawaited(_scanVideos());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final settings = await PlayerSettings.load();
      final rawHistory = prefs.getString(_historyKey);
      final history = rawHistory == null
          ? <dynamic>[]
          : jsonDecode(rawHistory) as List;
      final favorites = prefs.getStringList(_favoritesKey) ?? const <String>[];
      if (!settings.saveHistory) history.clear();
      if (!mounted) return;
      setState(() {
        _settings = settings;
        _recent = history.whereType<Map>().map(_itemFromJson).toList();
        _favorites = favorites.toSet();
      });
    } catch (_) {
      // A corrupt preference should not prevent the local library scan.
    }
  }

  MediaItem _itemFromJson(Map<dynamic, dynamic> entry) => MediaItem(
    name: entry['name'] as String? ?? '视频',
    url: entry['url'] as String? ?? '',
    size: (entry['size'] as num?)?.toInt() ?? 0,
    modified: DateTime.tryParse(entry['modified'] as String? ?? ''),
    isLocal: true,
    assetId: entry['assetId'] as String?,
    durationSeconds: (entry['durationSeconds'] as num?)?.toInt(),
    width: (entry['width'] as num?)?.toInt(),
    height: (entry['height'] as num?)?.toInt(),
  );

  Map<String, Object?> _itemToJson(MediaItem item) => {
    'name': item.name,
    'url': item.url,
    'size': item.size,
    'modified': item.modified?.toIso8601String(),
    'assetId': item.assetId,
    'durationSeconds': item.durationSeconds,
    'width': item.width,
    'height': item.height,
  };

  Future<void> _saveFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_favoritesKey, _favorites.toList());
  }

  Future<void> _saveHistory() async {
    final prefs = await SharedPreferences.getInstance();
    if (!_settings.saveHistory || kIsWeb) {
      await prefs.remove(_historyKey);
      return;
    }
    await prefs.setString(
      _historyKey,
      jsonEncode(_recent.map(_itemToJson).toList()),
    );
  }

  Future<void> _scanVideos({bool reset = true}) async {
    if (_scanning) return;
    if (!_supportsScanning) {
      if (mounted) {
        setState(() {
          _scanSupported = false;
          _scanning = false;
        });
      }
      return;
    }
    final requestedPage = reset ? 0 : _page + 1;
    setState(() {
      _scanning = true;
      _scanError = null;
    });
    try {
      if (_isMobileLibrary) {
        final result = await scanDeviceVideos(
          page: requestedPage,
          pageSize: _pageSize,
        );
        if (!mounted) return;
        setState(() {
          _scanSupported = result.supported;
          _permissionGranted = result.permissionGranted;
          _limitedAccess = result.limitedAccess;
          _total = result.total;
          _hasMore = result.hasMore;
          if (!result.permissionGranted) {
            _videos = [];
          } else {
            _videos = reset
                ? result.items
                : _mergeUnique(_videos, result.items);
            _page = requestedPage;
          }
        });
      } else {
        final found = await scanDefaultLocalMedia();
        if (!mounted) return;
        setState(() {
          _scanSupported = true;
          _permissionGranted = true;
          _limitedAccess = false;
          _videos = found;
          _total = found.length;
          _hasMore = false;
          _page = 0;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _scanError = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  List<MediaItem> _mergeUnique(List<MediaItem> current, List<MediaItem> more) {
    final seen = current.map((item) => item.identity).toSet();
    return [...current, ...more.where((item) => seen.add(item.identity))];
  }

  void _onScroll() {
    if (_scrollController.hasClients &&
        _scrollController.position.extentAfter < 420 &&
        _hasMore &&
        !_scanning) {
      unawaited(_scanVideos(reset: false));
    }
  }

  List<MediaItem> get _visibleVideos {
    final query = _searchController.text.trim().toLowerCase();
    final items = _videos.where((item) {
      if (_filter == '收藏' && !_favorites.contains(item.identity)) {
        return false;
      }
      if (_filter == '竖屏' &&
          !(item.width != null &&
              item.height != null &&
              item.height! > item.width!)) {
        return false;
      }
      if (_filter == '横屏' &&
          !(item.width != null &&
              item.height != null &&
              item.width! >= item.height!)) {
        return false;
      }
      return query.isEmpty ||
          item.name.toLowerCase().contains(query) ||
          item.url.toLowerCase().contains(query);
    }).toList();
    if (_sort == '名称') {
      items.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
    }
    return items;
  }

  Future<void> _toggleFavorite(MediaItem item) async {
    setState(() {
      if (!_favorites.add(item.identity)) _favorites.remove(item.identity);
    });
    await _saveFavorites();
  }

  Future<void> _remember(MediaItem item) async {
    if (!_settings.saveHistory) return;
    _recent = [
      item,
      ..._recent.where((entry) => entry.identity != item.identity).take(59),
    ];
    if (mounted) setState(() {});
    await _saveHistory();
  }

  Future<void> _openVideo(MediaItem item) async {
    final queue = _visibleVideos;
    final index = queue.indexWhere(
      (candidate) => candidate.identity == item.identity,
    );
    await _remember(item);
    await _launchPlayer(queue, index < 0 ? 0 : index);
  }

  Future<void> _openRecent(MediaItem item) async {
    final index = _recent.indexWhere(
      (candidate) => candidate.identity == item.identity,
    );
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
    await _loadSavedData();
    if (_isMobileLibrary) await _scanVideos();
  }

  Future<void> _openWebDav() async {
    final result = await Navigator.of(context).push<WebDavPlayback>(
      MaterialPageRoute(builder: (_) => const WebDavScreen()),
    );
    if (result != null) {
      await _launchPlayer(result.queue, result.index, headers: result.headers);
    }
  }

  Future<void> _openPermissionSettings() async {
    if (_limitedAccess) {
      await expandLimitedVideoAccess();
    } else {
      await openDeviceMediaSettings();
    }
    await _scanVideos();
  }

  Future<void> _clearHistory() async {
    setState(() => _recent.clear());
    await _saveHistory();
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
    child: LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth < 430
            ? 2
            : constraints.maxWidth < 650
            ? 3
            : 4;
        final items = _visibleVideos;
        return CustomScrollView(
          controller: _scrollController,
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
              sliver: SliverList.list(
                children: [
                  _header(),
                  const SizedBox(height: 20),
                  _searchBar(),
                  const SizedBox(height: 11),
                  _filterBar(),
                  if (_recent.isNotEmpty) ...[
                    const SizedBox(height: 22),
                    _recentSection(),
                  ],
                  if (_limitedAccess) ...[
                    const SizedBox(height: 12),
                    _notice(
                      '当前只显示你授权的视频',
                      action: '选择更多',
                      onPressed: _openPermissionSettings,
                    ),
                  ],
                  if (_scanError != null) ...[
                    const SizedBox(height: 12),
                    _notice(_scanError!, action: '重试', onPressed: _scanVideos),
                  ],
                  if (_scanning && _videos.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    const LinearProgressIndicator(minHeight: 2),
                  ],
                  const SizedBox(height: 17),
                  Row(
                    children: [
                      const Text(
                        '本地视频',
                        style: TextStyle(
                          color: _ink,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _total == 0 ? '${items.length}' : '$_total',
                        style: const TextStyle(
                          color: Color(0xFF858D83),
                          fontSize: 12,
                        ),
                      ),
                      const Spacer(),
                      if (_sort == '名称')
                        const Text(
                          '名称排序',
                          style: TextStyle(
                            color: Color(0xFF858D83),
                            fontSize: 10,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            if (!_scanSupported)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _emptyState(
                  Icons.phone_android_rounded,
                  '请在 Android 或 iPhone 上浏览本地视频',
                ),
              )
            else if (_isMobileLibrary && !_permissionGranted && !_scanning)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _emptyState(
                  Icons.video_library_outlined,
                  '允许访问视频后，设备中的视频会自动显示在这里。',
                  action: '允许访问视频',
                  onPressed: _scanVideos,
                ),
              )
            else if (_scanning && _videos.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator(color: _ink)),
              )
            else if (items.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _emptyState(
                  _filter == '收藏'
                      ? Icons.favorite_border_rounded
                      : Icons.movie_outlined,
                  _filter == '收藏'
                      ? '还没有收藏的视频'
                      : _searchController.text.trim().isNotEmpty
                      ? '没有匹配的视频'
                      : '没有找到本地视频',
                  action: _filter == '收藏' ? null : '重新扫描',
                  onPressed: _filter == '收藏' ? null : _scanVideos,
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
                sliver: SliverGrid.builder(
                  itemCount: items.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    childAspectRatio: .82,
                  ),
                  itemBuilder: (context, index) => _videoCard(items[index]),
                ),
              ),
            if (_scanning && _videos.isNotEmpty && _hasMore)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.only(bottom: 24),
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
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
      const Expanded(
        child: Column(
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
      ),
      IconButton(
        tooltip: '刷新媒体库',
        onPressed: _scanning ? null : _scanVideos,
        icon: _scanning
            ? const SizedBox(
                width: 19,
                height: 19,
                child: CircularProgressIndicator(strokeWidth: 2, color: _ink),
              )
            : const Icon(Icons.refresh_rounded, color: _ink),
      ),
      IconButton(
        tooltip: 'WebDAV',
        onPressed: _openWebDav,
        icon: const Icon(Icons.cloud_outlined, color: _ink),
      ),
      IconButton(
        tooltip: '设置',
        onPressed: () async {
          setState(() => _tab = 1);
          await _loadSettingsOnly();
        },
        icon: const Icon(Icons.tune_rounded, color: _ink),
      ),
    ],
  );

  Widget _searchBar() => TextField(
    controller: _searchController,
    onChanged: (_) => setState(() {}),
    decoration: InputDecoration(
      hintText: '搜索视频',
      prefixIcon: const Icon(Icons.search_rounded, size: 20),
      suffixIcon: _searchController.text.isEmpty
          ? null
          : IconButton(
              tooltip: '清除搜索',
              onPressed: () {
                _searchController.clear();
                setState(() {});
              },
              icon: const Icon(Icons.close_rounded, size: 18),
            ),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: BorderSide.none,
      ),
    ),
  );

  Widget _filterBar() => Row(
    children: [
      Expanded(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: ['全部', '横屏', '竖屏', '收藏'].map((filter) {
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
      ),
      PopupMenuButton<String>(
        tooltip: '排序方式',
        onSelected: (value) => setState(() => _sort = value),
        itemBuilder: (_) => const [
          PopupMenuItem(value: '最近', child: Text('最近添加')),
          PopupMenuItem(value: '名称', child: Text('名称排序')),
        ],
        icon: const Icon(Icons.sort_rounded, color: _ink),
      ),
    ],
  );

  Widget _recentSection() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          const Text(
            '继续观看',
            style: TextStyle(
              color: _ink,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
          const Spacer(),
          TextButton(onPressed: _clearHistory, child: const Text('清除')),
        ],
      ),
      SizedBox(
        height: 76,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: _recent.length.clamp(0, 8),
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            final item = _recent[index];
            return SizedBox(
              width: 235,
              child: Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  onTap: () => _openRecent(item),
                  borderRadius: BorderRadius.circular(14),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0F4EA),
                            borderRadius: BorderRadius.circular(11),
                          ),
                          child: const Icon(
                            Icons.play_circle_outline_rounded,
                            color: _ink,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            item.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _ink,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    ],
  );

  Widget _notice(
    String text, {
    required String action,
    required VoidCallback onPressed,
  }) => Container(
    padding: const EdgeInsets.fromLTRB(13, 10, 8, 10),
    decoration: BoxDecoration(
      color: const Color(0xFFEDEFE8),
      borderRadius: BorderRadius.circular(13),
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(text, style: const TextStyle(color: _ink, fontSize: 11)),
        ),
        TextButton(onPressed: onPressed, child: Text(action)),
      ],
    ),
  );

  Widget _emptyState(
    IconData icon,
    String text, {
    String? action,
    VoidCallback? onPressed,
  }) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 34),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 42, color: const Color(0xFF9AA197)),
          const SizedBox(height: 12),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF737D72),
              fontSize: 12,
              height: 1.4,
            ),
          ),
          if (action != null && onPressed != null) ...[
            const SizedBox(height: 10),
            FilledButton.tonal(onPressed: onPressed, child: Text(action)),
          ],
        ],
      ),
    ),
  );

  Widget _videoCard(MediaItem item) => Material(
    color: Colors.white,
    borderRadius: BorderRadius.circular(16),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: () => _openVideo(item),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                Container(color: const Color(0xFF18211C)),
                if (item.assetId != null)
                  FutureBuilder<Uint8List?>(
                    future: _thumbnailCache.putIfAbsent(
                      item.assetId!,
                      () => loadDeviceVideoThumbnail(item.assetId!),
                    ),
                    builder: (context, snapshot) {
                      final bytes = snapshot.data;
                      if (bytes == null) return const SizedBox.shrink();
                      return Image.memory(
                        bytes,
                        fit: BoxFit.contain,
                        gaplessPlayback: true,
                      );
                    },
                  ),
                const Center(
                  child: Icon(
                    Icons.play_circle_fill_rounded,
                    color: Colors.white70,
                    size: 35,
                  ),
                ),
                if (item.durationSeconds != null)
                  Positioned(
                    right: 7,
                    bottom: 7,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: .72),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 3,
                        ),
                        child: Text(
                          _formatDuration(item.durationSeconds!),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                if (item.width != null &&
                    item.height != null &&
                    item.height! > item.width!)
                  const Positioned(
                    left: 7,
                    top: 7,
                    child: _OrientationBadge(label: '竖屏'),
                  ),
                Positioned(
                  right: 1,
                  top: 1,
                  child: IconButton(
                    tooltip: _favorites.contains(item.identity) ? '取消收藏' : '收藏',
                    onPressed: () => _toggleFavorite(item),
                    visualDensity: VisualDensity.compact,
                    icon: Icon(
                      _favorites.contains(item.identity)
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                      color: _favorites.contains(item.identity)
                          ? const Color(0xFFFF8376)
                          : Colors.white,
                      size: 19,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(9, 8, 9, 9),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 11,
                    height: 1.2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${item.prettySize} · ${item.extension.toUpperCase()}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Color(0xFF858D83), fontSize: 9),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  String _formatDuration(int seconds) {
    final duration = Duration(seconds: seconds);
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final remainder = duration.inSeconds.remainder(60);
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${remainder.toString().padLeft(2, '0')}';
    }
    return '${duration.inMinutes}:${remainder.toString().padLeft(2, '0')}';
  }

  String _friendlyError(Object error) => error
      .toString()
      .replaceFirst('Exception: ', '')
      .replaceFirst('DioException [bad response]: ', '服务器返回异常：');
}

class _OrientationBadge extends StatelessWidget {
  const _OrientationBadge({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: .7),
      borderRadius: BorderRadius.circular(5),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
      child: Text(
        label,
        style: const TextStyle(color: Colors.white, fontSize: 9),
      ),
    ),
  );
}

