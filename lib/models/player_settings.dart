import 'package:shared_preferences/shared_preferences.dart';

class PlayerSettings {
  const PlayerSettings({
    this.landscapeOnFullscreen = true,
    this.hideSystemUi = true,
    this.saveHistory = true,
    this.autoHideControls = true,
    this.defaultSpeed = 1,
    this.rememberPosition = true,
    this.autoPlayNext = true,
    this.repeatMode = 0,
    this.seekSeconds = 10,
    this.subtitleFontSize = 18,
  });

  final bool landscapeOnFullscreen;
  final bool hideSystemUi;
  final bool saveHistory;
  final bool autoHideControls;
  final double defaultSpeed;
  final bool rememberPosition;
  final bool autoPlayNext;

  /// 0: off, 1: repeat queue, 2: repeat current item.
  final int repeatMode;
  final int seekSeconds;
  final double subtitleFontSize;

  static Future<PlayerSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return PlayerSettings(
      landscapeOnFullscreen: prefs.getBool('landscapeOnFullscreen') ?? true,
      hideSystemUi: prefs.getBool('hideSystemUi') ?? true,
      saveHistory: prefs.getBool('saveHistory') ?? true,
      autoHideControls: prefs.getBool('autoHideControls') ?? true,
      defaultSpeed: prefs.getDouble('defaultSpeed') ?? 1,
      rememberPosition: prefs.getBool('rememberPosition') ?? true,
      autoPlayNext: prefs.getBool('autoPlayNext') ?? true,
      repeatMode: prefs.getInt('repeatMode') ?? 0,
      seekSeconds: prefs.getInt('seekSeconds') ?? 10,
      subtitleFontSize: prefs.getDouble('subtitleFontSize') ?? 18,
    );
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('landscapeOnFullscreen', landscapeOnFullscreen);
    await prefs.setBool('hideSystemUi', hideSystemUi);
    await prefs.setBool('saveHistory', saveHistory);
    await prefs.setBool('autoHideControls', autoHideControls);
    await prefs.setDouble('defaultSpeed', defaultSpeed);
    await prefs.setBool('rememberPosition', rememberPosition);
    await prefs.setBool('autoPlayNext', autoPlayNext);
    await prefs.setInt('repeatMode', repeatMode);
    await prefs.setInt('seekSeconds', seekSeconds);
    await prefs.setDouble('subtitleFontSize', subtitleFontSize);
  }

  PlayerSettings copyWith({
    bool? landscapeOnFullscreen,
    bool? hideSystemUi,
    bool? saveHistory,
    bool? autoHideControls,
    double? defaultSpeed,
    bool? rememberPosition,
    bool? autoPlayNext,
    int? repeatMode,
    int? seekSeconds,
    double? subtitleFontSize,
  }) => PlayerSettings(
    landscapeOnFullscreen: landscapeOnFullscreen ?? this.landscapeOnFullscreen,
    hideSystemUi: hideSystemUi ?? this.hideSystemUi,
    saveHistory: saveHistory ?? this.saveHistory,
    autoHideControls: autoHideControls ?? this.autoHideControls,
    defaultSpeed: defaultSpeed ?? this.defaultSpeed,
    rememberPosition: rememberPosition ?? this.rememberPosition,
    autoPlayNext: autoPlayNext ?? this.autoPlayNext,
    repeatMode: repeatMode ?? this.repeatMode,
    seekSeconds: seekSeconds ?? this.seekSeconds,
    subtitleFontSize: subtitleFontSize ?? this.subtitleFontSize,
  );
}

