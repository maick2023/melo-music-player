import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/song_model.dart';
import '../services/audio_player_service.dart';
import '../widgets/equalizer_sheet.dart';
import '../widgets/fullscreen_cover_view.dart';
import '../widgets/glass_card_view.dart';
import '../widgets/sleep_timer_sheet.dart';
import '../widgets/vinyl_turntable_view.dart';

/// 仿 QQ 音乐全屏播放面板：支持三种经典样式自由切换 + 全屏滚动歌词
class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({super.key});

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  bool _showFullLyrics = false;

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(audioPlayerProvider);
    final controller = ref.read(audioPlayerProvider.notifier);
    final song = state.currentSong;
    if (song == null) return const SizedBox.shrink();

    final currentLyricIdx = state.currentLyricIndex;
    final currentLyricText =
        (currentLyricIdx >= 0 && currentLyricIdx < song.lyrics.length)
            ? song.lyrics[currentLyricIdx].text
            : '纯音乐 / 本地无损曲库';

    return Scaffold(
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 600),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              song.dominantColor.withOpacity(0.45),
              song.accentColor,
              const Color(0xFF090D14),
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // 顶部栏：下拉收起 + 三种经典样式实时切换胶囊 + 歌词开关
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: Colors.white,
                        size: 30,
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    // 三种经典样式一键切换器
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.black38,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        children: PlayerVisualStyle.values.map((style) {
                          final selected = state.visualStyle == style;
                          return GestureDetector(
                            onTap: () => controller.setVisualStyle(style),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: selected
                                    ? const Color(0xFF00D676)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                style.label,
                                style: TextStyle(
                                  color: selected
                                      ? Colors.black
                                      : Colors.white70,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        _showFullLyrics
                            ? Icons.album_rounded
                            : Icons.lyrics_rounded,
                        color: const Color(0xFF00D676),
                      ),
                      onPressed: () =>
                          setState(() => _showFullLyrics = !_showFullLyrics),
                    ),
                  ],
                ),
              ),
              // 中央主视觉区：全屏歌词 或 三种经典样式视图
              Expanded(
                child: _showFullLyrics
                    ? ListView.builder(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 28,
                          vertical: 24,
                        ),
                        itemCount: song.lyrics.length,
                        itemBuilder: (context, idx) {
                          final line = song.lyrics[idx];
                          final active = idx == currentLyricIdx;
                          return GestureDetector(
                            onTap: () => controller.seekTo(line.timestamp),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Text(
                                line.text,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: active
                                      ? const Color(0xFF00E676)
                                      : Colors.white54,
                                  fontSize: active ? 20 : 15,
                                  fontWeight: active
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                            ),
                          );
                        },
                      )
                    : AnimatedSwitcher(
                        duration: const Duration(milliseconds: 350),
                        child: switch (state.visualStyle) {
                          PlayerVisualStyle.vinyl => VinylTurntableView(
                              key: const ValueKey('vinyl'),
                              song: song,
                              isPlaying: state.isPlaying,
                            ),
                          PlayerVisualStyle.fullscreen => FullscreenCoverView(
                              key: const ValueKey('fullscreen'),
                              song: song,
                              currentLyricText: currentLyricText,
                            ),
                          PlayerVisualStyle.glassCard => GlassCardView(
                              key: const ValueKey('glassCard'),
                              song: song,
                              isPlaying: state.isPlaying,
                              currentLyricText: currentLyricText,
                            ),
                        },
                      ),
              ),
              // 底部歌曲信息、音效/定时快捷入口与进度条
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                song.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 21,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${song.artist} · ${song.format}',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: Icon(
                            song.isFavorite
                                ? Icons.favorite_rounded
                                : Icons.favorite_border_rounded,
                            color: song.isFavorite
                                ? Colors.redAccent
                                : Colors.white70,
                          ),
                          onPressed: () => controller.toggleFavorite(song.id),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // 银河音效 / 倍速 / 睡眠定时按钮栏
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        TextButton.icon(
                          onPressed: () => showModalBottomSheet(
                            context: context,
                            backgroundColor: Colors.transparent,
                            builder: (_) => const EqualizerSheet(),
                          ),
                          icon: const Icon(
                            Icons.equalizer_rounded,
                            color: Color(0xFF00D676),
                            size: 18,
                          ),
                          label: Text(
                            '音效: ${state.activeEqPreset.name}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () => showModalBottomSheet(
                            context: context,
                            backgroundColor: Colors.transparent,
                            builder: (_) => const SleepTimerAndSpeedSheet(),
                          ),
                          icon: const Icon(
                            Icons.timer_outlined,
                            color: Color(0xFF00D676),
                            size: 18,
                          ),
                          label: Text(
                            '${state.playbackSpeed}x · ${state.sleepTimerRemaining != null ? _formatDuration(state.sleepTimerRemaining!) : "定时"}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                    Slider(
                      value: state.position.inSeconds
                          .clamp(0, state.duration.inSeconds.clamp(1, 99999))
                          .toDouble(),
                      max: state.duration.inSeconds.clamp(1, 99999).toDouble(),
                      activeColor: const Color(0xFF00D676),
                      inactiveColor: Colors.white24,
                      onChanged: (v) =>
                          controller.seekTo(Duration(seconds: v.toInt())),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _formatDuration(state.position),
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                          ),
                        ),
                        Text(
                          _formatDuration(state.duration),
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        IconButton(
                          icon: Icon(
                            state.loopMode.icon,
                            color: Colors.white70,
                          ),
                          onPressed: controller.cycleLoopMode,
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.skip_previous_rounded,
                            color: Colors.white,
                            size: 36,
                          ),
                          onPressed: controller.previousSong,
                        ),
                        FloatingActionButton(
                          backgroundColor: const Color(0xFF00D676),
                          onPressed: controller.togglePlayPause,
                          child: Icon(
                            state.isPlaying
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            color: Colors.black,
                            size: 34,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.skip_next_rounded,
                            color: Colors.white,
                            size: 36,
                          ),
                          onPressed: controller.nextSong,
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.queue_music_rounded,
                            color: Colors.white70,
                          ),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
