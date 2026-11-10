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

