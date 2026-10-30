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

/// 全局音频播放、进度记忆、自定义排序编辑、后台常驻与车载按键控制器
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
  List<String> _savedOrderIds = [];
  Map<String, Map<String, String>> _savedSongEdits = {};
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

  /// 初始化：1. 恢复上次播放歌曲、进度与自定义排序 -> 2. 启动后台常驻服务 -> 3. 扫描本地音乐并保持记忆位置 -> 4. 启动车载点火监听
  Future<void> _initMemoryCarAndStartupScan() async {
    final prefs = await SharedPreferences.getInstance();
    _deletedSongIds = (prefs.getStringList('deleted_song_ids') ?? []).toSet();
    _favoriteSongIds =
        (prefs.getStringList('favorite_song_ids_v1') ?? []).toSet();
    _savedOrderIds = prefs.getStringList('saved_song_order_ids_v1') ?? [];

    final rawEdits = prefs.getString('saved_song_edits_v1');
    if (rawEdits != null && rawEdits.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawEdits) as Map<String, dynamic>;
        _savedSongEdits = decoded.map((k, v) {
          final m = (v as Map<String, dynamic>);
          return MapEntry(k, {
            'title': (m['title'] as String?) ?? '',
            'artist': (m['artist'] as String?) ?? '',
          });
        });
      } catch (_) {}
    }

    _rememberedSongId = prefs.getString('last_played_song_id');
    final savedPosMs = prefs.getInt('last_played_position_ms') ?? 0;
    _rememberedPosition = Duration(milliseconds: max(0, savedPosMs));

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

    final List<SongModel> restoredSongs = [];
    final savedCustomList =
        prefs.getStringList('saved_custom_songs_v1') ?? const [];
    for (final itemStr in savedCustomList) {
      try {
        final map = jsonDecode(itemStr) as Map<String, dynamic>;
        final s = SongModel.fromJson(map);
        if (!_deletedSongIds.contains(s.id)) {
          restoredSongs.add(_decorateSongWithUserEdits(s));
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
          restoredSongs.insert(0, _decorateSongWithUserEdits(lastSong));
        }
      } catch (_) {}
    }

    final orderedRestored = _applySavedOrder(restoredSongs);

    int initialIdx = 0;
    if (_rememberedSongId != null && orderedRestored.isNotEmpty) {
      final found =
          orderedRestored.indexWhere((s) => s.id == _rememberedSongId);
      if (found != -1) initialIdx = found;
    }

    final initialSong =
        orderedRestored.isNotEmpty ? orderedRestored[initialIdx] : null;

    state = state.copyWith(
      allSongs: orderedRestored,
      currentQueue: orderedRestored,
      currentIndex: initialIdx,
      position: _rememberedPosition,
      duration:
          initialSong?.duration ?? const Duration(minutes: 3, seconds: 30),
      visualStyle: restoredStyle,
      loopMode: restoredLoop,
      playbackSpeed: savedSpeed,
      carAutoPlayEnabled: savedCarAuto,
      activeEqPreset: restoredPreset,
      customEqGains: List<double>.from(restoredPreset.gains),
    );

    await _initBackgroundAudioService();
    await scanLocalMusic(preserveCurrentSelection: true);
    await _preloadRememberedSongAtPosition();

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
    CarAutoPlayService.requestBackgroundKeepAlivePermissions();
  }

  SongModel _decorateSongWithUserEdits(SongModel s) {
    final edit = _savedSongEdits[s.id];
    final newTitle =
        (edit != null && (edit['title'] ?? '').isNotEmpty) ? edit['title']! : s.title;
    final newArtist =
        (edit != null && (edit['artist'] ?? '').isNotEmpty) ? edit['artist']! : s.artist;
    return s.copyWith(
      title: newTitle,
      artist: newArtist,
      isFavorite: _favoriteSongIds.contains(s.id) || s.isFavorite,
    );
  }

  List<SongModel> _applySavedOrder(List<SongModel> songs) {
    if (_savedOrderIds.isEmpty || songs.length <= 1) return songs;
    final Map<String, int> rankMap = {};
    for (int i = 0; i < _savedOrderIds.length; i++) {
      rankMap[_savedOrderIds[i]] = i;
    }
    final List<SongModel> ordered = List<SongModel>.from(songs);
    ordered.sort((a, b) {
      final ra = rankMap[a.id] ?? 999999;
      final rb = rankMap[b.id] ?? 999999;
      return ra.compareTo(rb);
    });
    return ordered;
  }

  Future<void> _saveCurrentOrder(List<SongModel> songs) async {
    _savedOrderIds = songs.map((s) => s.id).toList();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('saved_song_order_ids_v1', _savedOrderIds);
    } catch (_) {}
  }

  /// 拖拽调整歌曲顺序（长按拖拽松手后立即生效并永久保存排序）
  Future<void> reorderSong(int oldIndex, int newIndex) async {
    final list = List<SongModel>.from(state.allSongs);
    if (oldIndex < 0 || oldIndex >= list.length) return;
    if (newIndex > oldIndex) newIndex -= 1;
    newIndex = newIndex.clamp(0, list.length - 1);

    final playingId = state.currentSong?.id;
    final movedItem = list.removeAt(oldIndex);
    list.insert(newIndex, movedItem);

    int nextCurrentIndex = state.currentIndex;
    if (playingId != null) {
      final found = list.indexWhere((s) => s.id == playingId);
      if (found != -1) nextCurrentIndex = found;
    }

    state = state.copyWith(
      allSongs: list,
      currentQueue: list,
      currentIndex: nextCurrentIndex,
    );
    await _saveCurrentOrder(list);
    await _saveCustomSongsList(list);
  }

  /// 点击上移 (offset = -1) 或下移 (offset = 1) 调整单曲位置
  Future<void> moveSongByOffset(String songId, int offset) async {
    final list = List<SongModel>.from(state.allSongs);
    final idx = list.indexWhere((s) => s.id == songId);
    if (idx == -1) return;
    final targetIdx = (idx + offset).clamp(0, list.length - 1);
    if (targetIdx == idx) return;

    final playingId = state.currentSong?.id;
    final item = list.removeAt(idx);
    list.insert(targetIdx, item);

    int nextCurrentIndex = state.currentIndex;
    if (playingId != null) {
      final found = list.indexWhere((s) => s.id == playingId);
      if (found != -1) nextCurrentIndex = found;
    }

    state = state.copyWith(
      allSongs: list,
      currentQueue: list,
      currentIndex: nextCurrentIndex,
    );
    await _saveCurrentOrder(list);
    await _saveCustomSongsList(list);
  }

  /// 一键将指定歌曲置顶到第 1 位
  Future<void> pinSongToTop(String songId) async {
    final list = List<SongModel>.from(state.allSongs);
    final idx = list.indexWhere((s) => s.id == songId);
    if (idx <= 0) return;

    final playingId = state.currentSong?.id;
    final item = list.removeAt(idx);
    list.insert(0, item);

    int nextCurrentIndex = state.currentIndex;
    if (playingId != null) {
      final found = list.indexWhere((s) => s.id == playingId);
      if (found != -1) nextCurrentIndex = found;
    }

    state = state.copyWith(
      allSongs: list,
      currentQueue: list,
      currentIndex: nextCurrentIndex,
    );
    await _saveCurrentOrder(list);
    await _saveCustomSongsList(list);
  }

  /// 快捷批量排序：'title' (按歌名) | 'artist' (按歌手) | 'fav_first' (我喜欢置顶) | 'reverse' (倒序)
  Future<void> sortSongsByMode(String mode) async {
    if (state.allSongs.length <= 1) return;
    final playingId = state.currentSong?.id;
    List<SongModel> list = List<SongModel>.from(state.allSongs);

    if (mode == 'title') {
      list.sort((a, b) => a.title.compareTo(b.title));
    } else if (mode == 'artist') {
      list.sort((a, b) {
        final cmp = a.artist.compareTo(b.artist);
        return cmp != 0 ? cmp : a.title.compareTo(b.title);
      });
    } else if (mode == 'fav_first') {
      list.sort((a, b) {
        if (a.isFavorite == b.isFavorite) return 0;
        return a.isFavorite ? -1 : 1;
      });
    } else if (mode == 'reverse') {
      list = list.reversed.toList();
    }

    int nextCurrentIndex = state.currentIndex;
    if (playingId != null) {
      final found = list.indexWhere((s) => s.id == playingId);
      if (found != -1) nextCurrentIndex = found;
    }

    state = state.copyWith(
      allSongs: list,
      currentQueue: list,
      currentIndex: nextCurrentIndex,
    );
    await _saveCurrentOrder(list);
    await _saveCustomSongsList(list);
  }

  /// 编辑修改歌曲名称与歌手名（永久保存修改）
  Future<void> renameSong(
    String songId, {
    required String newTitle,
    required String newArtist,
  }) async {
    final t = newTitle.trim();
    final a = newArtist.trim();
    if (t.isEmpty) return;

    _savedSongEdits[songId] = {
      'title': t,
      'artist': a.isEmpty ? '未知歌手' : a,
    };
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('saved_song_edits_v1', jsonEncode(_savedSongEdits));
    } catch (_) {}

    final updatedAll = state.allSongs.map((s) {
      if (s.id == songId) {
        return s.copyWith(title: t, artist: a.isEmpty ? s.artist : a);
      }
      return s;
    }).toList();

    final updatedQueue = state.currentQueue.map((s) {
      if (s.id == songId) {
        return s.copyWith(title: t, artist: a.isEmpty ? s.artist : a);
      }
      return s;
    }).toList();

    state = state.copyWith(allSongs: updatedAll, currentQueue: updatedQueue);
    await _saveCustomSongsList(updatedAll);
    await _savePlaybackMemory();
    _syncMediaNotification();
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
    } catch (_) {}
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

  Future<void> resumeOrPlayRememberedSong() async {
    if (state.currentQueue.isEmpty) return;
    if (state.isPlaying && _audioPlayer.playing) return;

    final idx = state.currentIndex.clamp(0, state.currentQueue.length - 1);
    if (_audioPlayer.processingState == ProcessingState.idle ||
        _audioPlayer.processingState == ProcessingState.completed) {
      await playSongAt(
        idx,
        startPosition:
            state.position.inSeconds > 0 ? state.position : _rememberedPosition,
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

  /// 扫描手机本地音乐库（自动过滤已删除歌曲，应用用户自定义排序与改名，并严格保持上次记忆的歌曲位置）
  Future<int> scanLocalMusic({bool preserveCurrentSelection = true}) async {
    final currentSelectedId = state.currentSong?.id ?? _rememberedSongId;
    final currentPos =
        state.position.inSeconds > 0 ? state.position : _rememberedPosition;

    final scanned = await _scannerService.autoScanAllDeviceMusic();
    final filteredScanned = scanned
        .where((s) => !_deletedSongIds.contains(s.id))
        .map(_decorateSongWithUserEdits)
        .toList();

    if (filteredScanned.isNotEmpty || state.allSongs.isNotEmpty) {
      final existingCustom = state.allSongs
          .where((s) => !_deletedSongIds.contains(s.id))
          .map(_decorateSongWithUserEdits)
          .toList();
      final existingIds = existingCustom.map((e) => e.id).toSet();
      final newFromScan =
          filteredScanned.where((s) => !existingIds.contains(s.id)).toList();

      final merged = _applySavedOrder([...existingCustom, ...newFromScan]);

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
      await _saveCurrentOrder(merged);
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
    await _saveCurrentOrder(updatedAll);
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
    await _saveCurrentOrder(updated);
    await _saveCustomSongsList(updated);
    await playSongAt(0);
  }

  Future<void> playSongById(String songId) async {
    final idx = state.currentQueue.indexWhere((s) => s.id == songId);
    if (idx != -1) {
      await playSongAt(idx);
    }
  }

  /// 播放指定下标歌曲
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

  /// 保存当前所有状态记忆
  Future<void> saveMemoryOnBackground() async {
    await _savePlaybackMemory();
    await _saveCustomSongsList(state.allSongs);
    await _saveCurrentOrder(state.allSongs);
  }

  /// 将应用退到手机后台待命：
  /// 重要修复：绝不调用 SystemNavigator.pop()！因为 SystemNavigator.pop() 在安卓上会调用 Activity.finish() 销毁引擎导致音乐立即停止！
  /// 若原生 moveTaskToBack 通道可用则退回桌面且不断播；若未更新原生层则保持音乐继续播放并激活后台常驻白名单。
  Future<bool> moveAppToBackground() async {
    await saveMemoryOnBackground();
    _syncMediaNotification();
    await CarAutoPlayService.requestBackgroundKeepAlivePermissions();
    if (Platform.isAndroid) {
      try {
        final moved =
            await _retainChannel.invokeMethod<bool>('moveTaskToBack');
        if (moved == true) return true;
      } catch (_) {
        // 未注册原生 moveTaskToBack 时忽略异常，保持当前播放不中断
      }
    }
    return false;
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

  /// 停止音乐并彻底结束 App 进程（仅当用户明确点击“彻底退出”时调用）
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
    await prefs.setStringList(
      'favorite_song_ids_v1',
      _favoriteSongIds.toList(),
    );

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
