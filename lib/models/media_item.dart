class MediaItem {
  const MediaItem({
    required this.name,
    required this.url,
    required this.size,
    required this.modified,
    this.isDirectory = false,
    this.isLocal = false,
    this.assetId,
    this.durationSeconds,
    this.width,
    this.height,
  });

  final String name;
  final String url;
  final int size;
  final DateTime? modified;
  final bool isDirectory;
  final bool isLocal;
  final String? assetId;
  final int? durationSeconds;
  final int? width;
  final int? height;

  String get identity => assetId ?? url;

  String get extension =>
      name.contains('.') ? name.split('.').last.toLowerCase() : '';
  bool get isVideo => const {
    'mp4',
    'm4v',
    'mov',
    'mkv',
    'webm',
    'avi',
    'm3u8',
    'mpg',
    'mpeg',
    '3gp',
    'ts',
    'm2ts',
    'flv',
    'wmv',
    'ogv',
    'vob',
    'rmvb',
  }.contains(extension);
  bool get isAudio => const {
    'mp3',
    'm4a',
    'aac',
    'flac',
    'wav',
    'ogg',
    'opus',
  }.contains(extension);
  bool get isMedia => isVideo || isAudio;

  String get prettySize {
    if (size <= 0) return '—';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(0)} KB';
    if (size < 1024 * 1024 * 1024) {
      return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}

