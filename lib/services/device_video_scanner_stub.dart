import 'dart:typed_data';

import '../models/device_video_page.dart';

Future<DeviceVideoPage> scanDeviceVideos({int page = 0, int pageSize = 60})
    async => const DeviceVideoPage(
      supported: false,
      permissionGranted: false,
      items: [],
      total: 0,
      hasMore: false,
    );

Future<String?> resolveDeviceVideo(String assetId) async => null;

Future<Uint8List?> loadDeviceVideoThumbnail(
  String assetId, {
  int width = 320,
  int height = 180,
}) async => null;

Future<void> openDeviceMediaSettings() async {}

Future<void> expandLimitedVideoAccess() async {}

