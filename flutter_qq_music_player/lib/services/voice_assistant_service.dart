import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

/// 双向语音交互服务：支持麦克风实时语音唤醒/听写 (STT) 与 AI 语音情感播报 (TTS)
class VoiceAssistantService {
  final stt.SpeechToText _speech = stt.SpeechToText();
  final FlutterTts _tts = FlutterTts();
  bool isListening = false;
  bool ttsEnabled = true;

  Future<bool> initVoiceEngine() async {
    await _tts.setLanguage('zh-CN');
    await _tts.setSpeechRate(0.5);
    await _tts.setPitch(1.0);
    return _speech.initialize();
  }

  /// 开始麦克风语音识别（支持中文普通话与中英混合歌名识别）
  Future<void> startListening({
    required void Function(String recognizedWords, bool isFinal) onResult,
  }) async {
    final available = await _speech.initialize();
    if (!available) return;
    isListening = true;
    await _speech.listen(
      localeId: 'zh_CN',
      onResult: (result) {
        onResult(result.recognizedWords, result.finalResult);
      },
    );
  }

  Future<void> stopListening() async {
    isListening = false;
    await _speech.stop();
  }

  /// 朗读大模型回复内容
  Future<void> speakReply(String text) async {
    if (!ttsEnabled || text.trim().isEmpty) return;
    await _tts.stop();
    await _tts.speak(text);
  }

  Future<void> stopSpeaking() async {
    await _tts.stop();
  }
}
