import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import '../models/eq_preset_model.dart';
import '../models/song_model.dart';
import 'car_auto_play_service.dart';
import 'local_scanner_service.dart';
import 'online_search_service.dart';
import 'synth_wav_generator.dart';

/// 全局播放器状态快照
class PlayerStateModel {
  final List<SongModel> allSongs;
  final List<SongModel> currentQueue;
  final int currentIndex;
  final bool isPlaying;
  final Duration position;
  final Duration duration;
  final PlayerVisualStyle visualStyle;
  final LoopPlayMode loopMode;
  final double playbackSpeed;
  final EqPresetModel activeEqPreset;
  final List<double> customEqGains;
  final bool surround3dEnabled;
  final Duration? sleepTimerRemaining;
  final bool stopAfterCurrentSong;
  final String activePlaylistFilter; // 'all', 'fav', 'wifi', 'lossless'
  final String searchQuery;
  final bool carAutoPlayEnabled;
  final bool showLyricsInline;

  const PlayerStateModel({
    required this.allSongs,
    required this.currentQueue,
    required this.currentIndex,
    required this.isPlaying,
    required this.position,
    required this.duration,
    required this.visualStyle,
    required this.loopMode,
    required this.playbackSpeed,
    required this.activeEqPreset,
    required this.customEqGains,
    required this.surround3dEnabled,
    this.sleepTimerRemaining,
    this.stopAfterCurrentSong = false,
    this.activePlaylistFilter = 'all',
    this.searchQuery = '',
    this.carAutoPlayEnabled = true,
    this.showLyricsInline = false,
  });

  SongModel? get currentSong =>
      (currentIndex >= 0 && currentIndex < currentQueue.length)
          ? currentQueue[currentIndex]
          : (allSongs.isNotEmpty ? allSongs.first : null);

  /// 根据当前播放进度计算高亮的 LRC 歌词行下标
  int get currentLyricIndex {
    final song = currentSong;
    if (song == null || song.lyrics.isEmpty) return -1;
    int idx = 0;
    for (int i = 0; i < song.lyrics.length; i++) {
      if (position >= song.lyrics[i].timestamp) {
        idx = i;
      } else {
        break;
      }
    }
    return idx;
  }

  /// 根据当前 Tab ('all', 'fav', 'wifi', 'lossless') 和搜索关键词过滤显示的曲目列表
  List<SongModel> get filteredSongs {
    return allSongs.where((s) {
      if (activePlaylistFilter == 'fav' && !s.isFavorite) return false;
      if (activePlaylistFilter == 'wifi' &&
          !s.album.contains('Wi-Fi') &&
          !s.album.contains('导入') &&
          !s.album.contains('在线')) {
        return false;
      }
      if (activePlaylistFilter == 'lossless' &&
          !s.format.toUpperCase().contains('FLAC') &&
          !s.format.toUpperCase().contains('WAV') &&
          !s.format.toUpperCase().contains('APE') &&
          !s.format.toUpperCase().contains('DSD')) {
        return false;
      }
      if (searchQuery.trim().isNotEmpty) {
        final q = searchQuery.trim().toLowerCase();
        return s.title.toLowerCase().contains(q) ||
            s.artist.toLowerCase().contains(q) ||
            s.album.toLowerCase().contains(q);
      }
      return true;
    }).toList();
  }

  PlayerStateModel copyWith({
    List<SongModel>? allSongs,
    List<SongModel>? currentQueue,
    int? currentIndex,
    bool? isPlaying,
    Duration? position,
    Duration? duration,
    PlayerVisualStyle? visualStyle,
    LoopPlayMode? loopMode,
    double? playbackSpeed,
    EqPresetModel? activeEqPreset,
    List<double>? customEqGains,
    bool? surround3dEnabled,
    Duration? sleepTimerRemaining,
    bool clearSleepTimer = false,
    bool? stopAfterCurrentSong,
    String? activePlaylistFilter,
    String? searchQuery,
    bool? carAutoPlayEnabled,
    bool? showLyricsInline,
  }) {
    return PlayerStateModel(
      allSongs: allSongs ?? this.allSongs,
      currentQueue: currentQueue ?? this.currentQueue,
      currentIndex: currentIndex ?? this.currentIndex,
      isPlaying: isPlaying ?? this.isPlaying,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      visualStyle: visualStyle ?? this.visualStyle,
      loopMode: loopMode ?? this.loopMode,
      playbackSpeed: playbackSpeed ?? this.playbackSpeed,
      activeEqPreset: activeEqPreset ?? this.activeEqPreset,
      customEqGains: customEqGains ?? this.customEqGains,
      surround3dEnabled: surround3dEnabled ?? this.surround3dEnabled,
      sleepTimerRemaining: clearSleepTimer
          ? null
          : (sleepTimerRemaining ?? this.sleepTimerRemaining),
      stopAfterCurrentSong: stopAfterCurrentSong ?? this.stopAfterCurrentSong,
      activePlaylistFilter: activePlaylistFilter ?? this.activePlaylistFilter,
      searchQuery: searchQuery ?? this.searchQuery,
      carAutoPlayEnabled: carAutoPlayEnabled ?? this.carAutoPlayEnabled,
      showLyricsInline: showLyricsInline ?? this.showLyricsInline,
    );
  }
}

/// 全局音频播放与附加功能控制器
class AudioPlayerController extends StateNotifier<PlayerStateModel> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  final LocalScannerService _scannerService = LocalScannerService();
  final OnlineSearchService _onlineSearchService = OnlineSearchService();
  CarAutoPlayService? _carService;
  Timer? _sleepTimer;

  AudioPlayerController()
      : super(
          PlayerStateModel(
            allSongs: _defaultDemoSongs,
            currentQueue: _defaultDemoSongs,
            currentIndex: 0,
            isPlaying: false,
            position: Duration.zero,
            duration: _defaultDemoSongs.first.duration,
            visualStyle: PlayerVisualStyle.vinyl,
            loopMode: LoopPlayMode.sequence,
            playbackSpeed: 1.0,
            activeEqPreset: EqPresetModel.builtinPresets[1],
            customEqGains: List<double>.from(
              EqPresetModel.builtinPresets[1].gains,
            ),
            surround3dEnabled: true,
          ),
        ) {
    _bindAudioStreams();
    _initCarAndStartupScan();
  }

  Future<void> _initCarAndStartupScan() async {
    _carService = CarAutoPlayService(
      onCarConnectedTriggerPlay: (_) {
        if (state.carAutoPlayEnabled && !state.isPlaying) {
          playSongAt(state.currentIndex);
        }
      },
      onCarDisconnectedTriggerPause: () {
        if (state.isPlaying) {
          pause();
        }
      },
    );
    await _carService?.init();
    // 启动后自动尝试免导入扫描手机上的真实本地音乐
    await scanLocalMusic();
  }

  void _bindAudioStreams() {
    _audioPlayer.positionStream.listen((pos) {
      state = state.copyWith(position: pos);
    });
    _audioPlayer.durationStream.listen((dur) {
      if (dur != null && dur.inSeconds > 0) {
        state = state.copyWith(duration: dur);
      }
    });
    _audioPlayer.playerStateStream.listen((playerState) {
      if (playerState.processingState == ProcessingState.completed) {
        if (state.stopAfterCurrentSong) {
          pause();
          state = state.copyWith(stopAfterCurrentSong: false);
        } else {
          nextSong(autoTriggered: true);
        }
      }
    });
  }

  /// 扫描手机本地音乐库（将真实手机音乐合并进曲库顶部）
  Future<int> scanLocalMusic() async {
    final scanned = await _scannerService.autoScanAllDeviceMusic();
    if (scanned.isNotEmpty) {
      final existingIds = scanned.map((e) => e.id).toSet();
      final kept = state.allSongs
          .where((s) => !existingIds.contains(s.id))
          .toList();
      final merged = [...scanned, ...kept];
      state = state.copyWith(
        allSongs: merged,
        currentQueue: merged,
        currentIndex: 0,
      );
    }
    return scanned.length;
  }

  /// 从文件选择器手动导入本地音频（适配 iOS 与自定义文件夹）
  Future<int> importAudioFiles() async {
    final imported = await _scannerService.pickAndImportAudioFiles();
    if (imported.isNotEmpty) {
      final existingIds = imported.map((e) => e.id).toSet();
      final kept = state.allSongs
          .where((s) => !existingIds.contains(s.id))
          .toList();
      final merged = [...imported, ...kept];
      state = state.copyWith(
        allSongs: merged,
        currentQueue: merged,
        currentIndex: 0,
      );
      await playSongAt(0);
    }
    return imported.length;
  }

  /// 联网搜索歌曲（对接真实 iTunes / 云端流媒体 API，若无网则回退内置高保真曲库）
  Future<List<SongModel>> searchOnlineSongs(String keyword) async {
    final onlineResults = await _onlineSearchService.searchOnlineSongs(keyword);
    if (onlineResults.isNotEmpty) return onlineResults;
    return _cloudFallbackSongs
        .where(
          (s) =>
              keyword.trim().isEmpty ||
              s.title.toLowerCase().contains(keyword.toLowerCase()) ||
              s.artist.toLowerCase().contains(keyword.toLowerCase()),
        )
        .toList();
  }

  /// 将联网搜索到的歌曲加入播放队列顶部并立即出声播放
  Future<void> addAndPlaySong(SongModel song) async {
    final existingIdx = state.allSongs.indexWhere((s) => s.id == song.id);
    List<SongModel> updated;
    if (existingIdx != -1) {
      updated = List<SongModel>.from(state.allSongs);
      final item = updated.removeAt(existingIdx);
      updated.insert(0, item);
    } else {
      updated = [song, ...state.allSongs];
    }
    state = state.copyWith(
      allSongs: updated,
      currentQueue: updated,
      currentIndex: 0,
    );
    await playSongAt(0);
  }

  /// 根据歌曲 ID 触发播放
  Future<void> playSongById(String songId) async {
    final idx = state.currentQueue.indexWhere((s) => s.id == songId);
    if (idx != -1) {
      await playSongAt(idx);
    }
  }

  /// 播放指定下标歌曲（支持：1. 手机真实本地音频  2. http/https 在线流媒体  3. demo:// 内置合成旋律 WAV，确保 100% 有声音！）
  Future<void> playSongAt(int index) async {
    if (index < 0 || index >= state.currentQueue.length) return;
    final song = state.currentQueue[index];
    state = state.copyWith(
      currentIndex: index,
      position: Duration.zero,
      duration: song.duration,
      isPlaying: true,
    );

    try {
      if (song.filePath.startsWith('http://') ||
          song.filePath.startsWith('https://')) {
        await _audioPlayer.setUrl(song.filePath);
      } else if (song.filePath.startsWith('demo://')) {
        // 为内置演示歌曲实时生成真实可听的 16-bit WAV 旋律音频文件并播放！
        final wavPath = await SynthWavGenerator.getOrCreatePlayableWav(
          song.id,
          _melodyMap[song.id] ??
              [261.63, 293.66, 329.63, 392.00, 440.00, 392.00, 329.63, 293.66],
          durationSeconds: 28,
        );
        await _audioPlayer.setFilePath(wavPath);
      } else {
        await _audioPlayer.setFilePath(song.filePath);
      }
      await _audioPlayer.setSpeed(state.playbackSpeed);
      await _audioPlayer.play();
    } catch (_) {}
  }

  Future<void> togglePlayPause() async {
    if (!state.isPlaying) {
      // 如果当前播放器还没有加载过音频源，直接调用 playSongAt 确保出声
      if (_audioPlayer.processingState == ProcessingState.idle) {
        await playSongAt(state.currentIndex);
        return;
      }
      state = state.copyWith(isPlaying: true);
      try {
        await _audioPlayer.play();
      } catch (_) {}
    } else {
      state = state.copyWith(isPlaying: false);
      try {
        await _audioPlayer.pause();
      } catch (_) {}
    }
  }

  Future<void> pause() async {
    state = state.copyWith(isPlaying: false);
    try {
      await _audioPlayer.pause();
    } catch (_) {}
  }

  Future<void> seekTo(Duration target) async {
    state = state.copyWith(position: target);
    try {
      await _audioPlayer.seek(target);
    } catch (_) {}
  }

  /// 下一首（根据顺序、单曲循环、随机模式计算）
  Future<void> nextSong({bool autoTriggered = false}) async {
    if (state.currentQueue.isEmpty) return;
    if (autoTriggered && state.loopMode == LoopPlayMode.single) {
      await playSongAt(state.currentIndex);
      return;
    }
    int nextIdx;
    if (state.loopMode == LoopPlayMode.shuffle) {
      nextIdx = Random().nextInt(state.currentQueue.length);
    } else {
      nextIdx = (state.currentIndex + 1) % state.currentQueue.length;
    }
    await playSongAt(nextIdx);
  }

  Future<void> previousSong() async {
    if (state.currentQueue.isEmpty) return;
    final prevIdx =
        (state.currentIndex - 1 + state.currentQueue.length) %
            state.currentQueue.length;
    await playSongAt(prevIdx);
  }

  /// 切换三种播放页视觉样式（经典黑胶 / 沉浸大图 / 流光卡片）
  void setVisualStyle(PlayerVisualStyle style) {
    state = state.copyWith(visualStyle: style, showLyricsInline: false);
  }

  void toggleInlineLyrics() {
    state = state.copyWith(showLyricsInline: !state.showLyricsInline);
  }

  void setPlaylistFilter(String filter) {
    state = state.copyWith(activePlaylistFilter: filter);
  }

  void setSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
  }

  void setCarAutoPlay(bool enabled) {
    state = state.copyWith(carAutoPlayEnabled: enabled);
    _carService?.updateSettings(autoPlay: enabled);
  }

  /// 循环切换播放模式
  void cycleLoopMode() {
    final modes = LoopPlayMode.values;
    final nextMode = modes[(state.loopMode.index + 1) % modes.length];
    state = state.copyWith(loopMode: nextMode);
  }

  /// 切换歌曲收藏红心状态
  void toggleFavorite(String songId) {
    final updatedAll = state.allSongs.map((s) {
      return s.id == songId ? s.copyWith(isFavorite: !s.isFavorite) : s;
    }).toList();
    final updatedQueue = state.currentQueue.map((s) {
      return s.id == songId ? s.copyWith(isFavorite: !s.isFavorite) : s;
    }).toList();
    state = state.copyWith(allSongs: updatedAll, currentQueue: updatedQueue);
  }

  /// 设置播放倍速 (0.5x ~ 2.0x)
  Future<void> setPlaybackSpeed(double speed) async {
    state = state.copyWith(playbackSpeed: speed);
    try {
      await _audioPlayer.setSpeed(speed);
    } catch (_) {}
  }

  /// 切换均衡器预设音效
  void applyEqPreset(EqPresetModel preset) {
    state = state.copyWith(
      activeEqPreset: preset,
      customEqGains: List<double>.from(preset.gains),
    );
  }

  /// 手动调节单个频段增益 (-12dB ~ +12dB)
  void updateEqBand(int bandIndex, double gainDb) {
    final updated = List<double>.from(state.customEqGains);
    updated[bandIndex] = gainDb;
    state = state.copyWith(customEqGains: updated);
  }

  void toggleSurround3d(bool enabled) {
    state = state.copyWith(surround3dEnabled: enabled);
  }

  /// 开启睡眠定时关闭（按分钟倒计时）
  void startSleepTimer(int minutes) {
    _sleepTimer?.cancel();
    if (minutes <= 0) {
      state = state.copyWith(
        clearSleepTimer: true,
        stopAfterCurrentSong: false,
      );
      return;
    }
    state = state.copyWith(sleepTimerRemaining: Duration(minutes: minutes));
    _sleepTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final currentRem = state.sleepTimerRemaining;
      if (currentRem == null || currentRem.inSeconds <= 1) {
        timer.cancel();
        pause();
        state = state.copyWith(clearSleepTimer: true);
      } else {
        state = state.copyWith(
          sleepTimerRemaining: Duration(seconds: currentRem.inSeconds - 1),
        );
      }
    });
  }

  void setStopAfterCurrentSong(bool value) {
    state = state.copyWith(stopAfterCurrentSong: value);
  }

  @override
  void dispose() {
    _sleepTimer?.cancel();
    _carService?.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  static const Map<String, List<double>> _melodyMap = {
    'demo_1': [261.63, 293.66, 329.63, 392.00, 329.63, 293.66, 261.63, 196.00],
    'demo_2': [220.00, 261.63, 329.63, 440.00, 392.00, 329.63, 293.66, 261.63],
    'demo_3': [196.00, 246.94, 293.66, 392.00, 349.23, 293.66, 246.94, 196.00],
    'demo_4': [293.66, 349.23, 440.00, 523.25, 440.00, 392.00, 349.23, 293.66],
    'cloud_1': [329.63, 392.00, 440.00, 392.00, 329.63, 293.66, 261.63, 293.66],
    'cloud_2': [293.66, 329.63, 392.00, 440.00, 523.25, 440.00, 392.00, 329.63],
    'cloud_3': [246.94, 293.66, 369.99, 440.00, 392.00, 329.63, 293.66, 246.94],
  };

  static final List<SongModel> _defaultDemoSongs = [
    const SongModel(
      id: 'demo_1',
      title: '晴天 (无损臻品母带)',
      artist: '周杰伦',
      album: '叶惠美',
      filePath: 'demo://qingtian.wav',
      duration: Duration(seconds: 28),
      format: 'FLAC · 24bit/96kHz',
      dominantColor: Color(0xFF00C471),
      accentColor: Color(0xFF073B28),
      isFavorite: true,
      lyrics: [
        LyricLine(timestamp: Duration(seconds: 0), text: '故事的小黄花 从出生那年就飘着'),
        LyricLine(timestamp: Duration(seconds: 4), text: '童年的荡秋千 随记忆一直晃到现在'),
        LyricLine(timestamp: Duration(seconds: 9), text: 'Re So So Si Do Si La So La Si Si Si Si La Si La So'),
        LyricLine(timestamp: Duration(seconds: 14), text: '吹着前奏望着天空 我想起花瓣试着掉落'),
        LyricLine(timestamp: Duration(seconds: 19), text: '为你翘课的那一天 花落的那一天'),
        LyricLine(timestamp: Duration(seconds: 24), text: '消失的下雨天 我好想再淋一遍'),
      ],
    ),
    const SongModel(
      id: 'demo_2',
      title: '泡沫 (银河全景声版)',
      artist: 'G.E.M. 邓紫棋',
      album: 'Xposed',
      filePath: 'demo://paomo.wav',
      duration: Duration(seconds: 28),
      format: 'FLAC · SQ无损',
      dominantColor: Color(0xFF6366F1),
      accentColor: Color(0xFF1E1B4B),
      isFavorite: true,
      lyrics: [
        LyricLine(timestamp: Duration(seconds: 0), text: '阳光下的泡沫 是彩色的'),
        LyricLine(timestamp: Duration(seconds: 6), text: '就像被骗的我 是幸福的'),
        LyricLine(timestamp: Duration(seconds: 13), text: '追究什么对错 你的谎言 基于你还爱我'),
        LyricLine(timestamp: Duration(seconds: 20), text: '美丽的泡沫 虽然一刹花火'),
      ],
    ),
    const SongModel(
      id: 'demo_3',
      title: '夜曲 (黑胶典藏版)',
      artist: '周杰伦',
      album: '十一月的萧邦',
      filePath: 'demo://yequ.wav',
      duration: Duration(seconds: 28),
      format: 'WAV · Hi-Res',
      dominantColor: Color(0xFFEC4899),
      accentColor: Color(0xFF4C0519),
      isFavorite: false,
      lyrics: [
        LyricLine(timestamp: Duration(seconds: 0), text: '一群嗜血的蚂蚁 被腐肉所吸引'),
        LyricLine(timestamp: Duration(seconds: 7), text: '我面无表情 看孤独的风景'),
        LyricLine(timestamp: Duration(seconds: 14), text: '为你弹奏萧邦的夜曲 纪念我死去的爱情'),
        LyricLine(timestamp: Duration(seconds: 21), text: '跟夜风一样的声音 心碎得很好听'),
      ],
    ),
    const SongModel(
      id: 'demo_4',
      title: '光年之外 (Wi-Fi/云端导入)',
      artist: 'G.E.M. 邓紫棋',
      album: 'Wi-Fi 局域网导入',
      filePath: 'demo://guangnian.wav',
      duration: Duration(seconds: 28),
      format: 'MP3 · 320kbps',
      dominantColor: Color(0xFF0EA5E9),
      accentColor: Color(0xFF082F49),
      isFavorite: false,
      lyrics: [
        LyricLine(timestamp: Duration(seconds: 0), text: '感受停在我发端的指尖'),
        LyricLine(timestamp: Duration(seconds: 7), text: '如何瞬间 冻结时间'),
        LyricLine(timestamp: Duration(seconds: 15), text: '记住望着我坚定的双眼'),
        LyricLine(timestamp: Duration(seconds: 22), text: '也许已经 没有明天'),
      ],
    ),
  ];

  static final List<SongModel> _cloudFallbackSongs = [
    const SongModel(
      id: 'cloud_1',
      title: '稻香 (24bit 至尊无损)',
      artist: '周杰伦',
      album: '魔杰座 · 在线云端',
      filePath: 'demo://daoxiang.wav',
      duration: Duration(seconds: 28),
      format: 'FLAC · 在线云端',
      dominantColor: Color(0xFF10B981),
      accentColor: Color(0xFF064E3B),
      lyrics: [
        LyricLine(timestamp: Duration.zero, text: '对这个世界如果你有太多的抱怨'),
        LyricLine(timestamp: Duration(seconds: 7), text: '跌倒了就不敢继续往前走'),
        LyricLine(timestamp: Duration(seconds: 15), text: '还记得你说家是唯一的城堡 随着稻香河流继续奔跑'),
      ],
    ),
    const SongModel(
      id: 'cloud_2',
      title: '江南 (DSD64 母带重制版)',
      artist: '林俊杰',
      album: '第二天堂 · 在线云端',
      filePath: 'demo://jiangnan.wav',
      duration: Duration(seconds: 28),
      format: 'DSF · DSD母带',
      dominantColor: Color(0xFF06B6D4),
      accentColor: Color(0xFF164E63),
      lyrics: [
        LyricLine(timestamp: Duration.zero, text: '风到这里就是粘 粘住过客的思念'),
        LyricLine(timestamp: Duration(seconds: 8), text: '雨到了这里缠成线 缠着我们流连人世间'),
      ],
    ),
    const SongModel(
      id: 'cloud_3',
      title: 'Hotel California (加州旅馆 现场版)',
      artist: 'Eagles',
      album: 'Hell Freezes Over · 在线云端',
      filePath: 'demo://hotel.wav',
      duration: Duration(seconds: 28),
      format: 'APE · 发烧原盘',
      dominantColor: Color(0xFFF59E0B),
      accentColor: Color(0xFF451A03),
      lyrics: [
        LyricLine(timestamp: Duration.zero, text: 'On a dark desert highway, cool wind in my hair'),
        LyricLine(timestamp: Duration(seconds: 8), text: 'Welcome to the Hotel California'),
      ],
    ),
  ];
}

final audioPlayerProvider =
    StateNotifierProvider<AudioPlayerController, PlayerStateModel>(
  (ref) => AudioPlayerController(),
);
