import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/eq_preset_model.dart';
import '../models/song_model.dart';
import '../services/audio_player_service.dart';
import '../services/local_scanner_service.dart';
import '../services/universal_llm_service.dart';
import '../services/wifi_transfer_server.dart';
import '../widgets/ai_assistant_sheet.dart';
import '../widgets/equalizer_sheet.dart';
import '../widgets/fullscreen_cover_view.dart';
import '../widgets/glass_card_view.dart';
import '../widgets/sleep_timer_sheet.dart';
import '../widgets/vinyl_turntable_view.dart';
import 'player_screen.dart';

/// 完全还原设计原型的全功能主工作台界面：
/// 1. 顶部品牌栏 + 6 大核心功能胶囊按钮（导入本地音乐、AI语音助手、全网在线搜歌、车载点火自启、Wi-Fi局域网传歌、银河音效均衡器、倍速/睡眠定时）
/// 2. 顶部内嵌可随时切换三种经典样式（经典黑胶 / 沉浸大图 / 流光卡片 + 词）的互动播放舱
/// 3. 本地音乐曲库卡片（支持全盘扫描、关键字搜索、全部单曲 / 我喜欢 / Wi-Fi导入 / SQ无损 四大分类 Tab）
class MainScreen extends ConsumerStatefulWidget {
  const MainScreen({super.key});

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen> {
  WifiTransferServer? _wifiServer;
  String? _wifiUrl;

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  /// 弹窗 1：打开 AI 语音助手 (支持 DeepSeek / 火山引擎 / 千问 / GPT / Gemini / Llama)
  void _openAiAssistantModal(PlayerStateModel state, AudioPlayerController controller) {
    final cur = state.currentSong;
    final summary = cur != null ? '《${cur.title}》- ${cur.artist}' : '暂无播放';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AiAssistantSheet(
        currentSongSummary: summary,
        onExecuteCommand: (AiPlayerCommand cmd) async {
          if (cmd.action == 'next') {
            await controller.nextSong();
          } else if (cmd.action == 'prev') {
            await controller.previousSong();
          } else if (cmd.action == 'pause') {
            await controller.pause();
          } else if (cmd.action == 'resume') {
            await controller.togglePlayPause();
          } else if (cmd.action == 'switch_style') {
            if (cmd.targetQuery == 'fullscreen') {
              controller.setVisualStyle(PlayerVisualStyle.fullscreen);
            } else if (cmd.targetQuery == 'glass') {
              controller.setVisualStyle(PlayerVisualStyle.glassCard);
            } else {
              controller.setVisualStyle(PlayerVisualStyle.vinyl);
            }
          } else if (cmd.action == 'set_eq') {
            controller.applyEqPreset(EqPresetModel.builtinPresets[2]);
          } else if (cmd.action == 'play_search') {
            final results = await controller.searchOnlineSongs(cmd.targetQuery ?? '周杰伦');
            if (results.isNotEmpty) {
              await controller.addAndPlaySong(results.first);
            }
          }
        },
      ),
    );
  }

  /// 弹窗 2：打开全网在线搜歌即点即播窗口
  void _openOnlineSearchModal(AudioPlayerController controller) {
    final TextEditingController searchCtrl = TextEditingController(text: '周杰伦');
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF121C26),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        List<SongModel> results = [];
        bool loading = true;
        bool initialized = false;

        return StatefulBuilder(
          builder: (ctx, setModalState) {
            Future<void> runSearch(String kw) async {
              setModalState(() => loading = true);
              final list = await controller.searchOnlineSongs(kw);
              if (ctx.mounted) {
                setModalState(() {
                  results = list;
                  loading = false;
                });
              }
            }

            if (!initialized) {
              initialized = true;
              Future.microtask(() => runSearch('周杰伦'));
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 18,
                right: 18,
                top: 18,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              child: SizedBox(
                height: MediaQuery.of(ctx).size.height * 0.72,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          '🌐 全网在线音乐搜索与即点即播',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white54),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const Text(
                      '输入歌名或歌手，直接在线检索流媒体音源并播放',
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: searchCtrl,
                            style: const TextStyle(color: Colors.white, fontSize: 13),
                            decoration: InputDecoration(
                              hintText: '输入歌名、歌手（如：稻香、林俊杰、邓紫棋）...',
                              hintStyle: const TextStyle(color: Colors.white38),
                              filled: true,
                              fillColor: const Color(0xFF0B1118),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide.none,
                              ),
                            ),
                            onSubmitted: runSearch,
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF00D676),
                            foregroundColor: Colors.black,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: () => runSearch(searchCtrl.text),
                          child: const Text(
                            '立即搜索',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      children: ['稻香', '江南', '邓紫棋', '加州旅馆'].map((hot) {
                        return ActionChip(
                          backgroundColor: Colors.white10,
                          label: Text(
                            hot,
                            style: const TextStyle(color: Colors.white, fontSize: 11),
                          ),
                          onPressed: () {
                            searchCtrl.text = hot;
                            runSearch(hot);
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: loading
                          ? const Center(
                              child: CircularProgressIndicator(
                                color: Color(0xFF00D676),
                              ),
                            )
                          : ListView.separated(
                              itemCount: results.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 8),
                              itemBuilder: (ctx, i) {
                                final item = results[i];
                                return Container(
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF0B1118),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: Colors.white10),
                                  ),
                                  child: ListTile(
                                    leading: CircleAvatar(
                                      backgroundColor: item.dominantColor,
                                      child: const Icon(
                                        Icons.cloud_done_rounded,
                                        color: Colors.white,
                                        size: 18,
                                      ),
                                    ),
                                    title: Text(
                                      item.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    subtitle: Text(
                                      '${item.artist} · ${item.album}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white54,
                                        fontSize: 11,
                                      ),
                                    ),
                                    trailing: ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFF00D676),
                                        foregroundColor: Colors.black,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 6,
                                        ),
                                      ),
                                      onPressed: () async {
                                        Navigator.pop(ctx);
                                        await controller.addAndPlaySong(item);
                                        if (mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              content: Text('已加载并开始播放《${item.title}》'),
                                            ),
                                          );
                                        }
                                      },
                                      child: const Text(
                                        '▶ 播放',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// 弹窗 3：打开车载蓝牙 / CarPlay 点火自动播放设置与模拟点火测试
  void _openCarIgnitionModal(PlayerStateModel state, AudioPlayerController controller) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF121C26),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '🚗 车载蓝牙 / CarPlay 点火自动续播',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                '当手机连接到车载蓝牙 (A2DP) 或 CarPlay 通电握手时，无需解锁手机自动恢复上次播放进度',
                style: TextStyle(color: Colors.white60, fontSize: 12),
              ),
              const SizedBox(height: 14),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                activeColor: const Color(0xFF00D676),
                title: const Text(
                  '车子启动连接车载蓝牙后自动播放',
                  style: TextStyle(color: Colors.white, fontSize: 14),
                ),
                value: state.carAutoPlayEnabled,
                onChanged: (v) {
                  controller.setCarAutoPlay(v);
                  Navigator.pop(ctx);
                },
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00D676),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  icon: const Icon(Icons.key_rounded),
                  label: const Text(
                    '🔑 模拟车子点火启动 (立即唤醒并自动播放)',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await controller.playSongAt(state.currentIndex);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('🚗 检测到车载蓝牙已通电连接，已为您自动续播音乐！'),
                        ),
                      );
                    }
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 弹窗 4：打开 Wi-Fi 局域网无线传歌服务器（显示真实手机局域网 IP:8080）
  Future<void> _openWifiTransferModal(AudioPlayerController controller) async {
    final scanner = LocalScannerService();
    final musicDir = await scanner.getAppMusicDirectory();
    _wifiServer ??= WifiTransferServer(
      targetMusicDirectory: musicDir,
      onFileReceived: (fileName) {
        controller.scanLocalMusic();
      },
    );
    final url = await _wifiServer!.start(port: 8080);
    setState(() => _wifiUrl = url);

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF121C26),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Row(
                children: [
                  Icon(Icons.wifi_tethering_rounded, color: Color(0xFF00E676)),
                  SizedBox(width: 8),
                  Text(
                    'Wi-Fi 局域网无线传歌 (已启动)',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                '请将电脑与本手机连接至同一个 Wi-Fi，在电脑浏览器输入以下地址即可直接拖拽上传 MP3/FLAC/WAV/APE/LRC 文件：',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF0B1118),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: const Color(0xFF00D676).withOpacity(0.5),
                  ),
                ),
                child: Column(
                  children: [
                    const Text(
                      '手机局域网传歌网址',
                      style: TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                    const SizedBox(height: 6),
                    SelectableText(
                      _wifiUrl ?? 'http://127.0.0.1:8080',
                      style: const TextStyle(
                        color: Color(0xFF00E676),
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.folder_open_rounded, color: Color(0xFF00E676)),
                  label: const Text(
                    '或者直接从本机文件夹选择音乐导入',
                    style: TextStyle(color: Color(0xFF00E676)),
                  ),
                  onPressed: () {
                    Navigator.pop(ctx);
                    controller.importAudioFiles();
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(audioPlayerProvider);
    final controller = ref.read(audioPlayerProvider.notifier);
    final song = state.currentSong;
    final filteredSongs = state.filteredSongs;

    final currentLyricIdx = state.currentLyricIndex;
    final currentLyricText = (song != null &&
            currentLyricIdx >= 0 &&
            currentLyricIdx < song.lyrics.length)
        ? song.lyrics[currentLyricIdx].text
        : '纯音乐 / 本地全格式无损曲库';

    return Scaffold(
      backgroundColor: const Color(0xFF090E14),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // ==================== 1. 顶部品牌头 + 6 大核心功能按钮组（100% 还原你的设计图） ====================
            SliverToBoxAdapter(
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                decoration: const BoxDecoration(
                  color: Color(0xFF0B121A),
                  border: Border(
                    bottom: BorderSide(color: Colors.white10),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            gradient: const LinearGradient(
                              colors: [Color(0xFF00E676), Color(0xFF009E54)],
                            ),
                          ),
                          child: const Icon(
                            Icons.music_note_rounded,
                            color: Colors.black,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Text(
                                    '悦听 MeloMusic',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 17,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF00D676).withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(999),
                                      border: Border.all(
                                        color: const Color(0xFF00D676).withOpacity(0.4),
                                      ),
                                    ),
                                    child: const Text(
                                      'Flutter 全能版',
                                      style: TextStyle(
                                        color: Color(0xFF00E676),
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              const Text(
                                '自动识别手机音乐 · 三种播放页样式实时切换 · AI语音操控',
                                style: TextStyle(
                                  color: Colors.white54,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // 顶部 6 大功能胶囊按钮（完全对应你截图2中的按钮布局）
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        // 1. 导入本地音乐/歌词
                        _buildTopPillButton(
                          label: '+ 导入本地音乐/歌词 (.mp3/.flac/.lrc)',
                          bgColor: const Color(0xFF00D676),
                          textColor: Colors.black,
                          isBold: true,
                          onTap: () async {
                            final count = await controller.importAudioFiles();
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    count > 0
                                        ? '成功导入 $count 首音乐并开始播放！'
                                        : '未选择新文件，您也可点击下方「全盘扫描」自动识别手机音乐',
                                  ),
                                ),
                              );
                            }
                          },
                        ),
                        // 2. AI 语音助手 (DeepSeek/豆包/千问/GPT)
                        _buildTopPillButton(
                          label: '🤖 AI 语音助手 (DeepSeek/豆包/千问/GPT)',
                          bgColor: const Color(0xFF14B8A6),
                          textColor: Colors.black,
                          isBold: true,
                          onTap: () => _openAiAssistantModal(state, controller),
                        ),
                        // 3. 全网在线搜歌
                        _buildTopPillButton(
                          label: '🌐 全网在线搜歌',
                          bgColor: const Color(0xFF00D676).withOpacity(0.16),
                          textColor: const Color(0xFF00E676),
                          borderColor: const Color(0xFF00D676).withOpacity(0.45),
                          isBold: true,
                          onTap: () => _openOnlineSearchModal(controller),
                        ),
                        // 4. 车载点火自启
                        _buildTopPillButton(
                          label:
                              '🚗 车载点火自启: ${state.carAutoPlayEnabled ? "已开启" : "已关闭"}',
                          bgColor: Colors.white.withOpacity(0.08),
                          textColor: Colors.white,
                          onTap: () => _openCarIgnitionModal(state, controller),
                        ),
                        // 5. Wi-Fi 局域网传歌
                        _buildTopPillButton(
                          label: '📡 Wi-Fi 局域网传歌 (iOS/安卓导歌)',
                          bgColor: Colors.white.withOpacity(0.08),
                          textColor: Colors.white,
                          onTap: () => _openWifiTransferModal(controller),
                        ),
                        // 6. 银河音效 / 均衡器
                        _buildTopPillButton(
                          label: '🎛️ 银河音效 / 均衡器',
                          bgColor: Colors.white.withOpacity(0.08),
                          textColor: Colors.white,
                          onTap: () => showModalBottomSheet(
                            context: context,
                            backgroundColor: Colors.transparent,
                            builder: (_) => const EqualizerSheet(),
                          ),
                        ),
                        // 7. 倍速与睡眠定时
                        _buildTopPillButton(
                          label:
                              '⏱️ ${state.playbackSpeed}x · ${state.sleepTimerRemaining != null ? _formatDuration(state.sleepTimerRemaining!) : "睡眠定时"}',
                          bgColor: Colors.white.withOpacity(0.08),
                          textColor: Colors.white,
                          onTap: () => showModalBottomSheet(
                            context: context,
                            backgroundColor: Colors.transparent,
                            builder: (_) => const SleepTimerAndSpeedSheet(),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // ==================== 2. 内嵌仿 QQ 音乐三样式切换主播放舱（直接在首页展示黑胶/大图/流光卡片！） ====================
            if (song != null)
              SliverToBoxAdapter(
                child: Container(
                  margin: const EdgeInsets.fromLTRB(14, 14, 14, 8),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(28),
                    gradient: LinearGradient(
                      colors: [
                        song.dominantColor.withOpacity(0.45),
                        song.accentColor,
                        const Color(0xFF0A0F16),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    border: Border.all(color: Colors.white12, width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: song.dominantColor.withOpacity(0.18),
                        blurRadius: 24,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      // 顶部：音质徽章 + 三种经典样式实时切换胶囊 + AI/词按钮
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black45,
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: const Color(0xFF00E676).withOpacity(0.35),
                              ),
                            ),
                            child: Text(
                              song.format.split(' ').first,
                              style: const TextStyle(
                                color: Color(0xFF00E676),
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          // 经典黑胶 / 沉浸大图 / 流光卡片 一键切换器
                          Container(
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              color: Colors.black45,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: PlayerVisualStyle.values.map((style) {
                                final active = state.visualStyle == style &&
                                    !state.showLyricsInline;
                                return GestureDetector(
                                  onTap: () => controller.setVisualStyle(style),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: active
                                          ? const Color(0xFF00D676)
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      style.label,
                                      style: TextStyle(
                                        color: active
                                            ? Colors.black
                                            : Colors.white70,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                          Row(
                            children: [
                              GestureDetector(
                                onTap: () => controller.toggleInlineLyrics(),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 9,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: state.showLyricsInline
                                        ? const Color(0xFF00D676)
                                        : Colors.black45,
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(color: Colors.white24),
                                  ),
                                  child: Text(
                                    '词',
                                    style: TextStyle(
                                      color: state.showLyricsInline
                                          ? Colors.black
                                          : Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              GestureDetector(
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => const PlayerScreen(),
                                  ),
                                ),
                                child: const Icon(
                                  Icons.open_in_full_rounded,
                                  color: Colors.white70,
                                  size: 18,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      // 中央三样式视觉展示区（高度 280，支持点击歌词跳转）
                      SizedBox(
                        height: 280,
                        child: state.showLyricsInline
                            ? ListView.builder(
                                itemCount: song.lyrics.length,
                                itemBuilder: (ctx, idx) {
                                  final line = song.lyrics[idx];
                                  final active = idx == currentLyricIdx;
                                  return GestureDetector(
                                    onTap: () =>
                                        controller.seekTo(line.timestamp),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 8,
                                      ),
                                      child: Text(
                                        line.text,
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: active
                                              ? const Color(0xFF00E676)
                                              : Colors.white54,
                                          fontSize: active ? 16 : 13,
                                          fontWeight: active
                                              ? FontWeight.bold
                                              : FontWeight.normal,
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              )
                            : switch (state.visualStyle) {
                                PlayerVisualStyle.vinyl => Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Expanded(
                                        child: Transform.scale(
                                          scale: 0.78,
                                          child: VinylTurntableView(
                                            song: song,
                                            isPlaying: state.isPlaying,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        currentLyricText,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Color(0xFF00E676),
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                PlayerVisualStyle.fullscreen =>
                                  FullscreenCoverView(
                                    song: song,
                                    currentLyricText: currentLyricText,
                                  ),
                                PlayerVisualStyle.glassCard => GlassCardView(
                                    song: song,
                                    isPlaying: state.isPlaying,
                                    currentLyricText: currentLyricText,
                                  ),
                              },
                      ),
                      const SizedBox(height: 10),
                      // 歌曲标题、收藏红心、进度条与播放主控按钮
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
                                    fontSize: 17,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  '${song.artist} · ${song.album}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
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
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 3.5,
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 6,
                          ),
                        ),
                        child: Slider(
                          value: state.position.inSeconds
                              .clamp(
                                0,
                                state.duration.inSeconds.clamp(1, 99999),
                              )
                              .toDouble(),
                          max: state.duration.inSeconds
                              .clamp(1, 99999)
                              .toDouble(),
                          activeColor: const Color(0xFF00D676),
                          inactiveColor: Colors.white24,
                          onChanged: (v) =>
                              controller.seekTo(Duration(seconds: v.toInt())),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _formatDuration(state.position),
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 11,
                              ),
                            ),
                            Text(
                              '银河音效: ${state.activeEqPreset.name} · ${state.playbackSpeed}x',
                              style: const TextStyle(
                                color: Color(0xFF00E676),
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              _formatDuration(state.duration),
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          TextButton.icon(
                            onPressed: controller.cycleLoopMode,
                            icon: Icon(
                              state.loopMode.icon,
                              color: Colors.white70,
                              size: 18,
                            ),
                            label: Text(
                              state.loopMode.label.substring(0, 2),
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.skip_previous_rounded,
                              color: Colors.white,
                              size: 32,
                            ),
                            onPressed: controller.previousSong,
                          ),
                          GestureDetector(
                            onTap: controller.togglePlayPause,
                            child: Container(
                              width: 54,
                              height: 54,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Color(0xFF00D676),
                                boxShadow: [
                                  BoxShadow(
                                    color: Color(0x6600D676),
                                    blurRadius: 14,
                                  ),
                                ],
                              ),
                              child: Icon(
                                state.isPlaying
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                                color: Colors.black,
                                size: 32,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.skip_next_rounded,
                              color: Colors.white,
                              size: 32,
                            ),
                            onPressed: controller.nextSong,
                          ),
                          TextButton.icon(
                            onPressed: () => showModalBottomSheet(
                              context: context,
                              backgroundColor: Colors.transparent,
                              builder: (_) => const EqualizerSheet(),
                            ),
                            icon: const Icon(
                              Icons.tune_rounded,
                              color: Color(0xFF00E676),
                              size: 18,
                            ),
                            label: const Text(
                              '音效',
                              style: TextStyle(
                                color: Color(0xFF00E676),
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

            // ==================== 3. 我的本地音乐库卡片（全盘扫描 + 搜索框 + 4 个分类 Tab + 歌曲列表） ====================
            SliverToBoxAdapter(
              child: Container(
                margin: const EdgeInsets.fromLTRB(14, 8, 14, 24),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF101923),
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(color: Colors.white10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Text(
                                    '我的本地音乐库',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF00D676)
                                          .withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      '${state.allSongs.length} 首',
                                      style: const TextStyle(
                                        color: Color(0xFF00E676),
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 3),
                              const Text(
                                '启动免导入自动全盘识别 · 支持 MP3/FLAC/APE/DSD/WAV/ALAC/OGG',
                                style: TextStyle(
                                  color: Colors.white54,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(
                              color: const Color(0xFF00D676).withOpacity(0.45),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: () async {
                            final count = await controller.scanLocalMusic();
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    '全盘扫描完成：发现 $count 首手机本地音频（预置曲目可直接点击播放听音）',
                                  ),
                                ),
                              );
                            }
                          },
                          child: const Text(
                            '全盘扫描',
                            style: TextStyle(
                              color: Color(0xFF00E676),
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // 本地曲库搜索框
                    TextField(
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: '搜索本地歌曲、歌手、专辑...',
                        hintStyle: const TextStyle(color: Colors.white38),
                        prefixIcon: const Icon(
                          Icons.search_rounded,
                          color: Colors.white38,
                          size: 18,
                        ),
                        filled: true,
                        fillColor: const Color(0xFF0B1118),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onChanged: controller.setSearchQuery,
                    ),
                    const SizedBox(height: 10),
                    // 4 个歌单分类 Tab：全部单曲 / 我喜欢 ♥ / Wi-Fi/导入 / SQ无损
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0B1118),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          _buildFilterTab(
                            label: '全部单曲',
                            keyName: 'all',
                            activeFilter: state.activePlaylistFilter,
                            onTap: () => controller.setPlaylistFilter('all'),
                          ),
                          _buildFilterTab(
                            label: '我喜欢 ♥',
                            keyName: 'fav',
                            activeFilter: state.activePlaylistFilter,
                            onTap: () => controller.setPlaylistFilter('fav'),
                          ),
                          _buildFilterTab(
                            label: 'Wi-Fi/导入',
                            keyName: 'wifi',
                            activeFilter: state.activePlaylistFilter,
                            onTap: () => controller.setPlaylistFilter('wifi'),
                          ),
                          _buildFilterTab(
                            label: 'SQ无损',
                            keyName: 'lossless',
                            activeFilter: state.activePlaylistFilter,
                            onTap: () =>
                                controller.setPlaylistFilter('lossless'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    // 歌曲列表
                    if (filteredSongs.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 32),
                        child: Center(
                          child: Text(
                            '当前分类下暂无歌曲，可点击上方「全网在线搜歌」或「导入本地音乐」',
                            style: TextStyle(color: Colors.white38, fontSize: 12),
                          ),
                        ),
                      )
                    else
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: filteredSongs.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (ctx, idx) {
                          final item = filteredSongs[idx];
                          final isCurrent = song?.id == item.id;
                          return GestureDetector(
                            onTap: () => controller.playSongById(item.id),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: isCurrent
                                    ? const Color(0xFF00D676).withOpacity(0.15)
                                    : const Color(0xFF0B121A),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: isCurrent
                                      ? const Color(0xFF00D676).withOpacity(0.45)
                                      : Colors.white10,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 42,
                                    height: 42,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(12),
                                      gradient: LinearGradient(
                                        colors: [
                                          item.dominantColor,
                                          item.accentColor,
                                        ],
                                      ),
                                    ),
                                    child: Icon(
                                      isCurrent && state.isPlaying
                                          ? Icons.volume_up_rounded
                                          : Icons.music_note_rounded,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item.title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: isCurrent
                                                ? const Color(0xFF00E676)
                                                : Colors.white,
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Row(
                                          children: [
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 5,
                                                vertical: 1,
                                              ),
                                              decoration: BoxDecoration(
                                                color: Colors.white10,
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                item.format.split(' ').first,
                                                style: const TextStyle(
                                                  color: Color(0xFF00E676),
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Expanded(
                                              child: Text(
                                                '${item.artist} · ${item.album}',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  color: Colors.white54,
                                                  fontSize: 11,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    icon: Icon(
                                      item.isFavorite
                                          ? Icons.favorite_rounded
                                          : Icons.favorite_border_rounded,
                                      color: item.isFavorite
                                          ? Colors.redAccent
                                          : Colors.white38,
                                      size: 20,
                                    ),
                                    onPressed: () =>
                                        controller.toggleFavorite(item.id),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopPillButton({
    required String label,
    required Color bgColor,
    required Color textColor,
    Color? borderColor,
    bool isBold = false,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor ?? Colors.white12),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: textColor,
            fontSize: 11,
            fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildFilterTab({
    required String label,
    required String keyName,
    required String activeFilter,
    required VoidCallback onTap,
  }) {
    final active = activeFilter == keyName;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: BoxDecoration(
            color: active ? const Color(0xFF00D676) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: active ? Colors.black : Colors.white60,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}
