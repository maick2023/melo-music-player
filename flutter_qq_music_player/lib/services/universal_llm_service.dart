import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AiPlayerCommand {
  final String action;
  final String? targetQuery;
  final String replyText;

  const AiPlayerCommand({
    required this.action,
    this.targetQuery,
    this.replyText = '',
  });
}

class QuickModelOption {
  final String label;
  final String modelId;
  const QuickModelOption(this.label, this.modelId);
}

class LlmProviderPreset {
  final String id;
  final String name;
  final String defaultBaseUrl;
  final String defaultModel;
  final String hint;
  final List<QuickModelOption> quickModels;

  String get baseUrl => defaultBaseUrl;
  String get description => hint;

  const LlmProviderPreset({
    required this.id,
    required this.name,
    required this.defaultBaseUrl,
    required this.defaultModel,
    required this.hint,
    this.quickModels = const [],
  });

  static List<LlmProviderPreset> get builtinProviders => UniversalLlmService.presets;
}

class UniversalLlmService {
  static const List<LlmProviderPreset> presets = [
    LlmProviderPreset(
      id: 'volcengine',
      name: '火山引擎 (火山方舟)',
      defaultBaseUrl: 'https://ark.cn-beijing.volces.com/api/v3',
      defaultModel: 'doubao-seed-evolving',
      hint: '已严格对应你火山方舟「开通管理」中的 7 款已开通模型，点击下方按钮即可自动填入官方 Model ID',
      quickModels: [
        QuickModelOption('Doubao-Seed-Evolving (推荐)', 'doubao-seed-evolving'),
        QuickModelOption('Doubao-Seed-2.1-turbo', 'doubao-seed-2-1-turbo-260628'),
        QuickModelOption('Doubao-Seed-2.0-mini', 'doubao-seed-2-0-mini-260428'),
        QuickModelOption('Doubao-Seed-2.1-lite', 'doubao-seed-2-1-lite-260915'),
        QuickModelOption('DeepSeek-V4.1-Flash', 'deepseek-v4-1-flash-261017'),
        QuickModelOption('DeepSeek-V4.1-Flash经济版', 'deepseek-v4-1-flash-economy-261017'),
        QuickModelOption('GLM-5.3-Flash', 'glm-5-3-flash-260828'),
      ],
    ),
    LlmProviderPreset(
      id: 'deepseek',
      name: 'DeepSeek (深度求索官方)',
      defaultBaseUrl: 'https://api.deepseek.com/v1',
      defaultModel: 'deepseek-chat',
      hint: '支持 deepseek-chat 与 deepseek-reasoner',
      quickModels: [
        QuickModelOption('DeepSeek-Chat', 'deepseek-chat'),
        QuickModelOption('DeepSeek-Reasoner', 'deepseek-reasoner'),
      ],
    ),
    LlmProviderPreset(
      id: 'qwen',
      name: '阿里通义千问 (Qwen)',
      defaultBaseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
      defaultModel: 'qwen-plus',
      hint: '支持 qwen-max / qwen-plus / qwen-turbo',
      quickModels: [
        QuickModelOption('Qwen-Plus', 'qwen-plus'),
        QuickModelOption('Qwen-Max', 'qwen-max'),
        QuickModelOption('Qwen-Turbo', 'qwen-turbo'),
      ],
    ),
    LlmProviderPreset(
      id: 'openai',
      name: 'OpenAI (GPT 系列)',
      defaultBaseUrl: 'https://api.openai.com/v1',
      defaultModel: 'gpt-4o-mini',
      hint: '支持 gpt-4o / gpt-4o-mini / o3-mini',
      quickModels: [
        QuickModelOption('GPT-4o-mini', 'gpt-4o-mini'),
        QuickModelOption('GPT-4o', 'gpt-4o'),
      ],
    ),
    LlmProviderPreset(
      id: 'gemini',
      name: 'Google Gemini',
      defaultBaseUrl: 'https://generativelanguage.googleapis.com/v1beta/openai',
      defaultModel: 'gemini-2.5-flash',
      hint: '支持 gemini-2.5-flash / gemini-2.5-pro',
      quickModels: [
        QuickModelOption('Gemini 2.5 Flash', 'gemini-2.5-flash'),
        QuickModelOption('Gemini 2.5 Pro', 'gemini-2.5-pro'),
      ],
    ),
    LlmProviderPreset(
      id: 'meta_llama',
      name: 'Meta Llama / OpenRouter',
      defaultBaseUrl: 'https://api.groq.com/openai/v1',
      defaultModel: 'llama-3.3-70b-versatile',
      hint: '支持 Groq / OpenRouter / Ollama 等任何 OpenAI 兼容接口',
      quickModels: [
        QuickModelOption('Llama 3.3 70B', 'llama-3.3-70b-versatile'),
        QuickModelOption('Llama 3.1 8B', 'llama-3.1-8b-instant'),
      ],
    ),
  ];

  /// 将火山方舟控制台展示名称（如 Doubao-Seed-2.1-turbo、DeepSeek-V4.1-Flash经济版）
  /// 自动转换为火山引擎 API 调用必填的小写带日期版本号 Model ID
  static String normalizeVolcengineModelId(String rawModel) {
    final trimmed = rawModel.trim();
    final lower = trimmed.toLowerCase();

    const Map<String, String> displayToApiModelMap = {
      'doubao-seed-evolving': 'doubao-seed-evolving',
      'doubao-seed-2.1-turbo': 'doubao-seed-2-1-turbo-260628',
      'doubao-seed-2-1-turbo': 'doubao-seed-2-1-turbo-260628',
      'doubao-seed-2.0-mini': 'doubao-seed-2-0-mini-260428',
      'doubao-seed-2-0-mini': 'doubao-seed-2-0-mini-260428',
      'doubao-seed-2.1-lite': 'doubao-seed-2-1-lite-260915',
      'doubao-seed-2-1-lite': 'doubao-seed-2-1-lite-260915',
      'doubao-seed-2.1-pro': 'doubao-seed-2-1-pro-260915',
      'doubao-seed-2-1-pro': 'doubao-seed-2-1-pro-260915',
      'doubao-seed-2.0-lite': 'doubao-seed-2-0-lite-260428',
      'doubao-seed-2-0-lite': 'doubao-seed-2-0-lite-260428',
      'deepseek-v4.1-flash经济版': 'deepseek-v4-1-flash-economy-261017',
      'deepseek-v4.1-flash-economy': 'deepseek-v4-1-flash-economy-261017',
      'deepseek-v4-1-flash-economy': 'deepseek-v4-1-flash-economy-261017',
      'deepseek-v4.1-flash': 'deepseek-v4-1-flash-261017',
      'deepseek-v4-1-flash': 'deepseek-v4-1-flash-261017',
      'deepseek-v4-flash': 'deepseek-v4-flash-ga-260731',
      'deepseek-v4-pro': 'deepseek-v4-pro-ga-260813',
      'glm-5.3-flash': 'glm-5-3-flash-260828',
      'glm-5-3-flash': 'glm-5-3-flash-260828',
      'doubao-pro-32k': 'doubao-seed-evolving',
      'doubao-1-5-pro-32k-250115': 'doubao-seed-evolving',
    };

    if (displayToApiModelMap.containsKey(lower)) {
      return displayToApiModelMap[lower]!;
    }
    return trimmed;
  }

  String providerId = 'volcengine';
  String baseUrl = 'https://ark.cn-beijing.volces.com/api/v3';
  String apiKey = '';
  String modelName = 'doubao-seed-evolving';
  bool enableVoiceTts = true;

  Future<void> loadSavedConfig() async {
    final prefs = await SharedPreferences.getInstance();
    providerId = prefs.getString('llm_provider_id') ?? 'volcengine';
    baseUrl = prefs.getString('llm_base_url') ?? 'https://ark.cn-beijing.volces.com/api/v3';
    apiKey = prefs.getString('llm_api_key') ?? '';
    String savedModel = prefs.getString('llm_model_name') ?? 'doubao-seed-evolving';
    if (providerId == 'volcengine' || baseUrl.contains('volces.com')) {
      savedModel = normalizeVolcengineModelId(savedModel);
    }
    modelName = savedModel;
    enableVoiceTts = prefs.getBool('llm_voice_tts') ?? true;
  }

  Future<void> saveConfig({
    required String providerId,
    required String baseUrl,
    required String apiKey,
    required String modelName,
    bool enableVoiceTts = true,
  }) async {
    this.providerId = providerId;
    this.baseUrl = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    this.apiKey = apiKey.trim();
    String cleanedModel = modelName.trim();
    if (providerId == 'volcengine' || this.baseUrl.contains('volces.com')) {
      cleanedModel = normalizeVolcengineModelId(cleanedModel);
    }
    this.modelName = cleanedModel;
    this.enableVoiceTts = enableVoiceTts;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('llm_provider_id', this.providerId);
    await prefs.setString('llm_base_url', this.baseUrl);
    await prefs.setString('llm_api_key', this.apiKey);
    await prefs.setString('llm_model_name', this.modelName);
    await prefs.setBool('llm_voice_tts', this.enableVoiceTts);
  }

  /// 向兼容 OpenAI /chat/completions 规范的大模型接口发送请求
  /// 针对火山引擎，自动兼容标准方舟端点 (/api/v3) 与订阅套餐端点 (/api/plan/v3)，
  /// 并自动轮询你在「开通管理」中已开通的全部 7 个模型 ID
  Future<String> chatWithModel({
    required String userMessage,
    required String currentSongSummary,
    required List<String> localSongTitles,
  }) async {
    if (apiKey.isEmpty) {
      return _offlineSmartFallback(userMessage, currentSongSummary);
    }

    final systemPrompt = '''
你是“悦听 (MeloMusic)”跨平台音乐播放器的内置 AI 音乐伴侣与语音助手。
当前正在播放：$currentSongSummary。
用户本地曲库部分歌曲：${localSongTitles.take(12).join('、')}。

重要规则：
1. 如果用户表达了“我想听xxx”、“播放xxx”、“搜一下xxx”等点歌意图，请在回复的第一行输出指令标签：[PLAY_SONG:歌名或歌手]，然后再用温暖简短的中文回应用户。
2. 如果用户说“下一首/切歌”，第一行输出：[ACTION:NEXT]
3. 如果用户说“上一首”，第一行输出：[ACTION:PREV]
4. 如果用户说“暂停/停止播放”，第一行输出：[ACTION:PAUSE]
5. 如果用户说“切换到黑胶/大图/流光卡片”，第一行输出：[STYLE:VINYL] 或 [STYLE:FULLSCREEN] 或 [STYLE:GLASS]
6. 其余音乐闲聊、歌词赏析或歌手故事，请直接用亲切精炼的中文回答（控制在 100 字以内，适合语音朗读）。
''';

    final bool isVolc = baseUrl.contains('volces.com') || providerId == 'volcengine';
    final String primaryModel = isVolc ? normalizeVolcengineModelId(modelName) : modelName;

    final List<String> candidateModels = [primaryModel];
    if (isVolc) {
      for (final m in [
        'doubao-seed-evolving',
        'doubao-seed-2-1-turbo-260628',
        'doubao-seed-2-0-mini-260428',
        'doubao-seed-2-1-lite-260915',
        'deepseek-v4-1-flash-261017',
        'deepseek-v4-1-flash-economy-261017',
        'glm-5-3-flash-260828',
      ]) {
        if (!candidateModels.contains(m)) candidateModels.add(m);
      }
    }

    final normalizedBase = baseUrl.replaceAll(RegExp(r'/+$'), '');
    final List<String> candidateBases = [normalizedBase];
    if (isVolc) {
      if (!candidateBases.contains('https://ark.cn-beijing.volces.com/api/v3')) {
        candidateBases.add('https://ark.cn-beijing.volces.com/api/v3');
      }
      if (!candidateBases.contains('https://ark.cn-beijing.volces.com/api/plan/v3')) {
        candidateBases.add('https://ark.cn-beijing.volces.com/api/plan/v3');
      }
    }

    String lastErrorDetail = '';
    int lastStatusCode = 0;

    for (final baseCandidate in candidateBases) {
      for (final candidateModel in candidateModels) {
        try {
          final endpoint = baseCandidate.endsWith('/chat/completions')
              ? Uri.parse(baseCandidate)
              : Uri.parse('$baseCandidate/chat/completions');

          final response = await http
              .post(
                endpoint,
                headers: {
                  'Content-Type': 'application/json; charset=utf-8',
                  'Authorization': 'Bearer $apiKey',
                },
                body: jsonEncode({
                  'model': candidateModel,
                  'messages': [
                    {'role': 'system', 'content': systemPrompt},
                    {'role': 'user', 'content': userMessage},
                  ],
                  'temperature': 0.7,
                  'max_tokens': 400,
                }),
              )
              .timeout(const Duration(seconds: 20));

          if (response.statusCode == 200) {
            final decoded = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
            final choices = decoded['choices'] as List<dynamic>?;
            if (choices != null && choices.isNotEmpty) {
              final msg = choices.first['message'] as Map<String, dynamic>?;
              final content = msg?['content']?.toString().trim();
              if (content != null && content.isNotEmpty) {
                final prefs = await SharedPreferences.getInstance();
                if (candidateModel != modelName) {
                  modelName = candidateModel;
                  await prefs.setString('llm_model_name', candidateModel);
                }
                if (baseCandidate != baseUrl) {
                  baseUrl = baseCandidate;
                  await prefs.setString('llm_base_url', baseCandidate);
                }
                return content;
              }
            }
          }

          lastStatusCode = response.statusCode;
          try {
            final errJson = jsonDecode(utf8.decode(response.bodyBytes));
            lastErrorDetail = errJson['error']?['message']?.toString() ??
                errJson['message']?.toString() ??
                '';
          } catch (_) {
            lastErrorDetail = utf8.decode(response.bodyBytes);
          }

          if (response.statusCode != 404 && response.statusCode != 400) {
            break;
          }
        } catch (e) {
          lastErrorDetail = e.toString();
          break;
        }
      }
    }

    if (lastStatusCode == 401 || lastStatusCode == 403) {
      return 'API 鉴权失败 (状态码 $lastStatusCode)：请检查你粘贴的 API Key 是否完整、有没有多余空格。\n详情：$lastErrorDetail';
    }
    if (lastStatusCode == 404) {
      return 'API 返回 404 (模型未找到)：\n请确认模型名称填写为火山方舟官方 Model ID（如 doubao-seed-evolving 或 doubao-seed-2-1-turbo-260628）。\n原始响应：$lastErrorDetail';
    }
    return 'API 请求异常 (状态码 $lastStatusCode)：$lastErrorDetail';
  }

  String _offlineSmartFallback(String userMessage, String currentSongSummary) {
    final text = userMessage.trim();
    if (text.contains('下一首') || text.contains('切歌') || text.contains('换一首')) {
      return '[ACTION:NEXT]\n好的，马上为您切换到下一首歌曲！';
    }
    if (text.contains('上一首')) {
      return '[ACTION:PREV]\n好的，已为您切回上一首歌曲。';
    }
    if (text.contains('暂停') || text.contains('停止') || text.contains('别唱了')) {
      return '[ACTION:PAUSE]\n好的，音乐已暂停。';
    }
    if (text.contains('流光') || text.contains('卡片')) {
      return '[STYLE:GLASS]\n已为您切换至流光毛玻璃卡片播放页！';
    }
    if (text.contains('大图') || text.contains('海报')) {
      return '[STYLE:FULLSCREEN]\n已为您切换至沉浸式海报大图模式！';
    }
    if (text.contains('黑胶') || text.contains('唱针')) {
      return '[STYLE:VINYL]\n已为您切换至经典黑胶唱针模式！';
    }
    if (text.contains('我想听') || text.contains('播放') || text.contains('来一首') || text.contains('搜')) {
      final keyword = text
          .replaceAll(RegExp(r'(我想听|帮我播放|播放|来一首|搜索|搜一下|的歌)'), '')
          .trim();
      if (keyword.isNotEmpty) {
        return '[PLAY_SONG:$keyword]\n没问题，正在为您全网搜索并播放《$keyword》！';
      }
    }
    return '当前正在播放：$currentSongSummary。\n（提示：您尚未填入大模型 API Key，目前运行在本地离线语音管家模式。点击右上角“配置 API”填入您的火山引擎/DeepSeek/千问 Key 即可开启满血 AI 对话！）';
  }
}
