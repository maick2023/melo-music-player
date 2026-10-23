import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// 预设大模型服务商配置模板（兼容所有 OpenAI 格式接口及 Gemini/Claude/自定义网关）
class LlmProviderPreset {
  final String id;
  final String name;
  final String baseUrl;
  final String defaultModel;
  final String description;

  const LlmProviderPreset({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.defaultModel,
    required this.description,
  });

  static const List<LlmProviderPreset> builtinProviders = [
    LlmProviderPreset(
      id: 'deepseek',
      name: 'DeepSeek (深度求索)',
      baseUrl: 'https://api.deepseek.com/v1',
      defaultModel: 'deepseek-chat',
      description: '官方兼容 OpenAI 协议，支持 deepseek-chat (V3) 与 deepseek-reasoner (R1)',
    ),
    LlmProviderPreset(
      id: 'volcengine',
      name: '火山引擎 (豆包大模型)',
      baseUrl: 'https://ark.cn-beijing.volces.com/api/v3',
      defaultModel: 'doubao-pro-32k',
      description: '火山方舟大模型平台，可填入推理接入点 ID (ep-xxxx) 或模型名称',
    ),
    LlmProviderPreset(
      id: 'qwen',
      name: '阿里通义千问 (Qwen)',
      baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
      defaultModel: 'qwen-plus',
      description: '阿里云百炼 DashScope 兼容接口，支持 qwen-max / qwen-plus / qwen-turbo',
    ),
    LlmProviderPreset(
      id: 'openai',
      name: 'OpenAI (GPT 系列)',
      baseUrl: 'https://api.openai.com/v1',
      defaultModel: 'gpt-4o-mini',
      description: '支持 GPT-4o、GPT-4.1 及所有兼容 OpenAI 格式的中转站',
    ),
    LlmProviderPreset(
      id: 'gemini',
      name: 'Google Gemini',
      baseUrl: 'https://generativelanguage.googleapis.com/v1beta/openai',
      defaultModel: 'gemini-2.5-flash',
      description: 'Google 官方 OpenAI 兼容端点，支持 Gemini 2.5 Pro / Flash',
    ),
    LlmProviderPreset(
      id: 'meta_llama',
      name: 'Meta Llama (Groq / OpenRouter / Ollama)',
      baseUrl: 'https://api.groq.com/openai/v1',
      defaultModel: 'llama-3.3-70b-versatile',
      description: '支持 Meta Llama 3.3 及任何自建或第三方 OpenAI 兼容网关',
    ),
  ];
}

/// AI 解析出的播放器控制指令（实现语音/对话直接操控播放器）
class AiPlayerCommand {
  final String action; // 'play_search', 'pause', 'resume', 'next', 'prev', 'set_eq', 'switch_style', 'none'
  final String? targetQuery;
  final String replyText;

  const AiPlayerCommand({
    required this.action,
    required this.replyText,
    this.targetQuery,
  });
}

/// 全能大模型网关服务：支持切换任意大模型 API 并返回结构化音乐控制指令与乐评问答
class UniversalLlmService {
  String providerId = 'deepseek';
  String baseUrl = 'https://api.deepseek.com/v1';
  String apiKey = '';
  String modelName = 'deepseek-chat';

  Future<void> loadSavedConfig() async {
    final prefs = await SharedPreferences.getInstance();
    providerId = prefs.getString('llm_provider_id') ?? 'deepseek';
    baseUrl = prefs.getString('llm_base_url') ?? 'https://api.deepseek.com/v1';
    apiKey = prefs.getString('llm_api_key') ?? '';
    modelName = prefs.getString('llm_model_name') ?? 'deepseek-chat';
  }

  Future<void> saveConfig({
    required String providerId,
    required String baseUrl,
    required String apiKey,
    required String modelName,
  }) async {
    this.providerId = providerId;
    this.baseUrl = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    this.apiKey = apiKey.trim();
    this.modelName = modelName.trim();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('llm_provider_id', this.providerId);
    await prefs.setString('llm_base_url', this.baseUrl);
    await prefs.setString('llm_api_key', this.apiKey);
    await prefs.setString('llm_model_name', this.modelName);
  }

  /// 向当前配置的大模型发送用户消息（含当前正在播放的歌曲上下文），并解析返回文本与播放器控制指令
  Future<AiPlayerCommand> sendChatWithMusicIntent({
    required String userText,
    required String currentSongSummary,
  }) async {
    final systemPrompt = '''
你是“悦听 (MeloMusic)”跨平台无损音乐播放器的内置 AI 音乐伴侣与智能语音管家。
当前正在播放的音乐状态：$currentSongSummary。
你可以陪用户聊音乐故事、鉴赏歌词、按心情推荐歌单，也可以根据用户的意图直接控制播放器。
如果用户的意图包含操控播放器（例如点歌、切歌、暂停、换音效、切换黑胶/大图/流光卡片样式），请在回答末尾附带一行 JSON 指令标签（如无控制意图则只回答自然语言）：
[ACTION:{"action":"play_search|next|prev|pause|resume|set_eq|switch_style","query":"歌曲名或参数"}]
回答请保持温暖、精炼、适合语音播报（控制在 80 字以内）。
''';

    if (apiKey.isEmpty) {
      return _localFallbackIntentParser(userText);
    }

    try {
      final endpoint = Uri.parse('$baseUrl/chat/completions');
      final response = await http
          .post(
            endpoint,
            headers: {
              'Content-Type': 'application/json; charset=utf-8',
              'Authorization': 'Bearer $apiKey',
            },
            body: jsonEncode({
              'model': modelName,
              'messages': [
                {'role': 'system', 'content': systemPrompt},
                {'role': 'user', 'content': userText},
              ],
              'temperature': 0.7,
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final body = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        final choices = body['choices'] as List<dynamic>?;
        final content = (choices != null && choices.isNotEmpty)
            ? (choices.first['message']['content'] as String? ?? '')
            : '';
        return _extractCommandFromReply(content, userText);
      } else {
        return AiPlayerCommand(
          action: 'none',
          replyText: 'API 请求返回状态码 ${response.statusCode}，请检查 API Key、Base URL 或模型名称（如火山引擎需填写推理接入点 ep-xxxx）。',
        );
      }
    } catch (e) {
      return _localFallbackIntentParser(userText);
    }
  }

  AiPlayerCommand _extractCommandFromReply(String rawReply, String userText) {
    final reg = RegExp(r'\[ACTION:(\{.*?\})\]');
    final match = reg.firstMatch(rawReply);
    final cleanReply = rawReply.replaceAll(reg, '').trim();
    if (match != null) {
      try {
        final map = jsonDecode(match.group(1)!) as Map<String, dynamic>;
        return AiPlayerCommand(
          action: (map['action'] as String?) ?? 'none',
          targetQuery: map['query'] as String?,
          replyText: cleanReply,
        );
      } catch (_) {}
    }
    return AiPlayerCommand(action: 'none', replyText: cleanReply);
  }

  /// 当未配置 API Key 或离线状态时的本地智能意图兜底解析
  AiPlayerCommand _localFallbackIntentParser(String text) {
    final t = text.trim();
    if (t.contains('下一首') || t.contains('切歌') || t.contains('换一首')) {
      return const AiPlayerCommand(
        action: 'next',
        replyText: '好的，马上为您切换到下一首歌曲。',
      );
    }
    if (t.contains('上一首')) {
      return const AiPlayerCommand(
        action: 'prev',
        replyText: '好的，已为您切回上一首歌曲。',
      );
    }
    if (t.contains('暂停') || t.contains('停止') || t.contains('别唱了')) {
      return const AiPlayerCommand(
        action: 'pause',
        replyText: '已为您暂停播放。',
      );
    }
    if (t.contains('黑胶') || t.contains('大图') || t.contains('卡片')) {
      final style = t.contains('大图')
          ? 'fullscreen'
          : (t.contains('卡片') ? 'glass' : 'vinyl');
      return AiPlayerCommand(
        action: 'switch_style',
        targetQuery: style,
        replyText: '已为您切换播放页视觉样式。',
      );
    }
    if (t.contains('我想听') || t.contains('播放') || t.contains('来一首') || t.contains('搜')) {
      final query = t
          .replaceAll(RegExp(r'(我想听|帮我找|播放|来一首|搜索|的歌|歌曲)'), '')
          .trim();
      final finalQuery = query.isEmpty ? '周杰伦' : query;
      return AiPlayerCommand(
        action: 'play_search',
        targetQuery: finalQuery,
        replyText: '没问题，正在为您全网检索并播放「$finalQuery」！',
      );
    }
    return const AiPlayerCommand(
      action: 'none',
      replyText: '我已准备好连接您的 DeepSeek / 火山引擎 / 通义千问 / GPT / Gemini / Llama API，您可以直接语音对我说“我想听稻香”、“下一首”或询问歌词背景故事！',
    );
  }
}
