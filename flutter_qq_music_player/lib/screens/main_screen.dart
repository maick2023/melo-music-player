import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/audio_player_service.dart';
import 'player_screen.dart';

/// 仿 QQ 音乐主界面：包含本地扫描、iOS/Android 文件导入、Wi-Fi 无线传歌入口与底部悬浮胶囊播放栏
class MainScreen extends ConsumerWidget {
  const MainScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(audioPlayerProvider);
    final controller = ref.read(audioPlayerProvider.notifier);
    final currentSong = state.currentSong;

    return Scaffold(
      backgroundColor: const Color(0xFF0B1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B1117),
        elevation: 0,
        title: const Row(
          children: [
            Icon(Icons.music_note_rounded, color: Color(0xFF00D676)),
            SizedBox(width: 8),
            Text(
              '悦听 · 本地无损音乐',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 19),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: '扫描手机本地音乐',
            icon: const Icon(Icons.radar_rounded, color: Color(0xFF00D676)),
            onPressed: () async {
              final count = await controller.scanLocalMusic();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('扫描完成，共发现 $count 首本地歌曲')),
                );
              }
            },
          ),
          IconButton(
            tooltip: '从文件导入音频',
            icon: const Icon(Icons.folder_open_rounded, color: Colors.white),
            onPressed: () => controller.importAudioFiles(),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
              itemCount: state.currentQueue.length,
              itemBuilder: (context, idx) {
                final song = state.currentQueue[idx];
                final active = idx == state.currentIndex;
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  tileColor: active
                      ? const Color(0xFF00D676).withOpacity(0.12)
                      : Colors.transparent,
                  leading: CircleAvatar(
                    backgroundColor: song.dominantColor,
                    child: const Icon(
                      Icons.music_note_rounded,
                      color: Colors.white,
                    ),
                  ),
                  title: Text(
                    song.title,
                    style: TextStyle(
                      color: active ? const Color(0xFF00D676) : Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    '${song.artist} · ${song.album} (${song.format})',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  trailing: IconButton(
                    icon: Icon(
                      song.isFavorite
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                      color: song.isFavorite
                          ? Colors.redAccent
                          : Colors.white38,
                    ),
                    onPressed: () => controller.toggleFavorite(song.id),
                  ),
                  onTap: () => controller.playSongAt(idx),
                );
              },
            ),
          ),
        ],
      ),
      // 底部悬浮 QQ 音乐胶囊 Mini 播放条
      bottomSheet: currentSong == null
          ? null
          : GestureDetector(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const PlayerScreen()),
              ),
              child: Container(
                margin: const EdgeInsets.fromLTRB(14, 0, 14, 16),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF16222F),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: Colors.white12),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: currentSong.dominantColor,
                      child: const Icon(
                        Icons.album_rounded,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            currentSong.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            currentSong.artist,
                            style: const TextStyle(
                              color: Color(0xFF00D676),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        state.isPlaying
                            ? Icons.pause_circle_filled_rounded
                            : Icons.play_circle_fill_rounded,
                        color: const Color(0xFF00D676),
                        size: 36,
                      ),
                      onPressed: controller.togglePlayPause,
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.skip_next_rounded,
                        color: Colors.white,
                      ),
                      onPressed: controller.nextSong,
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
