import 'package:flutter/material.dart';

/// 播放页三种经典视觉样式（可随时无缝切换）
enum PlayerVisualStyle {
  vinyl('经典黑胶', Icons.album_rounded),
  fullscreen('沉浸大图', Icons.crop_portrait_rounded),
  glassCard('流光卡片', Icons.auto_awesome_mosaic_rounded);

  final String label;
  final IconData icon;
  const PlayerVisualStyle(this.label, this.icon);
}

/// 播放循环模式
enum LoopPlayMode {
  sequence('顺序播放', Icons.repeat_rounded),
  single('单曲循环', Icons.repeat_one_rounded),
  shuffle('随机播放', Icons.shuffle_rounded);

  final String label;
  final IconData icon;
  const LoopPlayMode(this.label, this.icon);
}

/// 单行 LRC 歌词模型
class LyricLine {
  final Duration timestamp;
  final String text;
  final String? translation;

  const LyricLine({
    required this.timestamp,
    required this.text,
    this.translation,
  });
}

/// 本地音乐实体模型
class SongModel {
  final String id;
  final String title;
  final String artist;
  final String album;
  final String filePath;
  final Duration duration;
  final int sizeBytes;
  final String format; // FLAC, MP3, WAV, M4A
  final Color dominantColor;
  final Color accentColor;
  final List<LyricLine> lyrics;
  final bool isFavorite;
  final String folderName;

  const SongModel({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.filePath,
    required this.duration,
    this.sizeBytes = 0,
    this.format = 'FLAC',
    this.dominantColor = const Color(0xFF1DB954),
    this.accentColor = const Color(0xFF0F4C3A),
    this.lyrics = const [],
    this.isFavorite = false,
    this.folderName = 'LocalMusic',
  });

  SongModel copyWith({
    bool? isFavorite,
    List<LyricLine>? lyrics,
    Color? dominantColor,
    Color? accentColor,
  }) {
    return SongModel(
      id: id,
      title: title,
      artist: artist,
      album: album,
      filePath: filePath,
      duration: duration,
      sizeBytes: sizeBytes,
      format: format,
      dominantColor: dominantColor ?? this.dominantColor,
      accentColor: accentColor ?? this.accentColor,
      lyrics: lyrics ?? this.lyrics,
      isFavorite: isFavorite ?? this.isFavorite,
      folderName: folderName,
    );
  }

  /// 解析标准 LRC 歌词文本，例如 [01:23.45]歌词内容
  static List<LyricLine> parseLrc(String lrcContent) {
    final List<LyricLine> result = [];
    final RegExp regExp = RegExp(r'\[(\d{2}):(\d{2})\.(\d{2,3})\](.*)');
    for (final rawLine in lrcContent.split('\n')) {
      final match = regExp.firstMatch(rawLine.trim());
      if (match != null) {
        final minutes = int.parse(match.group(1)!);
        final seconds = int.parse(match.group(2)!);
        final millisStr = match.group(3)!;
        final millis = millisStr.length == 2
            ? int.parse(millisStr) * 10
            : int.parse(millisStr);
        final text = match.group(4)!.trim();
        if (text.isNotEmpty) {
          result.add(
            LyricLine(
              timestamp: Duration(
                minutes: minutes,
                seconds: seconds,
                milliseconds: millis,
              ),
              text: text,
            ),
          );
        }
      }
    }
    result.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return result;
  }
}
