import '../models/media_item.dart';
import 'local_media_scan_stub.dart'
    if (dart.library.io) 'local_media_scan_io.dart'
    as implementation;

Future<List<MediaItem>> scanLocalMedia(String directoryPath) =>
    implementation.scanLocalMedia(directoryPath);

