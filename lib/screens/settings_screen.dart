import 'package:flutter/material.dart';

import '../models/player_settings.dart';

const _ink = Color(0xFF19251F);
const _green = Color(0xFFB9F36B);

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.initialSettings,
    this.onChanged,
  });

  final PlayerSettings initialSettings;
  final ValueChanged<PlayerSettings>? onChanged;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late PlayerSettings _settings = widget.initialSettings;

  Future<void> _update(PlayerSettings next) async {
    setState(() => _settings = next);
    widget.onChanged?.call(next);
    await next.save();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text(
        '设置',
        style: TextStyle(fontWeight: FontWeight.w800, color: _ink),
      ),
      backgroundColor: const Color(0xFFF5F5F0),
      surfaceTintColor: Colors.transparent,
    ),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
      children: [
        _sectionTitle('播放'),
        _settingsCard([
          _switchRow(
            title: '全屏时自动横屏',
            subtitle: '进入全屏时旋转设备，退出后恢复竖屏',
            icon: Icons.screen_rotation_alt_rounded,
            value: _settings.landscapeOnFullscreen,
            onChanged: (value) =>
                _update(_settings.copyWith(landscapeOnFullscreen: value)),
          ),
          _divider,
          _switchRow(
            title: '隐藏系统状态栏和导航栏',
            subtitle: '全屏播放时使用沉浸模式',
            icon: Icons.fullscreen_rounded,
            value: _settings.hideSystemUi,
            onChanged: (value) =>
                _update(_settings.copyWith(hideSystemUi: value)),
          ),
          _divider,
          _switchRow(
            title: '自动隐藏播放控制',
            subtitle: '播放时几秒后收起控制按钮，点按画面可再次显示',
            icon: Icons.visibility_off_outlined,
            value: _settings.autoHideControls,
            onChanged: (value) =>
                _update(_settings.copyWith(autoHideControls: value)),
          ),
          _divider,
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Row(
              children: [
                const Icon(Icons.speed_rounded, color: _ink, size: 20),
                const SizedBox(width: 13),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '默认播放速度',
                        style: TextStyle(
                          color: _ink,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        '可在播放页随时切换',
                        style: TextStyle(
                          color: Color(0xFF7E867D),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                DropdownButton<double>(
                  value: _settings.defaultSpeed,
                  underline: const SizedBox.shrink(),
                  borderRadius: BorderRadius.circular(14),
                  items: const [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
                      .map(
                        (speed) => DropdownMenuItem(
                          value: speed,
                          child: Text('${speed}x'),
                        ),
                      )
                      .toList(),
                  onChanged: (speed) {
                    if (speed != null) {
                      _update(_settings.copyWith(defaultSpeed: speed));
                    }
                  },
                ),
              ],
            ),
          ),
        ]),
        const SizedBox(height: 24),
        _sectionTitle('媒体库'),
        _settingsCard([
          _switchRow(
            title: '保存最近播放记录',
            subtitle: '最近打开的视频会保存在本机',
            icon: Icons.history_rounded,
            value: _settings.saveHistory,
            onChanged: (value) =>
                _update(_settings.copyWith(saveHistory: value)),
          ),
        ]),
        const SizedBox(height: 24),
        _sectionTitle('关于 Streambox'),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.play_circle_fill_rounded, color: _green, size: 26),
                  SizedBox(width: 9),
                  Text(
                    'Streambox',
                    style: TextStyle(
                      color: _ink,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 12),
              Text(
                '本地视频优先，WebDAV 作为可选网络来源。',
                style: TextStyle(color: Color(0xFF59635B), fontSize: 12),
              ),
              SizedBox(height: 6),
              Text(
                '播放格式取决于设备解码器；WebDAV 凭据仅保存在当前会话。',
                style: TextStyle(color: Color(0xFF899087), fontSize: 11),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _sectionTitle(String title) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 9),
    child: Text(
      title,
      style: const TextStyle(
        color: _ink,
        fontSize: 13,
        fontWeight: FontWeight.w800,
      ),
    ),
  );

  Widget _settingsCard(List<Widget> children) => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Column(children: children),
  );

  Widget _switchRow({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) => Padding(
    padding: const EdgeInsets.fromLTRB(15, 11, 11, 11),
    child: Row(
      children: [
        Icon(icon, color: _ink, size: 20),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: _ink,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: const TextStyle(color: Color(0xFF7E867D), fontSize: 10),
              ),
            ],
          ),
        ),
        Switch.adaptive(
          value: value,
          activeTrackColor: _green,
          onChanged: onChanged,
        ),
      ],
    ),
  );

  static const _divider = Padding(
    padding: EdgeInsets.symmetric(horizontal: 16),
    child: Divider(height: 1, color: Color(0xFFF0F1EC)),
  );
}

