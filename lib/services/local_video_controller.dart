import 'package:video_player/video_player.dart';

import 'local_video_controller_stub.dart'
    if (dart.library.io) 'local_video_controller_io.dart' as platform;

VideoPlayerController createLocalVideoController(String path) =>
    platform.createLocalVideoController(path);
