import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/eq_preset_model.dart';
import '../models/song_model.dart';
import 'car_auto_play_service.dart';
import 'local_scanner_service.dart';
import 'online_search_service.dart';

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

  List<SongModel> get filteredSongs {
    return allSongs.where((s) {
      if (activePlaylistFilter == 'fav' && !s.isFavorite) return false;
      if (activePlaylistFilter == 'wifi' &&
          !s.album.contains('Wi-Fi') &&
          !s.album.contains('导入') &&
          !s.album.contains('在线') &&
          !s.folderName.contains('在线')) {
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

/// 全局音频播放与曲库管理控制器（无内置假歌、支持单曲删除、支持退出即停播）
class AudioPlayerController extends StateNotifier<PlayerStateModel> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  final LocalScannerService _scannerService = LocalScannerService();
  final OnlineSearchService _onlineSearchService = OnlineSearchService();
  CarAutoPlayService? _carService;
  Timer? _sleepTimer;
  Set<String> _deletedSongIds = {};

  AudioPlayerController()
      : super(
          PlayerStateModel(
            allSongs: const [], // 不再塞入任何假曲调内置歌曲，完全展示用户扫描/导入/搜索的真歌
            currentQueue: const [],
            currentIndex: 0,
            isPlaying: false,
            position: Duration.zero,
            duration: const Duration(minutes: 3, seconds: 30),
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
    final prefs = await SharedPreferences.getInstance();
    _deletedSongIds = (prefs.getStringList('deleted_song_ids') ?? []).toSet();

    _carService = CarAutoPlayService(
      onCarConnectedTriggerPlay: (_) {
        if (state.carAutoPlayEnabled &&
            !state.isPlaying &&
            state.currentQueue.isNotEmpty) {
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
    // 启动后自动扫描手机本地真实音频
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

  /// 扫描手机本地音乐库（自动过滤掉用户已删除的歌曲）
  Future<int> scanLocalMusic() async {
    final scanned = await _scannerService.autoScanAllDeviceMusic();
    final filteredScanned =
        scanned.where((s) => !_deletedSongIds.contains(s.id)).toList();
    if (filteredScanned.isNotEmpty) {
      final existingIds = filteredScanned.map((e) => e.id).toSet();
      final kept = state.allSongs
          .where(
            (s) =>
                !existingIds.contains(s.id) && !_deletedSongIds.contains(s.id),
          )
          .toList();
      final merged = [...filteredScanned, ...kept];
      state = state.copyWith(
        allSongs: merged,
        currentQueue: merged,
        currentIndex: 0,
      );
    }
    return filteredScanned.length;
  }

  /// 从文件选择器手动导入本地音频
  Future<int> importAudioFiles() async {
    final imported = await _scannerService.pickAndImportAudioFiles();
    if (imported.isNotEmpty) {
      for (final s in imported) {
        _deletedSongIds.remove(s.id);
      }
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

  /// 删除指定歌曲（若正在播放该歌曲则先停止或切歌，并记录已删除 ID 防止重启恢复）
  Future<void> deleteSong(String songId) async {
    _deletedSongIds.add(songId);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('deleted_song_ids', _deletedSongIds.toList());

    final wasCurrent = state.currentSong?.id == songId;
    if (wasCurrent) {
      await _audioPlayer.stop();
    }

    final updatedAll = state.allSongs.where((s) => s.id != songId).toList();
    final updatedQueue =
        state.currentQueue.where((s) => s.id != songId).toList();

    int nextIndex = state.currentIndex;
    if (nextIndex >= updatedQueue.length) {
      nextIndex = max(0, updatedQueue.length - 1);
    }

    state = state.copyWith(
      allSongs: updatedAll,
      currentQueue: updatedQueue,
      currentIndex: nextIndex,
      isPlaying: wasCurrent ? false : state.isPlaying,
      position: wasCurrent ? Duration.zero : state.position,
    );
  }

  /// 联网搜索歌曲（仅在用户输入关键字时调用真实网络接口，绝不返回假曲调内置歌曲）
  Future<List<SongModel>> searchOnlineSongs(String keyword) async {
    final kw = keyword.trim();
    if (kw.isEmpty) return [];
    return _onlineSearchService.searchOnlineSongs(kw);
  }

  /// 将联网搜索到的歌曲加入播放队列顶部并立即播放真人原唱
  Future<void> addAndPlaySong(SongModel song) async {
    _deletedSongIds.remove(song.id);
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

  Future<void> playSongById(String songId) async {
    final idx = state.currentQueue.indexWhere((s) => s.id == songId);
    if (idx != -1) {
      await playSongAt(idx);
    }
  }

  /// 播放指定下标歌曲（仅播放真实本地音频文件或真实 HTTPS 在线演唱音频流，并自动拉取云端同步歌词）
  Future<void> playSongAt(int index) async {
    if (index < 0 || index >= state.currentQueue.length) return;
    final song = state.currentQueue[index];
    state = state.copyWith(
      currentIndex: index,
      position: Duration.zero,
      duration: song.duration,
      isPlaying: true,
    );

    if (song.lyrics.length <= 3) {
      _autoMatchCloudLyrics(index, song);
    }

    try {
      if (song.filePath.startsWith('http://') ||
          song.filePath.startsWith('https://')) {
        await _audioPlayer.setUrl(song.filePath);
      } else {
        await _audioPlayer.setFilePath(song.filePath);
      }
      await _audioPlayer.setSpeed(state.playbackSpeed);
      await _audioPlayer.play();
    } catch (_) {
      // 如果某条网易云外链因为版权重定向失败，自动用【歌名+歌手】从 iTunes 通道获取真人原唱流替换播放
      try {
        final backups = await _onlineSearchService
            .searchOnlineSongs('${song.title} ${song.artist}');
        final itunesMatch = backups.where((b) => b.id.startsWith('itunes_')).toList();
        if (itunesMatch.isNotEmpty) {
          await _audioPlayer.setUrl(itunesMatch.first.filePath);
          await _audioPlayer.setSpeed(state.playbackSpeed);
          await _audioPlayer.play();
          return;
        }
      } catch (_) {}
      state = state.copyWith(isPlaying: false);
    }
  }

  Future<void> _autoMatchCloudLyrics(int queueIndex, SongModel song) async {
    final fetched = await _onlineSearchService.fetchCloudLyricsForSong(song);
    if (fetched.length > 3) {
      final updatedSong = song.copyWith(lyrics: fetched);
      final newQueue = List<SongModel>.from(state.currentQueue);
      if (queueIndex >= 0 && queueIndex < newQueue.length) {
        newQueue[queueIndex] = updatedSong;
      }
      final newAll = state.allSongs
          .map((s) => s.id == song.id ? updatedSong : s)
          .toList();
      state = state.copyWith(allSongs: newAll, currentQueue: newQueue);
    }
  }

  Future<void> togglePlayPause() async {
    if (state.currentQueue.isEmpty) return;
    if (!state.isPlaying) {
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

  /// 彻底停止播放并释放音频焦点（用于退出播放器或关闭应用时立即停播）
  Future<void> stopPlaybackCompletely() async {
    _sleepTimer?.cancel();
    state = state.copyWith(isPlaying: false, position: Duration.zero);
    try {
      await _audioPlayer.stop();
    } catch (_) {}
  }

  /// 停止音乐并彻底退出 App 进程
  Future<void> stopAndExitApp() async {
    await stopPlaybackCompletely();
    try {
      await _audioPlayer.dispose();
    } catch (_) {}
    if (Platform.isAndroid) {
      SystemNavigator.pop();
      exit(0);
    } else {
      exit(0);
    }
  }

  Future<void> seekTo(Duration target) async {
    state = state.copyWith(position: target);
    try {
      await _audioPlayer.seek(target);
    } catch (_) {}
  }

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

  void cycleLoopMode() {
    final modes = LoopPlayMode.values;
    final nextMode = modes[(state.loopMode.index + 1) % modes.length];
    state = state.copyWith(loopMode: nextMode);
  }

  void toggleFavorite(String songId) {
    final updatedAll = state.allSongs.map((s) {
      return s.id == songId ? s.copyWith(isFavorite: !s.isFavorite) : s;
    }).toList();
    final updatedQueue = state.currentQueue.map((s) {
      return s.id == songId ? s.copyWith(isFavorite: !s.isFavorite) : s;
    }).toList();
    state = state.copyWith(allSongs: updatedAll, currentQueue: updatedQueue);
  }

  Future<void> setPlaybackSpeed(double speed) async {
    state = state.copyWith(playbackSpeed: speed);
    try {
      await _audioPlayer.setSpeed(speed);
    } catch (_) {}
  }

  void applyEqPreset(EqPresetModel preset) {
    state = state.copyWith(
      activeEqPreset: preset,
      customEqGains: List<double>.from(preset.gains),
    );
  }

  void updateEqBand(int bandIndex, double gainDb) {
    final updated = List<double>.from(state.customEqGains);
    updated[bandIndex] = gainDb;
    state = state.copyWith(customEqGains: updated);
  }

  void toggleSurround3d(bool enabled) {
    state = state.copyWith(surround3dEnabled: enabled);
  }

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
    _audioPlayer.stop();
    _audioPlayer.dispose();
    super.dispose();
  }
}

final audioPlayerProvider =
    StateNotifierProvider<AudioPlayerController, PlayerStateModel>(
  (ref) => AudioPlayerController(),
);
