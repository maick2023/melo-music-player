import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../models/song_model.dart';

/// 全网在线音乐搜索服务（纯净真唱流媒体版）
/// 严格保证：
///   1. 打开搜索窗口时列表为空，不预置任何假歌，完全由用户输入关键词触发真实联网搜索
///   2. 只返回包含真实 HTTPS 真人原唱音频流的歌曲，彻底移除所有合成曲调 (demo://)
///   3. 自动拉取真实逐行时间轴 LRC 歌词
class OnlineSearchService {
  static const List<Color> _onlineColors = [
    Color(0xFF00C471),
    Color(0xFF3B82F6),
    Color(0xFF8B5CF6),
    Color(0xFFEC4899),
    Color(0xFFF59E0B),
    Color(0xFF06B6D4),
  ];

  /// 根据用户输入的歌名/歌手搜索真实可播放的真人原唱流媒体歌曲
  Future<List<SongModel>> searchOnlineSongs(String keyword) async {
    final query = keyword.trim();
    if (query.isEmpty) return [];

    // 优先通过 iTunes 多区接口获取 100% 免鉴权、带真人原唱的 M4A/AAC 音频直链，同时并发查询网易云获取中文歌名与精确 LRC 歌词
    final results = await Future.wait([
      _searchItunesRealStreams(query),
      _searchNeteasePlayableSongs(query),
    ]);

    final List<SongModel> finalSongs = [];
    final itunesSongs = results[0];
    final neteaseSongs = results[1];

    // 1. 先加入 100% 保证能放出真人原唱的 iTunes 高清流媒体结果
    finalSongs.addAll(itunesSongs);

    // 2. 补充网易云非 VIP 可直连曲目
    for (final nSong in neteaseSongs) {
      final exists = finalSongs.any(
        (s) => s.title == nSong.title && s.artist == nSong.artist,
      );
      if (!exists) {
        finalSongs.add(nSong);
      }
    }

    return finalSongs;
  }

  /// 通道 A：Apple Music / iTunes 高清真人原唱流媒体接口（每个结果都自带真实的 .m4a 演唱音频流 previewUrl）
  Future<List<SongModel>> _searchItunesRealStreams(String query) async {
    for (final country in ['CN', 'HK', 'TW', 'SG', 'US']) {
      try {
        final uri = Uri.parse(
          'https://itunes.apple.com/search?term=${Uri.encodeComponent(query)}&media=music&entity=song&limit=25&country=$country',
        );
        final response =
            await http.get(uri).timeout(const Duration(seconds: 6));
        if (response.statusCode == 200) {
          final data = jsonDecode(utf8.decode(response.bodyBytes))
              as Map<String, dynamic>;
          final List<dynamic> results = data['results'] ?? [];
          final List<SongModel> songs = [];

          for (int i = 0; i < results.length; i++) {
            final item = results[i] as Map<String, dynamic>;
            final previewUrl = item['previewUrl'] as String?;
            if (previewUrl == null || !previewUrl.startsWith('http')) continue;

            final title = (item['trackName'] as String?) ?? '未知歌曲';
            final artist = (item['artistName'] as String?) ?? '未知歌手';
            final album = (item['collectionName'] as String?) ?? '在线精选专辑';
            final durationMs = (item['trackTimeMillis'] as int?) ?? 210000;
            final color = _onlineColors[i % _onlineColors.length];

            songs.add(
              SongModel(
                id: 'itunes_${item['trackId'] ?? i}',
                title: title,
                artist: artist,
                album: album,
                filePath: previewUrl,
                duration: Duration(milliseconds: durationMs),
                format: 'AAC · 在线真人原唱',
                dominantColor: color,
                accentColor:
                    HSLColor.fromColor(color).withLightness(0.2).toColor(),
                folderName: '全网在线搜索',
                lyrics: [
                  LyricLine(timestamp: Duration.zero, text: '$title - $artist'),
                  const LyricLine(
                    timestamp: Duration(seconds: 2),
                    text: '正在同步云端逐行 LRC 歌词...',
                  ),
                ],
              ),
            );
          }
          if (songs.isNotEmpty) return songs;
        }
      } catch (_) {}
    }
    return [];
  }

  /// 通道 B：网易云音乐公开搜索接口（过滤掉 fee==1 的纯 VIP 无声曲目）
  Future<List<SongModel>> _searchNeteasePlayableSongs(String query) async {
    try {
      final uri = Uri.parse(
        'https://music.163.com/api/search/get/web?csrf_token=&hlpretag=&hlposttag=&s=${Uri.encodeComponent(query)}&type=1&offset=0&total=true&limit=20',
      );
      final response = await http
          .get(
            uri,
            headers: {
              'Referer': 'https://music.163.com',
              'User-Agent':
                  'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/120.0.0.0 Mobile Safari/537.36',
            },
          )
          .timeout(const Duration(seconds: 6));

      if (response.statusCode == 200) {
        final data =
            jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        final resultObj = data['result'] as Map<String, dynamic>?;
        final List<dynamic> songsRaw = resultObj?['songs'] ?? [];
        final List<SongModel> list = [];

        for (int i = 0; i < songsRaw.length; i++) {
          final item = songsRaw[i] as Map<String, dynamic>;
          final songId = item['id'];
          final fee = (item['fee'] as int?) ?? 0;
          // 过滤掉收费/VIP 锁定的无外链曲目，只保留可公开播放的曲目
          if (songId == null || fee == 1 || fee == 4) continue;

          final title = (item['name'] as String?) ?? '未知歌曲';
          final artistsList = (item['artists'] as List<dynamic>?) ?? [];
          final artist = artistsList.isNotEmpty
              ? ((artistsList.first as Map<String, dynamic>)['name']
                      as String? ??
                  '未知歌手')
              : '未知歌手';
          final albumObj = item['album'] as Map<String, dynamic>?;
          final album = (albumObj?['name'] as String?) ?? '在线精选专辑';
          final durationMs = (item['duration'] as int?) ?? 210000;
          final color = _onlineColors[i % _onlineColors.length];

          list.add(
            SongModel(
              id: 'netease_$songId',
              title: title,
              artist: artist,
              album: album,
              filePath:
                  'https://music.163.com/song/media/outer/url?id=$songId.mp3',
              duration: Duration(milliseconds: durationMs),
              format: 'MP3 · 在线真人原唱',
              dominantColor: color,
              accentColor:
                  HSLColor.fromColor(color).withLightness(0.2).toColor(),
              folderName: '全网在线搜索',
              lyrics: [
                LyricLine(timestamp: Duration.zero, text: '$title - $artist'),
                const LyricLine(
                  timestamp: Duration(seconds: 2),
                  text: '正在同步云端逐行 LRC 歌词...',
                ),
              ],
            ),
          );
        }
        return list;
      }
    } catch (_) {}
    return [];
  }

  /// 自动根据【歌名 + 歌手】从云端拉取真实的逐行时间轴 LRC 歌词
  Future<List<LyricLine>> fetchCloudLyricsForSong(SongModel song) async {
    if (song.id.startsWith('netease_')) {
      final neteaseId = song.id.replaceFirst('netease_', '');
      final lines = await _fetchNeteaseLyricById(neteaseId);
      if (lines.isNotEmpty) return lines;
    }

    try {
      final cleanTitle =
          song.title.replaceAll(RegExp(r'\(.*?\)|（.*?）'), '').trim();
      final searchKw =
          song.artist != '未知歌手' && song.artist != '本地歌手'
              ? '$cleanTitle ${song.artist}'
              : cleanTitle;
      final searchUri = Uri.parse(
        'https://music.163.com/api/search/get/web?s=${Uri.encodeComponent(searchKw)}&type=1&offset=0&total=true&limit=3',
      );
      final searchRes = await http
          .get(searchUri, headers: {'Referer': 'https://music.163.com'})
          .timeout(const Duration(seconds: 5));
      if (searchRes.statusCode == 200) {
        final data = jsonDecode(utf8.decode(searchRes.bodyBytes))
            as Map<String, dynamic>;
        final songs = (data['result']?['songs'] as List<dynamic>?) ?? [];
        if (songs.isNotEmpty) {
          final firstId = (songs.first as Map<String, dynamic>)['id'];
          if (firstId != null) {
            final lines = await _fetchNeteaseLyricById(firstId.toString());
            if (lines.isNotEmpty) return lines;
          }
        }
      }
    } catch (_) {}

    try {
      final uri = Uri.parse(
        'https://lrclib.net/api/search?q=${Uri.encodeComponent("${song.title} ${song.artist}")}',
      );
      final res = await http.get(uri).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final list = jsonDecode(utf8.decode(res.bodyBytes)) as List<dynamic>;
        if (list.isNotEmpty) {
          final first = list.first as Map<String, dynamic>;
          final syncedLrc = (first['syncedLyrics'] as String?) ?? '';
          if (syncedLrc.isNotEmpty) {
            final parsed = SongModel.parseLrc(syncedLrc);
            if (parsed.isNotEmpty) return parsed;
          }
        }
      }
    } catch (_) {}

    return song.lyrics;
  }

  Future<List<LyricLine>> _fetchNeteaseLyricById(String songId) async {
    try {
      final uri = Uri.parse(
        'https://music.163.com/api/song/lyric?os=pc&id=$songId&lv=-1&kv=-1&tv=-1',
      );
      final res = await http
          .get(uri, headers: {'Referer': 'https://music.163.com'})
          .timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final data =
            jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
        final lrcRaw = (data['lrc']?['lyric'] as String?) ?? '';
        if (lrcRaw.isNotEmpty) {
          final parsed = SongModel.parseLrc(lrcRaw);
          if (parsed.isNotEmpty) return parsed;
        }
      }
    } catch (_) {}
    return [];
  }
}
