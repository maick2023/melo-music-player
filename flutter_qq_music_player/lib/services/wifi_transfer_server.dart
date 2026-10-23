import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

/// 手机端内置局域网 HTTP 传歌服务器
/// 开启后电脑或另一台手机在同一 Wi-Fi 下直接打开浏览器即可拖拽上传 MP3/FLAC/LRC 文件
class WifiTransferServer {
  HttpServer? _server;
  String? _serverUrl;
  final Directory targetMusicDirectory;
  final void Function(String fileName) onFileReceived;

  WifiTransferServer({
    required this.targetMusicDirectory,
    required this.onFileReceived,
  });

  bool get isRunning => _server != null;
  String? get serverUrl => _serverUrl;

  /// 启动局域网 HTTP 传歌服务（默认端口 8080）
  Future<String> start({int port = 8080}) async {
    if (_server != null && _serverUrl != null) return _serverUrl!;

    final info = NetworkInfo();
    String? wifiIp = await info.getWifiIP();
    wifiIp ??= '127.0.0.1';

    final router = Router();

    // 1. 电脑浏览器访问首页：返回精美的拖拽上传网页
    router.get('/', (Request request) {
      return Response.ok(
        _buildWebUploadPageHtml(wifiIp!, port),
        headers: {'content-type': 'text/html; charset=utf-8'},
      );
    });

    // 2. 获取当前已导入的手机音乐列表
    router.get('/api/files', (Request request) async {
      final files = await targetMusicDirectory
          .list()
          .where((e) => e is File)
          .map((e) => p.basename(e.path))
          .toList();
      return Response.ok(
        jsonEncode({'files': files}),
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });

    // 3. 接收浏览器上传的二进制音频/歌词文件 (PUT / POST 原始流，简单稳定免第三方 multipart 解析依赖)
    router.post('/api/upload', (Request request) async {
      final rawName = request.headers['x-file-name'] ?? 'track_${DateTime.now().millisecondsSinceEpoch}.mp3';
      final fileName = Uri.decodeComponent(rawName);
      final safeName = p.basename(fileName);
      final savePath = p.join(targetMusicDirectory.path, safeName);
      final file = File(savePath);
      final sink = file.openWrite();
      await request.read().pipe(sink);
      await sink.close();

      onFileReceived(safeName);
      return Response.ok(
        jsonEncode({'ok': true, 'name': safeName}),
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });

    _server = await shelf_io.serve(router, InternetAddress.anyIPv4, port);
    _serverUrl = 'http://$wifiIp:${_server!.port}';
    return _serverUrl!;
  }

  /// 停止 Wi-Fi 传歌服务
  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _serverUrl = null;
  }

  /// 内嵌在手机里的局域网网页端 HTML（电脑浏览器打开该地址即可直接拖拽传歌）
  String _buildWebUploadPageHtml(String ip, int port) {
    return '''
<!DOCTYPE html>
<html lang="zh-CN">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>悦听播放器 · Wi-Fi 局域网无线传歌</title>
  <style>
    body { margin: 0; font-family: -apple-system, BlinkMacSystemFont, "PingFang SC", sans-serif; background: #0B1218; color: #F1F5F9; display: flex; align-items: center; justify-content: center; min-height: 100vh; }
    .card { width: 90%; max-width: 560px; background: #141E28; border: 1px solid rgba(255,255,255,0.1); border-radius: 24px; padding: 32px; box-shadow: 0 24px 48px rgba(0,0,0,0.45); text-align: center; }
    .badge { display: inline-block; background: rgba(0,214,118,0.15); color: #00D676; padding: 6px 14px; border-radius: 999px; font-size: 13px; font-weight: 600; margin-bottom: 12px; }
    h1 { margin: 0 0 8px; font-size: 24px; }
    p { margin: 0 0 24px; color: #94A3B8; font-size: 14px; }
    .dropzone { border: 2px dashed #00D676; background: rgba(0,214,118,0.05); border-radius: 18px; padding: 42px 20px; cursor: pointer; transition: 0.2s; }
    .dropzone:hover { background: rgba(0,214,118,0.12); }
    .log { margin-top: 20px; text-align: left; max-height: 180px; overflow-y: auto; font-size: 13px; color: #CBD5E1; background: #0E161E; border-radius: 12px; padding: 12px; }
  </style>
</head>
<body>
  <div class="card">
    <div class="badge">● 已连接至手机 ($ip:$port)</div>
    <h1>Wi-Fi 无线传歌工作台</h1>
    <p>支持批量拖拽上传 .mp3 / .flac / .wav / .m4a 音频及同名 .lrc 歌词文件</p>
    <label class="dropzone" id="dropzone">
      <input type="file" id="fileInput" multiple accept=".mp3,.flac,.wav,.m4a,.aac,.ogg,.lrc" style="display:none" />
      <div style="font-size:36px;margin-bottom:10px;">🎵</div>
      <div style="font-weight:600;font-size:16px;">点击选择文件 或 直接将歌曲拖拽至此处</div>
      <div style="font-size:12px;color:#64748B;margin-top:6px;">上传完成后手机端曲库将自动刷新</div>
    </label>
    <div class="log" id="logBox">等待上传任务...</div>
  </div>
  <script>
    const input = document.getElementById('fileInput');
    const logBox = document.getElementById('logBox');
    const dropzone = document.getElementById('dropzone');
    async function uploadFiles(files) {
      logBox.innerHTML = '';
      for (const file of files) {
        const item = document.createElement('div');
        item.textContent = '⏳ 正在上传: ' + file.name + ' ...';
        logBox.appendChild(item);
        const res = await fetch('/api/upload', {
          method: 'POST',
          headers: { 'x-file-name': encodeURIComponent(file.name) },
          body: file
        });
        if (res.ok) item.textContent = '✅ 上传成功: ' + file.name;
        else item.textContent = '❌ 上传失败: ' + file.name;
      }
    }
    input.addEventListener('change', (e) => uploadFiles(e.target.files));
    dropzone.addEventListener('dragover', (e) => e.preventDefault());
    dropzone.addEventListener('drop', (e) => { e.preventDefault(); uploadFiles(e.dataTransfer.files); });
  </script>
</body>
</html>
''';
  }
}
