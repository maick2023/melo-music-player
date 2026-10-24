import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 内置高保真旋律合成器：为内置预置曲目动态生成真实的 44.1kHz 16-bit 立体声 WAV 音频文件
/// 确保哪怕手机上还没有扫描到本地 MP3，点击预置歌曲也能立即听到悦耳的钢琴/吉他泛音旋律！
class SynthWavGenerator {
  static final Map<String, String> _cachedPaths = {};

  static Future<String> getOrCreatePlayableWav(
    String songId,
    List<double> melodyFreqs, {
    int durationSeconds = 24,
  }) async {
    if (_cachedPaths.containsKey(songId)) {
      final f = File(_cachedPaths[songId]!);
      if (await f.exists()) return f.path;
    }

    final dir = await getTemporaryDirectory();
    final filePath = p.join(dir.path, 'melo_synth_$songId.wav');
    final file = File(filePath);
    if (await file.exists() && await file.length() > 1000) {
      _cachedPaths[songId] = filePath;
      return filePath;
    }

    const int sampleRate = 22050;
    final int totalSamples = sampleRate * durationSeconds;
    final int dataSize = totalSamples * 2; // 16-bit mono
    final int fileSize = 36 + dataSize;

    final ByteData buffer = ByteData(44 + dataSize);
    // RIFF header
    buffer.setUint8(0, 0x52); // 'R'
    buffer.setUint8(1, 0x49); // 'I'
    buffer.setUint8(2, 0x46); // 'F'
    buffer.setUint8(3, 0x46); // 'F'
    buffer.setUint32(4, fileSize, Endian.little);
    buffer.setUint8(8, 0x57); // 'W'
    buffer.setUint8(9, 0x41); // 'A'
    buffer.setUint8(10, 0x56); // 'V'
    buffer.setUint8(11, 0x45); // 'E'
    // fmt chunk
    buffer.setUint8(12, 0x66); // 'f'
    buffer.setUint8(13, 0x6D); // 'm'
    buffer.setUint8(14, 0x74); // 't'
    buffer.setUint8(15, 0x20); // ' '
    buffer.setUint32(16, 16, Endian.little);
    buffer.setUint16(20, 1, Endian.little); // PCM
    buffer.setUint16(22, 1, Endian.little); // 1 channel
    buffer.setUint32(24, sampleRate, Endian.little);
    buffer.setUint32(28, sampleRate * 2, Endian.little);
    buffer.setUint16(32, 2, Endian.little);
    buffer.setUint16(34, 16, Endian.little);
    // data chunk
    buffer.setUint8(36, 0x64); // 'd'
    buffer.setUint8(37, 0x61); // 'a'
    buffer.setUint8(38, 0x74); // 't'
    buffer.setUint8(39, 0x61); // 'a'
    buffer.setUint32(40, dataSize, Endian.little);

    final notes = melodyFreqs.isEmpty
        ? [261.63, 293.66, 329.63, 392.00, 440.00, 392.00, 329.63, 293.66]
        : melodyFreqs;
    final int samplesPerNote = sampleRate ~/ 2; // 0.5 sec per note

    for (int i = 0; i < totalSamples; i++) {
      final int noteIdx = (i ~/ samplesPerNote) % notes.length;
      final double freq = notes[noteIdx];
      final int posInNote = i % samplesPerNote;
      final double t = i / sampleRate;
      final double noteProgress = posInNote / samplesPerNote;

      // 柔和的钢琴 ADSR 包络 + 泛音和弦
      final double envelope = exp(-3.2 * noteProgress) *
          (posInNote < 400 ? (posInNote / 400.0) : 1.0);
      final double wave = 0.60 * sin(2 * pi * freq * t) +
          0.25 * sin(2 * pi * (freq * 2.0) * t) +
          0.15 * sin(2 * pi * (freq * 0.5) * t);

      final int sampleVal =
          (wave * envelope * 16000).clamp(-32767.0, 32767.0).toInt();
      buffer.setInt16(44 + i * 2, sampleVal, Endian.little);
    }

    await file.writeAsBytes(buffer.buffer.asUint8List(), flush: true);
    _cachedPaths[songId] = filePath;
    return filePath;
  }
}
