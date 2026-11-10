import 'dart:io';

import '../models/media_item.dart';

Future<List<MediaItem>> scanLocalMedia(String directoryPath) async {
  final directory = Directory(directoryPath);
  if (!await directory.exists()) return const [];
  final items = <MediaItem>[];
  await for (final entity in directory.list(
    recursive: true,
    followLinks: false,
  )) {
    if (entity is! File) continue;
    final name = entity.uri.pathSegments.isEmpty
        ? entity.path.split(Platform.pathSeparator).last
        : entity.uri.pathSegments.last;
    final item = MediaItem(
      name: name,
      url: entity.path,
      size: 0,
      modified: null,
      isLocal: true,
    );
    if (!item.isVideo) continue;
    final stat = await entity.stat();
    items.add(
      MediaItem(
        name: item.name,
        url: item.url,
        size: stat.size,
        modified: stat.modified,
        isLocal: true,
      ),
    );
    if (items.length >= 1000) break;
  }
  items.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return items;
}

Future<List<MediaItem>> scanDefaultLocalMedia() async {
  final environment = Platform.environment;
  final home = environment['USERPROFILE'] ?? environment['HOME'];
  if (home == null || home.isEmpty) return const [];

  final separator = Platform.pathSeparator;
  final folders = Platform.isWindows
      ? ['Videos', 'Downloads']
      : Platform.isMacOS
      ? ['Movies', 'Downloads']
      : ['Videos', 'Downloads'];
  final items = <MediaItem>[];
  final seen = <String>{};
  for (final folder in folders) {
    final found = await scanLocalMedia('$home$separator$folder');
    for (final item in found) {
      if (seen.add(item.url)) items.add(item);
      if (items.length >= 1000) return items;
    }
  }
  items.sort((a, b) {
    final aDate = a.modified ?? DateTime.fromMillisecondsSinceEpoch(0);
    final bDate = b.modified ?? DateTime.fromMillisecondsSinceEpoch(0);
    return bDate.compareTo(aDate);
  });
  return items;
}

