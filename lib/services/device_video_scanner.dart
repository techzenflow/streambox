import 'dart:typed_data';

import '../models/device_video_page.dart';
import 'device_video_scanner_stub.dart'
    if (dart.library.io) 'device_video_scanner_io.dart' as platform;

Future<DeviceVideoPage> scanDeviceVideos({int page = 0, int pageSize = 60}) =>
    platform.scanDeviceVideos(page: page, pageSize: pageSize);

Future<String?> resolveDeviceVideo(String assetId) =>
    platform.resolveDeviceVideo(assetId);

Future<Uint8List?> loadDeviceVideoThumbnail(
  String assetId, {
  int width = 320,
  int height = 180,
}) => platform.loadDeviceVideoThumbnail(
  assetId,
  width: width,
  height: height,
);

Future<void> openDeviceMediaSettings() =>
    platform.openDeviceMediaSettings();

Future<void> expandLimitedVideoAccess() =>
    platform.expandLimitedVideoAccess();

