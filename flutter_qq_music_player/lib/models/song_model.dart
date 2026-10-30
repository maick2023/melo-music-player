import 'package:flutter/material.dart';

/// 播放页三种经典视觉样式（可随时无缝切换）
enum PlayerVisualStyle {
  vinyl('经典黑胶', Icons.album_rounded),
  fullscreen('沉浸大图', Icons.crop_portrait_rounded),
  glassCard('流光卡片', Icons.auto_awesome_mosaic_rounded);

  static const PlayerVisualStyle classicVinyl = PlayerVisualStyle.vinyl;
  static const PlayerVisualStyle immersiveCover = PlayerVisualStyle.fullscreen;
  static const PlayerVisualStyle liquidGlassCard = PlayerVisualStyle.glassCard;

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

  Map<String, dynamic> toJson() => {
        'ms': timestamp.inMilliseconds,
        'text': text,
        if (translation != null) 'tr': translation,
      };

  factory LyricLine.fromJson(Map<String, dynamic> json) {
    return LyricLine(
      timestamp: Duration(milliseconds: (json['ms'] as num?)?.toInt() ?? 0),
      text: (json['text'] as String?) ?? '',
      translation: json['tr'] as String?,
    );
  }
}

/// 本地与在线音乐实体模型（支持 JSON 持久化记忆）
class SongModel {
  final String id;
  final String title;
  final String artist;
  final String album;
  final String filePath;
  final Duration duration;
  final int sizeBytes;
  final String format; // FLAC, MP3, WAV, M4A, AAC
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

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'artist': artist,
        'album': album,
        'filePath': filePath,
        'durationMs': duration.inMilliseconds,
        'sizeBytes': sizeBytes,
        'format': format,
        'dominantColor': dominantColor.value,
        'accentColor': accentColor.value,
        'isFavorite': isFavorite,
        'folderName': folderName,
        'lyrics': lyrics.map((e) => e.toJson()).toList(),
      };

  factory SongModel.fromJson(Map<String, dynamic> json) {
    final rawLyrics = (json['lyrics'] as List<dynamic>?) ?? const [];
    return SongModel(
      id: (json['id'] as String?) ?? 'song_unknown',
      title: (json['title'] as String?) ?? '未知歌曲',
      artist: (json['artist'] as String?) ?? '未知歌手',
      album: (json['album'] as String?) ?? '本地专辑',
      filePath: (json['filePath'] as String?) ?? '',
      duration: Duration(
        milliseconds: (json['durationMs'] as num?)?.toInt() ?? 210000,
      ),
      sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
      format: (json['format'] as String?) ?? 'FLAC',
      dominantColor: Color(
        (json['dominantColor'] as num?)?.toInt() ?? 0xFF00C471,
      ),
      accentColor: Color(
        (json['accentColor'] as num?)?.toInt() ?? 0xFF0F4C3A,
      ),
      isFavorite: (json['isFavorite'] as bool?) ?? false,
      folderName: (json['folderName'] as String?) ?? 'LocalMusic',
      lyrics: rawLyrics
          .whereType<Map<String, dynamic>>()
          .map(LyricLine.fromJson)
          .toList(),
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
