import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/audio_player_service.dart';

/// 倍速播放 (0.5x~2.0x) 与睡眠定时关闭底部设置面板
class SleepTimerAndSpeedSheet extends ConsumerWidget {
  const SleepTimerAndSpeedSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(audioPlayerProvider);
    final controller = ref.read(audioPlayerProvider.notifier);
    const speeds = [0.75, 1.0, 1.25, 1.5, 2.0];
    const timerMins = [0, 15, 30, 45, 60];

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
      decoration: const BoxDecoration(
        color: Color(0xFF121A24),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '倍速播放 (变速不变调)',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            children: speeds.map((s) {
              final active = state.playbackSpeed == s;
              return ChoiceChip(
                label: Text('${s}x'),
                selected: active,
                selectedColor: const Color(0xFF00D676),
                onSelected: (_) => controller.setPlaybackSpeed(s),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          const Text(
            '睡眠定时关闭',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            children: timerMins.map((m) {
              return ActionChip(
                label: Text(m == 0 ? '关闭定时' : '$m 分钟'),
                onPressed: () => controller.startSleepTimer(m),
              );
            }).toList(),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text(
              '播完当前歌曲后自动暂停',
              style: TextStyle(color: Colors.white, fontSize: 14),
            ),
            value: state.stopAfterCurrentSong,
            activeColor: const Color(0xFF00D676),
            onChanged: controller.setStopAfterCurrentSong,
          ),
        ],
      ),
    );
  }
}
