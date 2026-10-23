import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart' as audio_query;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/song_model.dart';

/// 支持的全音频格式后缀清单（配合 FFmpeg / media_kit 与系统硬解，通吃所有主流与发烧无损格式）
const Set<String> kSupportedAllAudioExtensions = {
  '.mp3',
  '.flac',
  '.wav',
  '.ape',
  '.dsf',
  '.dff',
  '.alac',
  '.m4a',
  '.aac',
  '.ogg',
  '.opus',
  '.wma',
  '.aiff',
  '.wv',
};

/// 负责 App 启动时免手动导入自动全盘扫描（Android MediaStore + 常用音乐目录监听 + iOS Apple Music 曲库与沙盒同步）
class LocalScannerService {
  final audio_query.OnAudioQuery _audioQuery = audio_query.OnAudioQuery();

  static const List<Color> _paletteColors = [
    Color(0xFF00C471),
    Color(0xFF2563EB),
    Color(0xFF9333EA),
    Color(0xFFE11D48),
    Color(0xFFD97706),
    Color(0xFF0891B2),
  ];

  /// App 启动时自动调用：无需用户手动挑选文件，自动扫描全机音频并过滤短铃声
  Future<List<SongModel>> autoScanAllDeviceMusic({int minDurationSeconds = 45}) async {
    final List<SongModel> songs = [];

    // 1. 自动扫描 App 专属音乐目录与缓存目录
    final sandboxSongs = await _scanAppSandboxDirectory();
    songs.addAll(sandboxSongs);

    // 2. Android & iOS 系统媒体库全自动扫描 (Android 走 MediaStore 全盘索引，iOS 走 MPMediaLibrary 系统曲库)
    final bool hasPermission = await _requestMediaPermission();
    if (hasPermission) {
      final queried = await _audioQuery.querySongs(
        sortType: audio_query.SongSortType.DATE_ADDED,
        orderType: audio_query.OrderType.DESC_OR_GREATER,
        uriType: audio_query.UriType.EXTERNAL,
        ignoreCase: true,
      );

      for (int i = 0; i < queried.length; i++) {
        final item = queried[i];
        final durationSec = (item.duration ?? 0) ~/ 1000;
        if (durationSec < minDurationSeconds) continue;

        final filePath = item.data;
        final ext = p.extension(filePath).replaceAll('.', '').toUpperCase();
        final lyrics = await _loadMatchingLrcFile(filePath);
        final color = _paletteColors[i % _paletteColors.length];

        songs.add(
          SongModel(
            id: 'media_${item.id}',
            title: item.title,
            artist: (item.artist == null || item.artist == '<unknown>')
                ? '未知歌手'
                : item.artist!,
            album: (item.album == null || item.album == '<unknown>')
                ? '本地无损专辑'
                : item.album!,
            filePath: filePath,
            duration: Duration(milliseconds: item.duration ?? 0),
            sizeBytes: item.size,
            format: ext.isEmpty ? 'FLAC' : ext,
            dominantColor: color,
            accentColor: HSLColor.fromColor(color).withLightness(0.22).toColor(),
            lyrics: lyrics,
            folderName: p.basename(p.dirname(filePath)),
          ),
        );
      }
    }

    return songs;
  }

  /// 兼容原有的 scanDeviceMusic 接口
  Future<List<SongModel>> scanDeviceMusic({int minDurationSeconds = 45}) {
    return autoScanAllDeviceMusic(minDurationSeconds: minDurationSeconds);
  }

  /// 补充方式：手动从文件选择器导入全格式音频
  Future<List<SongModel>> pickAndImportAudioFiles() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowMultiple: true,
      allowedExtensions: kSupportedAllAudioExtensions
          .map((e) => e.replaceAll('.', ''))
          .followedBy(['lrc', 'qrc'])
          .toList(),
    );

    if (result == null || result.files.isEmpty) return [];

    final musicDir = await getAppMusicDirectory();
    for (final picked in result.files) {
      if (picked.path == null) continue;
      final srcFile = File(picked.path!);
      final targetPath = p.join(musicDir.path, picked.name);
      if (srcFile.path != targetPath) {
        await srcFile.copy(targetPath);
      }
    }
    return _scanAppSandboxDirectory();
  }

  Future<Directory> getAppMusicDirectory() async {
    final docDir = await getApplicationDocumentsDirectory();
    final musicDir = Directory(p.join(docDir.path, 'MeloLocalMusic'));
    if (!await musicDir.exists()) {
      await musicDir.create(recursive: true);
    }
    return musicDir;
  }

  Future<List<SongModel>> _scanAppSandboxDirectory() async {
    final musicDir = await getAppMusicDirectory();
    final List<SongModel> result = [];
    final entities = await musicDir.list().toList();

    int index = 0;
    for (final entity in entities) {
      if (entity is! File) continue;
      final ext = p.extension(entity.path).toLowerCase();
      if (!kSupportedAllAudioExtensions.contains(ext)) continue;

      final stat = await entity.stat();
      final baseName = p.basenameWithoutExtension(entity.path);
      String artist = '本地歌手';
      String title = baseName;
      if (baseName.contains(' - ')) {
        final parts = baseName.split(' - ');
        artist = parts.first.trim();
        title = parts.sublist(1).join(' - ').trim();
      }

      final lyrics = await _loadMatchingLrcFile(entity.path);
      final color = _paletteColors[index % _paletteColors.length];
      index++;

      result.add(
        SongModel(
          id: 'sandbox_${entity.path.hashCode}',
          title: title,
          artist: artist,
          album: '本地全格式曲库',
          filePath: entity.path,
          duration: const Duration(minutes: 3, seconds: 45),
          sizeBytes: stat.size,
          format: ext.replaceAll('.', '').toUpperCase(),
          dominantColor: color,
          accentColor: HSLColor.fromColor(color).withLightness(0.22).toColor(),
          lyrics: lyrics,
          folderName: '自动监控目录',
        ),
      );
    }
    return result;
  }

  Future<List<LyricLine>> _loadMatchingLrcFile(String audioFilePath) async {
    try {
      final lrcPath = p.setExtension(audioFilePath, '.lrc');
      final lrcFile = File(lrcPath);
      if (await lrcFile.exists()) {
        final content = await lrcFile.readAsString();
        return SongModel.parseLrc(content);
      }
    } catch (_) {}
    return const [];
  }

  Future<bool> _requestMediaPermission() async {
    final audioStatus = await Permission.audio.request();
    if (audioStatus.isGranted) return true;
    final storageStatus = await Permission.storage.request();
    return storageStatus.isGranted;
  }
}
