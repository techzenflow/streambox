import 'package:flutter/foundation.dart';
import 'package:photo_manager/photo_manager.dart';

import '../models/device_video_page.dart';
import '../models/media_item.dart';

bool get _isMediaLibraryPlatform =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS);

Future<DeviceVideoPage> scanDeviceVideos({
  int page = 0,
  int pageSize = 60,
}) async {
  if (!_isMediaLibraryPlatform) {
    return const DeviceVideoPage(
      supported: false,
      permissionGranted: false,
      items: [],
      total: 0,
      hasMore: false,
    );
  }

  final permission = await PhotoManager.requestPermissionExtend();
  if (!permission.hasAccess) {
    return const DeviceVideoPage(
      supported: true,
      permissionGranted: false,
      items: [],
      total: 0,
      hasMore: false,
    );
  }

  final paths = await PhotoManager.getAssetPathList(
    type: RequestType.video,
    onlyAll: true,
  );
  if (paths.isEmpty) {
    return DeviceVideoPage(
      supported: true,
      permissionGranted: true,
      limitedAccess: permission.isLimited,
      items: const [],
      total: 0,
      hasMore: false,
    );
  }

  final path = paths.first;
  final total = await path.assetCountAsync;
  final assets = await path.getAssetListPaged(page: page, size: pageSize);
  final items = await Future.wait(assets.map(_toMediaItem));
  return DeviceVideoPage(
    supported: true,
    permissionGranted: true,
    limitedAccess: permission.isLimited,
    items: items,
    total: total,
    hasMore: (page + 1) * pageSize < total,
  );
}

Future<MediaItem> _toMediaItem(AssetEntity asset) async {
  final title = await asset.titleAsync;
  final size = await asset.fileSize;
  return MediaItem(
    name: title,
    url: 'asset://${asset.id}',
    assetId: asset.id,
    size: size,
    modified: asset.modifiedDateTime,
    durationSeconds: asset.videoDuration.inSeconds,
    width: asset.orientatedWidth,
    height: asset.orientatedHeight,
    isLocal: true,
  );
}

Future<String?> resolveDeviceVideo(String assetId) async {
  if (!_isMediaLibraryPlatform) return null;
  final asset = await AssetEntity.fromId(assetId);
  final file = await asset?.file;
  return file?.path;
}

Future<Uint8List?> loadDeviceVideoThumbnail(
  String assetId, {
  int width = 320,
  int height = 180,
}) async {
  if (!_isMediaLibraryPlatform) return null;
  final asset = await AssetEntity.fromId(assetId);
  if (asset == null) return null;
  return asset.thumbnailDataWithSize(ThumbnailSize(width, height), quality: 78);
}

Future<void> openDeviceMediaSettings() => PhotoManager.openSetting();

Future<void> expandLimitedVideoAccess() =>
    PhotoManager.presentLimited(type: RequestType.video);

