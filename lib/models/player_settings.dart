import 'package:shared_preferences/shared_preferences.dart';

class PlayerSettings {
  const PlayerSettings({
    this.landscapeOnFullscreen = true,
    this.hideSystemUi = true,
    this.saveHistory = true,
    this.autoHideControls = true,
    this.defaultSpeed = 1,
  });

  final bool landscapeOnFullscreen;
  final bool hideSystemUi;
  final bool saveHistory;
  final bool autoHideControls;
  final double defaultSpeed;

  static Future<PlayerSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return PlayerSettings(
      landscapeOnFullscreen: prefs.getBool('landscapeOnFullscreen') ?? true,
      hideSystemUi: prefs.getBool('hideSystemUi') ?? true,
      saveHistory: prefs.getBool('saveHistory') ?? true,
      autoHideControls: prefs.getBool('autoHideControls') ?? true,
      defaultSpeed: prefs.getDouble('defaultSpeed') ?? 1,
    );
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('landscapeOnFullscreen', landscapeOnFullscreen);
    await prefs.setBool('hideSystemUi', hideSystemUi);
    await prefs.setBool('saveHistory', saveHistory);
    await prefs.setBool('autoHideControls', autoHideControls);
    await prefs.setDouble('defaultSpeed', defaultSpeed);
  }

  PlayerSettings copyWith({
    bool? landscapeOnFullscreen,
    bool? hideSystemUi,
    bool? saveHistory,
    bool? autoHideControls,
    double? defaultSpeed,
  }) => PlayerSettings(
    landscapeOnFullscreen: landscapeOnFullscreen ?? this.landscapeOnFullscreen,
    hideSystemUi: hideSystemUi ?? this.hideSystemUi,
    saveHistory: saveHistory ?? this.saveHistory,
    autoHideControls: autoHideControls ?? this.autoHideControls,
    defaultSpeed: defaultSpeed ?? this.defaultSpeed,
  );
}

