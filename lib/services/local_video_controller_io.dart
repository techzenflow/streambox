import 'dart:io';

import 'package:video_player/video_player.dart';

VideoPlayerController createLocalVideoController(String path) {
  final uri = Uri.tryParse(path);
  if (uri != null && uri.scheme == 'content') {
    return VideoPlayerController.networkUrl(uri);
  }
  return VideoPlayerController.file(File(path));
}

