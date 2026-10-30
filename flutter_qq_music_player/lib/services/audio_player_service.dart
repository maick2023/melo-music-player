import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/eq_preset_model.dart';
import '../models/song_model.dart';
import 'car_auto_play_service.dart';
import 'local_scanner_service.dart';
import 'melo_audio_handler.dart';
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
        return s.title.toLowerCase().includesCaseInsensitive(q) ||
            s.artist.toLowerCase().includesCaseInsensitive(q) ||
            s.album.toLowerCase().includesCaseInsensitive(q);
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

extension _StrContainsExt on String {
  bool includesCaseInsensitive(String other) => contains(other);
}

/// 全局音频播放、进度记忆、后台常驻与车载按键控制器
class AudioPlayerController extends StateNotifier<PlayerStateModel> {
  static const MethodChannel _retainChannel =
      MethodChannel('com.melomusic.player/app_retain');

  final AudioPlayer _audioPlayer = AudioPlayer();
  final LocalScannerService _scannerService = LocalScannerService();
  final OnlineSearchService _onlineSearchService = OnlineSearchService();
  CarAutoPlayService? _carService;
  MeloAudioHandler? _audioHandler;
  Timer? _sleepTimer;

  Set<String> _deletedSongIds = {};
  Set<String> _favoriteSongIds = {};
  String? _rememberedSongId;
  Duration _rememberedPosition = Duration.zero;
  int _lastSavedSecond = -1;
  bool _hasPreloadedInitialSong = false;

  AudioPlayerController()
      : super(
          PlayerStateModel(
            allSongs: const [],
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
    _bindHardwareAndCarMediaKeys();
    _initMemoryCarAndStartupScan();
  }

  /// 初始化：1. 恢复上次播放歌曲与毫秒级进度记忆 -> 2. 启动后台常驻 MediaSession 服务 -> 3. 扫描本地音乐并保持记忆位置 -> 4. 启动车载点火监听
  Future<void> _initMemoryCarAndStartupScan() async {
    final prefs = await SharedPreferences.getInstance();
    _deletedSongIds = (prefs.getStringList('deleted_song_ids') ?? []).toSet();
    _favoriteSongIds =
        (prefs.getStringList('favorite_song_ids_v1') ?? []).toSet();
    _rememberedSongId = prefs.getString('last_played_song_id');
    final savedPosMs = prefs.getInt('last_played_position_ms') ?? 0;
    _rememberedPosition = Duration(milliseconds: max(0, savedPosMs));

    // 恢复视觉样式、循环模式、倍速、音效预设
    final styleIdx = prefs.getInt('last_visual_style_idx') ?? 0;
    final loopIdx = prefs.getInt('last_loop_mode_idx') ?? 0;
    final savedSpeed = prefs.getDouble('last_playback_speed') ?? 1.0;
    final savedCarAuto = prefs.getBool('car_auto_play') ?? true;
    final savedPresetId = prefs.getString('last_eq_preset_id') ?? 'pop';

    final restoredStyle = PlayerVisualStyle.values[
        styleIdx.clamp(0, PlayerVisualStyle.values.length - 1)];
    final restoredLoop = LoopPlayMode
        .values[loopIdx.clamp(0, LoopPlayMode.values.length - 1)];
    final restoredPreset = EqPresetModel.builtinPresets.firstWhere(
      (p) => p.id == savedPresetId,
      orElse: () => EqPresetModel.builtinPresets[1],
    );

    // 恢复已保存的在线搜索歌曲与上次正在听的歌曲快照
    final List<SongModel> restoredSongs = [];
    final savedCustomList =
        prefs.getStringList('saved_custom_songs_v1') ?? const [];
    for (final itemStr in savedCustomList) {
      try {
        final map = jsonDecode(itemStr) as Map<String, dynamic>;
        final s = SongModel.fromJson(map);
        if (!_deletedSongIds.contains(s.id)) {
          restoredSongs.add(
            s.copyWith(isFavorite: _favoriteSongIds.contains(s.id) || s.isFavorite),
          );
        }
      } catch (_) {}
    }

    final lastSongJsonStr = prefs.getString('last_played_song_json');
    if (lastSongJsonStr != null && lastSongJsonStr.isNotEmpty) {
      try {
        final map = jsonDecode(lastSongJsonStr) as Map<String, dynamic>;
        final lastSong = SongModel.fromJson(map);
        if (!_deletedSongIds.contains(lastSong.id) &&
            !restoredSongs.any((s) => s.id == lastSong.id)) {
          restoredSongs.insert(
            0,
            lastSong.copyWith(
              isFavorite:
                  _favoriteSongIds.contains(lastSong.id) || lastSong.isFavorite,
            ),
          );
        }
      } catch (_) {}
    }

    int initialIdx = 0;
    if (_rememberedSongId != null && restoredSongs.isNotEmpty) {
      final found = restoredSongs.indexWhere((s) => s.id == _rememberedSongId);
      if (found != -1) initialIdx = found;
    }

    final initialSong =
        restoredSongs.isNotEmpty ? restoredSongs[initialIdx] : null;

    state = state.copyWith(
      allSongs: restoredSongs,
      currentQueue: restoredSongs,
      currentIndex: initialIdx,
      position: _rememberedPosition,
      duration: initialSong?.duration ?? const Duration(minutes: 3, seconds: 30),
      visualStyle: restoredStyle,
      loopMode: restoredLoop,
      playbackSpeed: savedSpeed,
      carAutoPlayEnabled: savedCarAuto,
      activeEqPreset: restoredPreset,
      customEqGains: List<double>.from(restoredPreset.gains),
    );

    // 启动系统级 MediaSession 与通知栏前台保活服务（支持车载方向盘上下曲与锁屏保活）
    await _initBackgroundAudioService();

    // 扫描本地音乐并与已保存歌曲合并（严格保留上次记忆的歌曲下标与进度，绝不重置回第 1 首！）
    await scanLocalMusic(preserveCurrentSelection: true);

    // 预加载上次记忆的歌曲并定位到上次离开时的秒数
    await _preloadRememberedSongAtPosition();

    // 启动车载蓝牙连接检测与点火自动续播服务
    _carService = CarAutoPlayService(
      onCarConnectedTriggerPlay: (_) {
        if (state.carAutoPlayEnabled && state.currentQueue.isNotEmpty) {
          resumeOrPlayRememberedSong();
        }
      },
      onCarDisconnectedTriggerPause: () {
        if (state.isPlaying) {
          pause();
        }
      },
    );
    await _carService?.init();
    // 主动申请后台常驻与蓝牙连接权限，防止锁屏后被系统清理
    CarAutoPlayService.requestBackgroundKeepAlivePermissions();
  }

  /// 初始化系统通知栏与车载蓝牙 MediaSession
  Future<void> _initBackgroundAudioService() async {
    try {
      _audioHandler = await AudioService.init(
        builder: () => MeloAudioHandler(
          onPlayCmd: () => resumeOrPlayRememberedSong(),
          onPauseCmd: () => pause(),
          onNextCmd: () => nextSong(),
          onPreviousCmd: () => previousSong(),
          onSeekCmd: (pos) => seekTo(pos),
          onTogglePlayPauseCmd: () => togglePlayPause(),
        ),
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'com.melomusic.player.channel.audio',
          androidNotificationChannelName: '悦听车载与后台音乐服务',
          androidNotificationOngoing: false,
          androidStopForegroundOnPause: false,
        ),
      );
      _syncMediaNotification();
    } catch (_) {
      // 如果宿主未启用 AudioServiceActivity 则安全降级，不影响播放器正常使用
    }
  }

  void _syncMediaNotification() {
    _audioHandler?.syncMediaState(
      song: state.currentSong,
      isPlaying: state.isPlaying,
      position: state.position,
      duration: state.duration,
      speed: state.playbackSpeed,
    );
  }

  /// 绑定车载方向盘物理按键 / 蓝牙 AVRCP 按键 / 线控按键监听
  void _bindHardwareAndCarMediaKeys() {
    HardwareKeyboard.instance.addHandler(_onHardwareKeyEvent);
    _retainChannel.setMethodCallHandler((call) async {
      if (call.method == 'onMediaKey') {
        final action = call.arguments as String? ?? '';
        if (action == 'next') {
          await nextSong();
        } else if (action == 'prev') {
          await previousSong();
        } else if (action == 'play') {
          await resumeOrPlayRememberedSong();
        } else if (action == 'pause') {
          await pause();
        } else if (action == 'toggle') {
          await togglePlayPause();
        }
      }
      return null;
    });
  }

  bool _onHardwareKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.mediaTrackNext ||
        key == LogicalKeyboardKey.mediaFastForward) {
      nextSong();
      return true;
    }
    if (key == LogicalKeyboardKey.mediaTrackPrevious ||
        key == LogicalKeyboardKey.mediaRewind) {
      previousSong();
      return true;
    }
    if (key == LogicalKeyboardKey.mediaPlayPause ||
        key == LogicalKeyboardKey.headsetHook) {
      togglePlayPause();
      return true;
    }
    if (key == LogicalKeyboardKey.mediaPlay) {
      resumeOrPlayRememberedSong();
      return true;
    }
    if (key == LogicalKeyboardKey.mediaPause ||
        key == LogicalKeyboardKey.mediaStop) {
      pause();
      return true;
    }
    return false;
  }

  void _bindAudioStreams() {
    _audioPlayer.positionStream.listen((pos) {
      state = state.copyWith(position: pos);
      // 每隔 2 秒自动持久化保存一次当前播放进度，确保随时退出或断电都不丢失进度
      final sec = pos.inSeconds;
      if (state.isPlaying && sec > 0 && (sec - _lastSavedSecond).abs() >= 2) {
        _lastSavedSecond = sec;
        _savePlaybackMemory(positionOverride: pos);
        _syncMediaNotification();
      }
    });

    _audioPlayer.durationStream.listen((dur) {
      if (dur != null && dur.inSeconds > 0) {
        state = state.copyWith(duration: dur);
        _syncMediaNotification();
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

  /// 保存当前播放的歌曲 ID、歌曲完整 JSON 快照与毫秒进度到手机本地存储
  Future<void> _savePlaybackMemory({
    SongModel? songOverride,
    Duration? positionOverride,
  }) async {
    final song = songOverride ?? state.currentSong;
    if (song == null) return;
    final pos = positionOverride ?? state.position;
    _rememberedSongId = song.id;
    _rememberedPosition = pos;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_played_song_id', song.id);
      await prefs.setString('last_played_song_json', jsonEncode(song.toJson()));
      await prefs.setInt('last_played_position_ms', pos.inMilliseconds);
    } catch (_) {}
  }

  /// 保存用户搜索添加的在线歌曲与导入歌曲列表，防止下次打开丢失
  Future<void> _saveCustomSongsList(List<SongModel> allSongs) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final customSongs = allSongs
          .where((s) => !s.id.startsWith('media_'))
          .take(100)
          .map((s) => jsonEncode(s.toJson()))
          .toList();
      await prefs.setStringList('saved_custom_songs_v1', customSongs);
    } catch (_) {}
  }

  /// App 启动时预加载上次播放的歌曲并跳转到上次记忆的进度（不重置回第 1 首）
  Future<void> _preloadRememberedSongAtPosition() async {
    if (_hasPreloadedInitialSong || state.currentQueue.isEmpty) return;
    final idx = state.currentIndex.clamp(0, state.currentQueue.length - 1);
    final song = state.currentQueue[idx];
    _hasPreloadedInitialSong = true;

    if (song.lyrics.length <= 3) {
      _autoMatchCloudLyrics(idx, song);
    }

    try {
      if (song.filePath.startsWith('http://') ||
          song.filePath.startsWith('https://')) {
        await _audioPlayer.setUrl(song.filePath);
      } else {
        await _audioPlayer.setFilePath(song.filePath);
      }
      await _audioPlayer.setSpeed(state.playbackSpeed);
      if (_rememberedPosition.inSeconds > 0 &&
          _rememberedPosition < song.duration) {
        await _audioPlayer.seek(_rememberedPosition);
        state = state.copyWith(position: _rememberedPosition);
      }
      _syncMediaNotification();
    } catch (_) {}
  }

  /// 车载点火或按播放键时：从上次记忆的歌曲和进度直接无缝续播
  Future<void> resumeOrPlayRememberedSong() async {
    if (state.currentQueue.isEmpty) return;
    if (state.isPlaying && _audioPlayer.playing) return;

    final idx = state.currentIndex.clamp(0, state.currentQueue.length - 1);
    if (_audioPlayer.processingState == ProcessingState.idle ||
        _audioPlayer.processingState == ProcessingState.completed) {
      await playSongAt(
        idx,
        startPosition: state.position.inSeconds > 0 ? state.position : _rememberedPosition,
      );
    } else {
      state = state.copyWith(isPlaying: true);
      _syncMediaNotification();
      try {
        await _audioPlayer.play();
      } catch (_) {
        await playSongAt(idx, startPosition: state.position);
      }
    }
  }

  /// 扫描手机本地音乐库（自动过滤已删除歌曲，并严格保持上次记忆的歌曲位置，绝不重置回第 1 首）
  Future<int> scanLocalMusic({bool preserveCurrentSelection = true}) async {
    final currentSelectedId = state.currentSong?.id ?? _rememberedSongId;
    final currentPos = state.position.inSeconds > 0 ? state.position : _rememberedPosition;

    final scanned = await _scannerService.autoScanAllDeviceMusic();
    final filteredScanned = scanned
        .where((s) => !_deletedSongIds.contains(s.id))
        .map(
          (s) => s.copyWith(
            isFavorite: _favoriteSongIds.contains(s.id) || s.isFavorite,
          ),
        )
        .toList();

    if (filteredScanned.isNotEmpty || state.allSongs.isNotEmpty) {
      final existingCustom = state.allSongs
          .where((s) => !_deletedSongIds.contains(s.id))
          .toList();
      final existingIds = existingCustom.map((e) => e.id).toSet();
      final newFromScan =
          filteredScanned.where((s) => !existingIds.contains(s.id)).toList();

      // 将用户已有的在线/记忆歌曲与本地扫描歌曲合并
      final merged = [...existingCustom, ...newFromScan];

      int targetIndex = 0;
      if (preserveCurrentSelection && currentSelectedId != null) {
        final foundIdx = merged.indexWhere((s) => s.id == currentSelectedId);
        if (foundIdx != -1) {
          targetIndex = foundIdx;
        }
      }

      state = state.copyWith(
        allSongs: merged,
        currentQueue: merged,
        currentIndex: targetIndex,
        position: currentPos,
      );
      _syncMediaNotification();
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
      final kept =
          state.allSongs.where((s) => !existingIds.contains(s.id)).toList();
      final merged = [...imported, ...kept];
      state = state.copyWith(
        allSongs: merged,
        currentQueue: merged,
        currentIndex: 0,
      );
      await _saveCustomSongsList(merged);
      await playSongAt(0);
    }
    return imported.length;
  }

  /// 删除指定歌曲
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
    await _saveCustomSongsList(updatedAll);
    await _savePlaybackMemory(
      positionOverride: wasCurrent ? Duration.zero : state.position,
    );
    _syncMediaNotification();
  }

  /// 联网搜索歌曲
  Future<List<SongModel>> searchOnlineSongs(String keyword) async {
    final kw = keyword.trim();
    if (kw.isEmpty) return [];
    return _onlineSearchService.searchOnlineSongs(kw);
  }

  Future<void> addAndPlayOnlineSong(SongModel song) => addAndPlaySong(song);

  /// 将联网搜索到的歌曲加入播放队列顶部、持久化保存并立即播放
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
    await _saveCustomSongsList(updated);
    await playSongAt(0);
  }

  Future<void> playSongById(String songId) async {
    final idx = state.currentQueue.indexWhere((s) => s.id == songId);
    if (idx != -1) {
      await playSongAt(idx);
    }
  }

  /// 播放指定下标歌曲（支持传入初始续播位置 startPosition，并立即写入记忆）
  Future<void> playSongAt(int index, {Duration? startPosition}) async {
    if (index < 0 || index >= state.currentQueue.length) return;
    final song = state.currentQueue[index];
    final targetPos = startPosition ?? Duration.zero;

    state = state.copyWith(
      currentIndex: index,
      position: targetPos,
      duration: song.duration,
      isPlaying: true,
    );
    await _savePlaybackMemory(songOverride: song, positionOverride: targetPos);
    _syncMediaNotification();

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
      if (targetPos.inSeconds > 0) {
        await _audioPlayer.seek(targetPos);
      }
      await _audioPlayer.play();
      _syncMediaNotification();
    } catch (_) {
      try {
        final backups = await _onlineSearchService
            .searchOnlineSongs('${song.title} ${song.artist}');
        final itunesMatch =
            backups.where((b) => b.id.startsWith('itunes_')).toList();
        if (itunesMatch.isNotEmpty) {
          await _audioPlayer.setUrl(itunesMatch.first.filePath);
          await _audioPlayer.setSpeed(state.playbackSpeed);
          if (targetPos.inSeconds > 0) {
            await _audioPlayer.seek(targetPos);
          }
          await _audioPlayer.play();
          _syncMediaNotification();
          return;
        }
      } catch (_) {}
      state = state.copyWith(isPlaying: false);
      _syncMediaNotification();
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
      await _saveCustomSongsList(newAll);
      await _savePlaybackMemory(songOverride: updatedSong);
    }
  }

  Future<void> togglePlayPause() async {
    if (state.currentQueue.isEmpty) return;
    if (!state.isPlaying) {
      await resumeOrPlayRememberedSong();
    } else {
      await pause();
    }
  }

  Future<void> pause() async {
    state = state.copyWith(isPlaying: false);
    await _savePlaybackMemory();
    _syncMediaNotification();
    try {
      await _audioPlayer.pause();
    } catch (_) {}
  }

  /// 保存当前所有状态记忆（供 App 切到后台时调用）
  Future<void> saveMemoryOnBackground() async {
    await _savePlaybackMemory();
    await _saveCustomSongsList(state.allSongs);
  }

  /// 将应用退到手机后台待命（不结束进程，保持蓝牙点火监听与方向盘按键响应）
  Future<void> moveAppToBackground() async {
    await saveMemoryOnBackground();
    _syncMediaNotification();
    if (Platform.isAndroid) {
      try {
        await _retainChannel.invokeMethod('moveTaskToBack');
        return;
      } catch (_) {}
      await SystemNavigator.pop();
    }
  }

  /// 彻底停止播放并释放音频焦点
  Future<void> stopPlaybackCompletely() async {
    _sleepTimer?.cancel();
    await _savePlaybackMemory();
    state = state.copyWith(isPlaying: false);
    _syncMediaNotification();
    try {
      await _audioPlayer.stop();
    } catch (_) {}
  }

  /// 停止音乐并彻底结束 App 进程（仅当用户明确点击“彻底关闭进程”时调用）
  Future<void> stopAndExitApp() async {
    await stopPlaybackCompletely();
    try {
      await _audioHandler?.stop();
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
    await _savePlaybackMemory(positionOverride: target);
    _syncMediaNotification();
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

  void switchVisualStyle(PlayerVisualStyle style) => setVisualStyle(style);

  Future<void> setVisualStyle(PlayerVisualStyle style) async {
    state = state.copyWith(visualStyle: style, showLyricsInline: false);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('last_visual_style_idx', style.index);
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

  Future<void> cycleLoopMode() async {
    final modes = LoopPlayMode.values;
    final nextMode = modes[(state.loopMode.index + 1) % modes.length];
    state = state.copyWith(loopMode: nextMode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('last_loop_mode_idx', nextMode.index);
  }

  Future<void> toggleFavorite(String songId) async {
    if (_favoriteSongIds.contains(songId)) {
      _favoriteSongIds.remove(songId);
    } else {
      _favoriteSongIds.add(songId);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('favorite_song_ids_v1', _favoriteSongIds.toList());

    final updatedAll = state.allSongs.map((s) {
      return s.id == songId
          ? s.copyWith(isFavorite: _favoriteSongIds.contains(songId))
          : s;
    }).toList();
    final updatedQueue = state.currentQueue.map((s) {
      return s.id == songId
          ? s.copyWith(isFavorite: _favoriteSongIds.contains(songId))
          : s;
    }).toList();
    state = state.copyWith(allSongs: updatedAll, currentQueue: updatedQueue);
    await _saveCustomSongsList(updatedAll);
  }

  Future<void> setPlaybackSpeed(double speed) async {
    state = state.copyWith(playbackSpeed: speed);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('last_playback_speed', speed);
    try {
      await _audioPlayer.setSpeed(speed);
    } catch (_) {}
    _syncMediaNotification();
  }

  Future<void> applyEqPreset(EqPresetModel preset) async {
    state = state.copyWith(
      activeEqPreset: preset,
      customEqGains: List<double>.from(preset.gains),
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_eq_preset_id', preset.id);
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
    HardwareKeyboard.instance.removeHandler(_onHardwareKeyEvent);
    _sleepTimer?.cancel();
    _carService?.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }
}

final audioPlayerProvider =
    StateNotifierProvider<AudioPlayerController, PlayerStateModel>(
  (ref) => AudioPlayerController(),
);
