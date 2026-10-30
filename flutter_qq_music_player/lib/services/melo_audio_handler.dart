import 'dart:async';
import 'package:audio_service/audio_service.dart';
import '../models/song_model.dart';

/// 系统级媒体会话处理器 (Android MediaSession + 前台常驻通知栏 + 车载蓝牙 AVRCP 方向盘按键控制 + iOS 锁屏控制中心)
class MeloAudioHandler extends BaseAudioHandler with SeekHandler {
  final Future<void> Function() onPlayCmd;
  final Future<void> Function() onPauseCmd;
  final Future<void> Function() onNextCmd;
  final Future<void> Function() onPreviousCmd;
  final Future<void> Function(Duration position) onSeekCmd;
  final Future<void> Function() onTogglePlayPauseCmd;

  Timer? _clickDebounceTimer;
  int _clickCount = 0;

  MeloAudioHandler({
    required this.onPlayCmd,
    required this.onPauseCmd,
    required this.onNextCmd,
    required this.onPreviousCmd,
    required this.onSeekCmd,
    required this.onTogglePlayPauseCmd,
  }) {
    playbackState.add(
      PlaybackState(
        controls: const [
          MediaControl.skipToPrevious,
          MediaControl.play,
          MediaControl.skipToNext,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
          MediaAction.play,
          MediaAction.pause,
          MediaAction.playPause,
          MediaAction.skipToNext,
          MediaAction.skipToPrevious,
        },
        androidCompactActionIndices: const [0, 1, 2],
        processingState: AudioProcessingState.ready,
        playing: false,
      ),
    );
  }

  /// 当车载蓝牙连接后发送自动播放指令，或用户按车机/方向盘「播放」键时触发
  @override
  Future<void> play() => onPlayCmd();

  /// 当用户按车机/方向盘「暂停」键时触发
  @override
  Future<void> pause() => onPauseCmd();

  /// 当用户按方向盘/中控「下一首 (>>|)」物理按键时触发
  @override
  Future<void> skipToNext() => onNextCmd();

  /// 当用户按方向盘/中控「上一首 (|<<)」物理按键时触发
  @override
  Future<void> skipToPrevious() => onPreviousCmd();

  /// 部分车型方向盘快进键映射为 fastForward，同样触发下一首
  @override
  Future<void> fastForward() => onNextCmd();

  /// 部分车型方向盘快退键映射为 rewind，同样触发上一首
  @override
  Future<void> rewind() => onPreviousCmd();

  @override
  Future<void> seek(Duration position) => onSeekCmd(position);

  /// 兼容部分车载蓝牙与蓝牙耳机通过单键多击 (MediaButton.media / next / previous) 发送的按键事件
  @override
  Future<void> click([MediaButton button = MediaButton.media]) async {
    if (button == MediaButton.next) {
      await onNextCmd();
      return;
    }
    if (button == MediaButton.previous) {
      await onPreviousCmd();
      return;
    }
    _clickCount++;
    _clickDebounceTimer?.cancel();
    _clickDebounceTimer = Timer(const Duration(milliseconds: 320), () async {
      final count = _clickCount;
      _clickCount = 0;
      if (count == 1) {
        await onTogglePlayPauseCmd();
      } else if (count == 2) {
        await onNextCmd();
      } else if (count >= 3) {
        await onPreviousCmd();
      }
    });
  }

  /// 实时同步当前歌曲名、歌手、进度到车载中控屏与手机锁屏通知栏
  void syncMediaState({
    required SongModel? song,
    required bool isPlaying,
    required Duration position,
    required Duration duration,
    required double speed,
  }) {
    if (song != null) {
      mediaItem.add(
        MediaItem(
          id: song.id,
          title: song.title,
          artist: song.artist,
          album: song.album,
          duration: duration.inSeconds > 0 ? duration : song.duration,
        ),
      );
    }

    playbackState.add(
      PlaybackState(
        controls: [
          MediaControl.skipToPrevious,
          isPlaying ? MediaControl.pause : MediaControl.play,
          MediaControl.skipToNext,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
          MediaAction.play,
          MediaAction.pause,
          MediaAction.playPause,
          MediaAction.skipToNext,
          MediaAction.skipToPrevious,
        },
        androidCompactActionIndices: const [0, 1, 2],
        processingState: AudioProcessingState.ready,
        playing: isPlaying,
        updatePosition: position,
        speed: speed,
      ),
    );
  }
}
