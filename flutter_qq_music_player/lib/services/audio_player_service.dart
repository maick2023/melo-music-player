import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import '../models/eq_preset_model.dart';
import '../models/song_model.dart';
import 'local_scanner_service.dart';

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
  final String activePlaylistFilter; // 'all', 'favorites', 'wifi'

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
  });

  SongModel? get currentSong =>
      (currentIndex >= 0 && currentIndex < currentQueue.length)
          ? currentQueue[currentIndex]
          : null;

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
    );
  }
}

/// 全局音频播放与附加功能控制器
class AudioPlayerController extends StateNotifier<PlayerStateModel> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  final LocalScannerService _scannerService = LocalScannerService();
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
  }

  void _bindAudioStreams() {
    _audioPlayer.positionStream.listen((pos) {
      state = state.copyWith(position: pos);
    });
    _audioPlayer.durationStream.listen((dur) {
      if (dur != null) {
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

  /// 扫描手机本地音乐库
  Future<int> scanLocalMusic() async {
    final scanned = await _scannerService.scanDeviceMusic();
    if (scanned.isNotEmpty) {
      state = state.copyWith(
        allSongs: scanned,
        currentQueue: scanned,
        currentIndex: 0,
      );
    }
    return scanned.length;
  }

  /// 从文件选择器手动导入本地音频（适配 iOS 与自定义文件夹）
  Future<int> importAudioFiles() async {
    final imported = await _scannerService.pickAndImportAudioFiles();
    if (imported.isNotEmpty) {
      final merged = [...imported, ...state.allSongs];
      state = state.copyWith(allSongs: merged, currentQueue: merged);
    }
    return imported.length;
  }

  /// 播放指定歌曲
  Future<void> playSongAt(int index) async {
    if (index < 0 || index >= state.currentQueue.length) return;
    final song = state.currentQueue[index];
    state = state.copyWith(
      currentIndex: index,
      position: Duration.zero,
      duration: song.duration,
      isPlaying: true,
    );
    if (!song.filePath.startsWith('demo://')) {
      try {
        await _audioPlayer.setFilePath(song.filePath);
        await _audioPlayer.setSpeed(state.playbackSpeed);
        await _audioPlayer.play();
      } catch (_) {}
    }
  }

  Future<void> togglePlayPause() async {
    final nextPlaying = !state.isPlaying;
    state = state.copyWith(isPlaying: nextPlaying);
    try {
      if (nextPlaying) {
        await _audioPlayer.play();
      } else {
        await _audioPlayer.pause();
      }
    } catch (_) {}
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
      await seekTo(Duration.zero);
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
    state = state.copyWith(visualStyle: style);
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
    _audioPlayer.dispose();
    super.dispose();
  }

  static final List<SongModel> _defaultDemoSongs = [
    SongModel(
      id: 'demo_1',
      title: '晴天 (无损臻品母带)',
      artist: '周杰伦',
      album: '叶惠美',
      filePath: 'demo://qingtian.flac',
      duration: const Duration(minutes: 4, seconds: 29),
      format: 'FLAC · 24bit/96kHz',
      dominantColor: const Color(0xFF00C471),
      accentColor: const Color(0xFF073B28),
      isFavorite: true,
      lyrics: const [
        LyricLine(timestamp: Duration(seconds: 0), text: '故事的小黄花 从出生那年就飘着'),
        LyricLine(timestamp: Duration(seconds: 12), text: '童年的荡秋千 随记忆一直晃到现在'),
        LyricLine(timestamp: Duration(seconds: 25), text: 'Re So So Si Do Si La So La Si Si Si Si La Si La So'),
        LyricLine(timestamp: Duration(seconds: 38), text: '吹着前奏望着天空 我想起花瓣试着掉落'),
        LyricLine(timestamp: Duration(seconds: 50), text: '为你翘课的那一天 花落的那一天'),
        LyricLine(timestamp: Duration(seconds: 64), text: '教室的那一间 我怎么看不见'),
        LyricLine(timestamp: Duration(seconds: 76), text: '消失的下雨天 我好想再淋一遍'),
      ],
    ),
    SongModel(
      id: 'demo_2',
      title: '泡沫 (银河全景声版)',
      artist: 'G.E.M. 邓紫棋',
      album: 'Xposed',
      filePath: 'demo://paomo.flac',
      duration: const Duration(minutes: 4, seconds: 18),
      format: 'FLAC · SQ无损',
      dominantColor: const Color(0xFF6366F1),
      accentColor: const Color(0xFF1E1B4B),
      isFavorite: true,
      lyrics: const [
        LyricLine(timestamp: Duration(seconds: 0), text: '阳光下的泡沫 是彩色的'),
        LyricLine(timestamp: Duration(seconds: 14), text: '就像被骗的我 是幸福的'),
        LyricLine(timestamp: Duration(seconds: 28), text: '追究什么对错 你的谎言 基于你还爱我'),
        LyricLine(timestamp: Duration(seconds: 44), text: '美丽的泡沫 虽然一刹花火'),
      ],
    ),
    SongModel(
      id: 'demo_3',
      title: '匆匆那年 (Live 典藏版)',
      artist: '王菲',
      album: '匆匆那年 电影原声带',
      filePath: 'demo://congcong.wav',
      duration: const Duration(minutes: 4, seconds: 1),
      format: 'WAV · Hi-Res',
      dominantColor: const Color(0xFFEC4899),
      accentColor: const Color(0xFF4C0519),
      lyrics: const [
        LyricLine(timestamp: Duration(seconds: 0), text: '匆匆那年我们 究竟说了几遍 再见之后再拖延'),
        LyricLine(timestamp: Duration(seconds: 16), text: '可惜谁有没有 爱过不是一场 七情上面的雄辩'),
      ],
    ),
  ];
}

final audioPlayerProvider =
    StateNotifierProvider<AudioPlayerController, PlayerStateModel>(
  (ref) => AudioPlayerController(),
);
