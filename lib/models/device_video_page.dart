import 'media_item.dart';

class DeviceVideoPage {
  const DeviceVideoPage({
    required this.supported,
    required this.permissionGranted,
    required this.items,
    required this.total,
    required this.hasMore,
    this.limitedAccess = false,
  });

  final bool supported;
  final bool permissionGranted;
  final bool limitedAccess;
  final List<MediaItem> items;
  final int total;
  final bool hasMore;
}

