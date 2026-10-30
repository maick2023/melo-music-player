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

  /// 向兼容 OpenAI /chat/completions 规范的大模型接口发送多轮对话请求
  /// 支持回答任何领域的知识、日常聊天、写文章、写代码、翻译、逻辑推理，同时兼备语音点歌控制能力
  Future<String> chatWithModel({
    required String userMessage,
    required String currentSongSummary,
    required List<String> localSongTitles,
    List<Map<String, String>> historyMessages = const [],
  }) async {
    if (apiKey.trim().isEmpty) {
      await loadSavedConfig();
    }
    if (apiKey.trim().isEmpty) {
      return _offlineSmartFallback(userMessage, currentSongSummary);
    }

    final systemPrompt = '''
你是一个全能型人工智能助手（同时也是“悦听 MeloMusic”播放器的智能管家）。
你可以和用户自由畅聊任何话题、回答任何领域的问题（包括但不限于：日常交流、百科常识、新闻分析、工作写作、翻译、数学逻辑推理、编程代码、生活建议、情感陪伴、音乐鉴赏等），请给出详尽、自然、有深度的回答，不限制回答字数。

【可选的播放器控制指令（仅当用户明确要求操控音乐时才使用）】：
当前播放器状态：$currentSongSummary。用户曲库部分歌曲：${localSongTitles.take(15).join('、')}。
- 只有当用户明确说出“我想听xxx歌”、“播放歌曲xxx”、“来一首xxx”等点歌指令时，才在回复的第一行单独输出：[PLAY_SONG:歌名或歌手]，第二行开始正常回复用户。
- 只有当用户明确说“下一首/切歌”时，第一行输出：[ACTION:NEXT]
- 只有当用户明确说“上一首”时，第一行输出：[ACTION:PREV]
- 只有当用户明确说“暂停播放/停止放歌”时，第一行输出：[ACTION:PAUSE]
- 只有当用户明确说“切换到黑胶模式/大图模式/流光卡片模式”时，第一行输出：[STYLE:VINYL] 或 [STYLE:FULLSCREEN] 或 [STYLE:GLASS]
- 如果用户是在和你聊天、提问、探讨问题（而不是点歌或控制播放器），请【绝对不要】输出任何方括号指令标签，直接像满血大模型一样自由、完整地回答用户的问题！
''';

    // 组装多轮对话上下文（保留最近 10 轮对话，支持连续追问与深入交流）
    final List<Map<String, String>> apiMessages = [
      {'role': 'system', 'content': systemPrompt},
    ];
    final recentHistory = historyMessages.length > 10
        ? historyMessages.sublist(historyMessages.length - 10)
        : historyMessages;
    for (final m in recentHistory) {
      final role = m['role'] == 'user' ? 'user' : 'assistant';
      final text = (m['text'] ?? '').trim();
      if (text.isNotEmpty) {
        apiMessages.add({'role': role, 'content': text});
      }
    }
    if (apiMessages.last['role'] != 'user' ||
        apiMessages.last['content'] != userMessage.trim()) {
      apiMessages.add({'role': 'user', 'content': userMessage.trim()});
    }

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
                  'messages': apiMessages,
                  'temperature': 0.7,
                  'max_tokens': 4096,
                }),
              )
              .timeout(const Duration(seconds: 60));

          if (response.statusCode == 200) {
            final decoded = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
            final choices = decoded['choices'] as List<dynamic>?;
            if (choices != null && choices.isNotEmpty) {
              final msg = choices.first['message'] as Map<String, dynamic>?;
              String content = msg?['content']?.toString().trim() ?? '';
              if (content.isEmpty) {
                content = msg?['reasoning_content']?.toString().trim() ?? '';
              }
              if (content.isNotEmpty) {
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
    if (text == '下一首' || text == '切歌' || text == '换一首') {
      return '[ACTION:NEXT]\n好的，马上为您切换到下一首歌曲！';
    }
    if (text == '上一首') {
      return '[ACTION:PREV]\n好的，已为您切回上一首歌曲。';
    }
    if (text == '暂停' || text == '停止播放' || text == '别唱了') {
      return '[ACTION:PAUSE]\n好的，音乐已暂停。';
    }
    if (text.startsWith('我想听') || text.startsWith('播放') || text.startsWith('来一首')) {
      final keyword = text
          .replaceAll(RegExp(r'^(我想听|帮我播放|播放|来一首)'), '')
          .trim();
      if (keyword.isNotEmpty) {
        return '[PLAY_SONG:$keyword]\n没问题，正在为您全网搜索并播放《$keyword》！';
      }
    }
    return '⚠️ 您尚未保存大模型 API Key（或 Key 为空），当前处于离线状态，无法联网回答您的提问：「$text」。\n\n👉 请点击右上角「配置大模型 API」，点击「📋 一键粘贴 Key」填入您的火山引擎 / DeepSeek / 通义千问 API Key，即可与大模型自由聊天、探讨任何问题！';
  }
}
