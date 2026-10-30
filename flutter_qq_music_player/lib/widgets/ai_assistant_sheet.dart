import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';
import '../services/audio_player_service.dart';
import '../services/universal_llm_service.dart';
import '../models/song_model.dart';

class AiAssistantSheet extends ConsumerStatefulWidget {
  final String? currentSongSummary;
  final void Function(AiPlayerCommand cmd)? onExecuteCommand;

  const AiAssistantSheet({
    super.key,
    this.currentSongSummary,
    this.onExecuteCommand,
  });

  @override
  ConsumerState<AiAssistantSheet> createState() => _AiAssistantSheetState();
}

class _AiAssistantSheetState extends ConsumerState<AiAssistantSheet> {
  final UniversalLlmService _llm = UniversalLlmService();
  final stt.SpeechToText _speech = stt.SpeechToText();
  final FlutterTts _tts = FlutterTts();
  final ScrollController _scrollCtrl = ScrollController();
  final TextEditingController _chatCtrl = TextEditingController();
  final TextEditingController _baseUrlCtrl = TextEditingController();
  final TextEditingController _apiKeyCtrl = TextEditingController();
  final TextEditingController _modelCtrl = TextEditingController();

  bool _showConfigPanel = false;
  bool _isListening = false;
  bool _isLoadingReply = false;
  bool _isTestingApi = false;
  bool _obscureApiKey = false;

  List<Map<String, String>> _messages = [
    {
      'role': 'ai',
      'text': '你好！我是接入大模型的全能 AI 助手（兼智能音乐管家）。\n• 你可以问我任何问题（日常聊天、百科常识、工作写作、翻译、编程代码等）；\n• 也可以随时对我说“播放xxx”、“下一首”、“切换到黑胶模式”来操控播放器！',
    }
  ];

  @override
  void initState() {
    super.initState();
    _initConfigAndSpeech();
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    _chatCtrl.dispose();
    _baseUrlCtrl.dispose();
    _apiKeyCtrl.dispose();
    _modelCtrl.dispose();
    super.dispose();
  }

  Future<void> _initConfigAndSpeech() async {
    await _llm.loadSavedConfig();
    _baseUrlCtrl.text = _llm.baseUrl;
    _apiKeyCtrl.text = _llm.apiKey;
    _modelCtrl.text = _llm.modelName;

    final prefs = await SharedPreferences.getInstance();
    final savedChat = prefs.getString('saved_ai_chat_history_v1');
    if (savedChat != null && savedChat.isNotEmpty) {
      try {
        final decoded = jsonDecode(savedChat) as List<dynamic>;
        final loaded = decoded
            .whereType<Map<String, dynamic>>()
            .map((m) => {
                  'role': (m['role'] as String?) ?? 'ai',
                  'text': (m['text'] as String?) ?? '',
                })
            .toList();
        if (loaded.isNotEmpty) {
          _messages = loaded;
        }
      } catch (_) {}
    }

    await _tts.setLanguage('zh-CN');
    await _tts.setSpeechRate(0.5);
    if (mounted) {
      setState(() {});
      _scrollToBottom();
    }
  }

  Future<void> _saveChatHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final tail = _messages.length > 30
          ? _messages.sublist(_messages.length - 30)
          : _messages;
      await prefs.setString('saved_ai_chat_history_v1', jsonEncode(tail));
    } catch (_) {}
  }

  Future<void> _syncAndSaveConfig() async {
    await _llm.saveConfig(
      providerId: _llm.providerId,
      baseUrl: _baseUrlCtrl.text,
      apiKey: _apiKeyCtrl.text,
      modelName: _modelCtrl.text,
      enableVoiceTts: _llm.enableVoiceTts,
    );
    _modelCtrl.text = _llm.modelName;
    _baseUrlCtrl.text = _llm.baseUrl;
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _pasteIntoController(
    TextEditingController ctrl,
    String fieldLabel,
  ) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) {
      if (!mounted) return;
      _showResultDialog(
        '剪贴板为空',
        '手机剪贴板里还没有内容，请先去复制 $fieldLabel 再点击「一键粘贴」。',
        isSuccess: false,
      );
      return;
    }
    setState(() {
      ctrl.text = text;
      ctrl.selection =
          TextSelection.fromPosition(TextPosition(offset: ctrl.text.length));
    });
    await _syncAndSaveConfig();
  }

  void _showResultDialog(
    String title,
    String message, {
    required bool isSuccess,
  }) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF162230),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            Icon(
              isSuccess
                  ? Icons.check_circle_rounded
                  : Icons.error_outline_rounded,
              color: isSuccess ? const Color(0xFF00D676) : Colors.amberAccent,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Text(
            message,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 13,
              height: 1.5,
            ),
          ),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00D676),
              foregroundColor: Colors.black,
            ),
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              '知道了',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleVoiceInput() async {
    if (_isListening) {
      await _speech.stop();
      setState(() => _isListening = false);
      return;
    }
    final available = await _speech.initialize(
      onStatus: (status) {
        if (status == 'done' || status == 'notListening') {
          if (mounted) setState(() => _isListening = false);
        }
      },
      onError: (_) {
        if (mounted) setState(() => _isListening = false);
      },
    );
    if (available) {
      setState(() => _isListening = true);
      _speech.listen(
        localeId: 'zh_CN',
        onResult: (result) {
          setState(() {
            _chatCtrl.text = result.recognizedWords;
          });
          if (result.finalResult &&
              result.recognizedWords.trim().isNotEmpty) {
            _sendMessage(result.recognizedWords.trim());
          }
        },
      );
    } else {
      _showResultDialog(
        '需要麦克风权限',
        '无法启动手机语音识别，请在手机设置中授予麦克风权限。',
        isSuccess: false,
      );
    }
  }

  Future<void> _sendMessage(String rawText) async {
    final text = rawText.trim();
    if (text.isEmpty || _isLoadingReply) return;
    _chatCtrl.clear();
    FocusScope.of(context).unfocus();

    // 每次发消息前自动同步保存一次配置面板中的 Key 与模型，防止填了 Key 没点保存
    if (_apiKeyCtrl.text.trim().isNotEmpty) {
      await _syncAndSaveConfig();
    }

    final historySnapshot = List<Map<String, String>>.from(_messages);

    setState(() {
      _messages.add({'role': 'user', 'text': text});
      _isLoadingReply = true;
    });
    _scrollToBottom();

    final playerState = ref.read(audioPlayerProvider);
    final notifier = ref.read(audioPlayerProvider.notifier);
    final curSong = playerState.currentSong;
    final songSummary = curSong != null
        ? '《${curSong.title}》- ${curSong.artist}'
        : '当前未播放歌曲';

    final reply = await _llm.chatWithModel(
      userMessage: text,
      currentSongSummary: songSummary,
      localSongTitles: playerState.allSongs.map((s) => s.title).toList(),
      historyMessages: historySnapshot,
    );

    String cleanReply = reply.trim();
    if (cleanReply.startsWith('[ACTION:NEXT]')) {
      notifier.nextSong();
      cleanReply = cleanReply.replaceFirst('[ACTION:NEXT]', '').trim();
    } else if (cleanReply.startsWith('[ACTION:PREV]')) {
      notifier.previousSong();
      cleanReply = cleanReply.replaceFirst('[ACTION:PREV]', '').trim();
    } else if (cleanReply.startsWith('[ACTION:PAUSE]')) {
      if (playerState.isPlaying) notifier.togglePlayPause();
      cleanReply = cleanReply.replaceFirst('[ACTION:PAUSE]', '').trim();
    } else if (cleanReply.startsWith('[STYLE:VINYL]')) {
      notifier.setVisualStyle(PlayerVisualStyle.vinyl);
      cleanReply = cleanReply.replaceFirst('[STYLE:VINYL]', '').trim();
    } else if (cleanReply.startsWith('[STYLE:FULLSCREEN]')) {
      notifier.setVisualStyle(PlayerVisualStyle.fullscreen);
      cleanReply = cleanReply.replaceFirst('[STYLE:FULLSCREEN]', '').trim();
    } else if (cleanReply.startsWith('[STYLE:GLASS]')) {
      notifier.setVisualStyle(PlayerVisualStyle.glassCard);
      cleanReply = cleanReply.replaceFirst('[STYLE:GLASS]', '').trim();
    } else if (cleanReply.startsWith('[PLAY_SONG:')) {
      final endIdx = cleanReply.indexOf(']');
      if (endIdx != -1) {
        final keyword = cleanReply.substring(11, endIdx).trim();
        cleanReply = cleanReply.substring(endIdx + 1).trim();
        if (cleanReply.isEmpty) {
          cleanReply = '正在为您全网搜索并播放《$keyword》！';
        }
        final results = await notifier.searchOnlineSongs(keyword);
        if (results.isNotEmpty) {
          await notifier.addAndPlaySong(results.first);
        }
      }
    }

    if (mounted) {
      setState(() {
        _isLoadingReply = false;
        _messages.add({'role': 'ai', 'text': cleanReply});
        _modelCtrl.text = _llm.modelName;
        _baseUrlCtrl.text = _llm.baseUrl;
      });
      await _saveChatHistory();
      _scrollToBottom();
    }

    if (_llm.enableVoiceTts &&
        cleanReply.isNotEmpty &&
        !cleanReply.startsWith('API ') &&
        !cleanReply.startsWith('⚠️')) {
      final ttsSnippet =
          cleanReply.length > 180 ? cleanReply.substring(0, 180) : cleanReply;
      await _tts.speak(ttsSnippet);
    }
  }

  LlmProviderPreset get _currentPreset {
    return UniversalLlmService.presets.firstWhere(
      (p) => p.id == _llm.providerId,
      orElse: () => UniversalLlmService.presets.first,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.82,
        padding: const EdgeInsets.all(16),
        decoration: const BoxDecoration(
          color: Color(0xFF101923),
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      const Icon(
                        Icons.auto_awesome,
                        color: Color(0xFF00D676),
                        size: 20,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          '全能 AI 助手 (${_llm.modelName})',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!_showConfigPanel)
                      IconButton(
                        tooltip: '清空对话记录',
                        icon: const Icon(
                          Icons.cleaning_services_rounded,
                          size: 18,
                          color: Colors.white54,
                        ),
                        onPressed: () async {
                          await _tts.stop();
                          setState(() {
                            _messages = [
                              {
                                'role': 'ai',
                                'text': '对话已清空！你可以问我任何问题，或者让我帮你播放音乐。',
                              }
                            ];
                          });
                          await _saveChatHistory();
                        },
                      ),
                    TextButton.icon(
                      onPressed: () async {
                        if (_showConfigPanel) {
                          await _syncAndSaveConfig();
                        }
                        if (mounted) {
                          setState(() => _showConfigPanel = !_showConfigPanel);
                        }
                      },
                      icon: const Icon(
                        Icons.settings_ethernet,
                        size: 16,
                        color: Color(0xFF00D676),
                      ),
                      label: Text(
                        _showConfigPanel ? '返回对话' : '配置 API',
                        style: const TextStyle(
                          color: Color(0xFF00D676),
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const Divider(color: Colors.white12, height: 12),
            if (_showConfigPanel)
              Expanded(child: _buildApiConfigView())
            else ...[
              // 快捷提问与点歌示例胶囊
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildQuickPromptChip('💬 讲个有趣的笑话'),
                    _buildQuickPromptChip('🧠 为什么天空是蓝色的？'),
                    _buildQuickPromptChip('✍️ 帮我写一段朋友生日祝福'),
                    _buildQuickPromptChip('🎵 播放周杰伦的稻香'),
                    _buildQuickPromptChip('⏭️ 切换到下一首'),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Expanded(child: _buildChatListView()),
              const SizedBox(height: 8),
              Row(
                children: [
                  GestureDetector(
                    onTap: _toggleVoiceInput,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: _isListening
                            ? Colors.redAccent
                            : const Color(0xFF00D676).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        _isListening ? Icons.mic : Icons.mic_none,
                        color: _isListening
                            ? Colors.white
                            : const Color(0xFF00D676),
                        size: 20,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _chatCtrl,
                      textInputAction: TextInputAction.send,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: '问任何问题、自由聊天，或说“播放xxx”...',
                        hintStyle: const TextStyle(
                          color: Colors.white38,
                          fontSize: 12,
                        ),
                        filled: true,
                        fillColor: const Color(0xFF0B1118),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onSubmitted: _sendMessage,
                    ),
                  ),
                  const SizedBox(width: 6),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00D676),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 11,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed:
                        _isLoadingReply ? null : () => _sendMessage(_chatCtrl.text),
                    child: const Text(
                      '发送',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildQuickPromptChip(String label) {
    final cleanPrompt = label.replaceFirst(RegExp(r'^[^\s]+\s+'), '');
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ActionChip(
        backgroundColor: Colors.white10,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        label: Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 11),
        ),
        onPressed: () => _sendMessage(cleanPrompt),
      ),
    );
  }

  Widget _buildApiConfigView() {
    final preset = _currentPreset;
    return ListView(
      children: [
        const Text(
          '1. 选择大模型厂商预设：',
          style: TextStyle(
            color: Colors.white70,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: UniversalLlmService.presets.map((p) {
            final selected = _llm.providerId == p.id;
            return ChoiceChip(
              label: Text(
                p.name,
                style: TextStyle(
                  fontSize: 11,
                  color: selected ? Colors.black : Colors.white,
                ),
              ),
              selected: selected,
              selectedColor: const Color(0xFF00D676),
              backgroundColor: Colors.white10,
              onSelected: (_) async {
                setState(() {
                  _llm.providerId = p.id;
                  _baseUrlCtrl.text = p.defaultBaseUrl;
                  _modelCtrl.text = p.defaultModel;
                });
                await _syncAndSaveConfig();
              },
            );
          }).toList(),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              '2. API Key (点击右侧按钮直接粘贴)：',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            Row(
              children: [
                TextButton.icon(
                  style: TextButton.styleFrom(
                    backgroundColor: const Color(0xFF00D676).withOpacity(0.2),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                  ),
                  onPressed: () => _pasteIntoController(_apiKeyCtrl, 'API Key'),
                  icon: const Icon(
                    Icons.content_paste_rounded,
                    size: 14,
                    color: Color(0xFF00D676),
                  ),
                  label: const Text(
                    '📋 一键粘贴 Key',
                    style: TextStyle(
                      color: Color(0xFF00D676),
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  tooltip: '显示/隐藏密码',
                  icon: Icon(
                    _obscureApiKey ? Icons.visibility_off : Icons.visibility,
                    size: 18,
                    color: Colors.white54,
                  ),
                  onPressed: () =>
                      setState(() => _obscureApiKey = !_obscureApiKey),
                ),
                IconButton(
                  tooltip: '清空',
                  icon: const Icon(
                    Icons.clear_rounded,
                    size: 18,
                    color: Colors.white54,
                  ),
                  onPressed: () async {
                    setState(() => _apiKeyCtrl.clear());
                    await _syncAndSaveConfig();
                  },
                ),
              ],
            ),
          ],
        ),
        TextField(
          controller: _apiKeyCtrl,
          obscureText: _obscureApiKey,
          onChanged: (_) => _syncAndSaveConfig(),
          style: const TextStyle(color: Colors.white, fontSize: 12),
          decoration: InputDecoration(
            hintText: '复制你的 API Key 后，直接点上方「📋 一键粘贴 Key」',
            hintStyle: const TextStyle(color: Colors.white38, fontSize: 11),
            filled: true,
            fillColor: Colors.white.withOpacity(0.06),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Expanded(
              child: Text(
                '3. 模型名称 / Model ID (点下方绿色标签自动填入)：',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            TextButton.icon(
              style: TextButton.styleFrom(
                backgroundColor: Colors.white10,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              ),
              onPressed: () => _pasteIntoController(_modelCtrl, '模型名称'),
              icon: const Icon(
                Icons.content_paste_rounded,
                size: 13,
                color: Color(0xFF00D676),
              ),
              label: const Text(
                '粘贴',
                style: TextStyle(color: Color(0xFF00D676), fontSize: 11),
              ),
            ),
          ],
        ),
        TextField(
          controller: _modelCtrl,
          onChanged: (_) => _syncAndSaveConfig(),
          style: const TextStyle(
            color: Color(0xFF00D676),
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
          decoration: InputDecoration(
            hintText: '如 doubao-seed-evolving 或 doubao-seed-2-1-turbo-260628',
            hintStyle: const TextStyle(color: Colors.white38, fontSize: 11),
            filled: true,
            fillColor: Colors.white.withOpacity(0.06),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        if (preset.quickModels.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            preset.hint,
            style: const TextStyle(color: Colors.amberAccent, fontSize: 11),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: preset.quickModels.map((m) {
              final isCurr = _modelCtrl.text.trim() == m.modelId;
              return ActionChip(
                backgroundColor:
                    isCurr ? const Color(0xFF00D676) : Colors.white10,
                label: Text(
                  '${m.label} (${m.modelId})',
                  style: TextStyle(
                    fontSize: 10.5,
                    color: isCurr ? Colors.black : Colors.white,
                    fontWeight: isCurr ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                onPressed: () async {
                  setState(() {
                    _modelCtrl.text = m.modelId;
                  });
                  await _syncAndSaveConfig();
                },
              );
            }).toList(),
          ),
        ],
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              '4. API Base URL (自动兼容方舟标准与套餐地址)：',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            TextButton.icon(
              style: TextButton.styleFrom(
                backgroundColor: Colors.white10,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              ),
              onPressed: () => _pasteIntoController(_baseUrlCtrl, 'Base URL'),
              icon: const Icon(
                Icons.content_paste_rounded,
                size: 13,
                color: Color(0xFF00D676),
              ),
              label: const Text(
                '粘贴',
                style: TextStyle(color: Color(0xFF00D676), fontSize: 11),
              ),
            ),
          ],
        ),
        TextField(
          controller: _baseUrlCtrl,
          onChanged: (_) => _syncAndSaveConfig(),
          style: const TextStyle(color: Colors.white, fontSize: 12),
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.white.withOpacity(0.06),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          activeColor: const Color(0xFF00D676),
          title: const Text(
            '开启 AI 回复语音朗读 (TTS)',
            style: TextStyle(color: Colors.white, fontSize: 13),
          ),
          value: _llm.enableVoiceTts,
          onChanged: (v) async {
            setState(() => _llm.enableVoiceTts = v);
            if (!v) await _tts.stop();
            await _syncAndSaveConfig();
          },
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF00D676),
                  side: const BorderSide(color: Color(0xFF00D676)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: _isTestingApi
                    ? null
                    : () async {
                        FocusScope.of(context).unfocus();
                        if (_apiKeyCtrl.text.trim().isEmpty) {
                          _showResultDialog(
                            '请先粘贴 API Key',
                            '你还没有填入 API Key！请先复制你的 Key，然后点击上方「📋 一键粘贴 Key」按钮。',
                            isSuccess: false,
                          );
                          return;
                        }
                        setState(() => _isTestingApi = true);
                        await _syncAndSaveConfig();
                        final testRes = await _llm.chatWithModel(
                          userMessage: '你好，请用一句话介绍你自己，并告诉我你能回答哪些问题。',
                          currentSongSummary: '测试连通性',
                          localSongTitles: const [],
                        );
                        if (!mounted) return;
                        setState(() {
                          _isTestingApi = false;
                          _modelCtrl.text = _llm.modelName;
                          _baseUrlCtrl.text = _llm.baseUrl;
                        });
                        final isErr =
                            testRes.startsWith('API ') || testRes.startsWith('⚠️');
                        _showResultDialog(
                          isErr ? '❌ API 连接未通过' : '✅ 大模型 API 连通成功！',
                          isErr
                              ? testRes
                              : '当前生效模型：${_llm.modelName}\n\n模型回复：\n$testRes',
                          isSuccess: !isErr,
                        );
                      },
                icon: Icon(
                  _isTestingApi ? Icons.hourglass_top : Icons.wifi_tethering,
                  size: 16,
                ),
                label: Text(
                  _isTestingApi ? '正在连接大模型...' : '⚡ 测试 API 连通性',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00D676),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: () async {
                  FocusScope.of(context).unfocus();
                  await _syncAndSaveConfig();
                  if (!mounted) return;
                  setState(() {
                    _showConfigPanel = false;
                  });
                },
                child: const Text(
                  '保存并返回对话',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildChatListView() {
    return ListView.builder(
      controller: _scrollCtrl,
      itemCount: _messages.length + (_isLoadingReply ? 1 : 0),
      itemBuilder: (context, idx) {
        if (idx == _messages.length) {
          return const Padding(
            padding: EdgeInsets.all(12),
            child: Row(
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFF00D676),
                  ),
                ),
                SizedBox(width: 8),
                Text(
                  '大模型正在思考回答...',
                  style: TextStyle(color: Color(0xFF00D676), fontSize: 12),
                ),
              ],
            ),
          );
        }
        final msg = _messages[idx];
        final isUser = msg['role'] == 'user';
        return Align(
          alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 5),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.82,
            ),
            decoration: BoxDecoration(
              color: isUser ? const Color(0xFF00D676) : const Color(0xFF172432),
              borderRadius: BorderRadius.circular(16),
            ),
            child: SelectableText(
              msg['text'] ?? '',
              style: TextStyle(
                color: isUser ? Colors.black : Colors.white,
                fontSize: 13,
                height: 1.45,
                fontWeight: isUser ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        );
      },
    );
  }
}
