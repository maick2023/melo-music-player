import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';
import '../services/audio_player_service.dart';
import '../services/universal_llm_service.dart';
import '../services/online_search_service.dart';
import '../models/song_model.dart';

class AiAssistantSheet extends ConsumerStatefulWidget {
  final String? currentSongSummary;
  final Future<void> Function(AiPlayerCommand cmd)? onExecuteCommand;

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
  final TextEditingController _chatCtrl = TextEditingController();
  final TextEditingController _baseUrlCtrl = TextEditingController();
  final TextEditingController _apiKeyCtrl = TextEditingController();
  final TextEditingController _modelCtrl = TextEditingController();

  bool _showConfigPanel = false;
  bool _isListening = false;
  bool _isLoadingReply = false;
  bool _isTestingApi = false;
  bool _obscureApiKey = false; // 默认明文显示，方便核对粘贴内容

  final List<Map<String, String>> _messages = [
    {
      'role': 'ai',
      'text': '你好！我是悦听 AI 音乐助手，已支持接入火山引擎(豆包 Seed 2.1 / Evolving / DeepSeek V4.1 / GLM-5.3)、DeepSeek 官方、通义千问、OpenAI GPT、Gemini 与 Meta Llama。你可以直接按住麦克风对我说：“我想听周杰伦的稻香”、“切换到黑胶模式”或聊聊这首歌的故事！',
    }
  ];

  @override
  void initState() {
    super.initState();
    _initConfigAndSpeech();
  }

  Future<void> _initConfigAndSpeech() async {
    await _llm.loadSavedConfig();
    _baseUrlCtrl.text = _llm.baseUrl;
    _apiKeyCtrl.text = _llm.apiKey;
    _modelCtrl.text = _llm.modelName;
    await _tts.setLanguage('zh-CN');
    await _tts.setSpeechRate(0.5);
    if (mounted) setState(() {});
  }

  Future<void> _pasteIntoController(TextEditingController ctrl, String fieldLabel) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) {
      if (!mounted) return;
      _showResultDialog('剪贴板为空', '手机剪贴板里还没有内容，请先去复制 $fieldLabel 再点击「一键粘贴」。', isSuccess: false);
      return;
    }
    setState(() {
      ctrl.text = text;
      ctrl.selection = TextSelection.fromPosition(TextPosition(offset: ctrl.text.length));
    });
  }

  void _showResultDialog(String title, String message, {required bool isSuccess}) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF162230),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            Icon(
              isSuccess ? Icons.check_circle_rounded : Icons.error_outline_rounded,
              color: isSuccess ? const Color(0xFF00D676) : Colors.amberAccent,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Text(
            message,
            style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
          ),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00D676),
              foregroundColor: Colors.black,
            ),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('知道了', style: TextStyle(fontWeight: FontWeight.bold)),
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
          if (result.finalResult && result.recognizedWords.trim().isNotEmpty) {
            _sendMessage(result.recognizedWords.trim());
          }
        },
      );
    } else {
      _showResultDialog('需要麦克风权限', '无法启动手机语音识别，请在手机设置中授予麦克风权限。', isSuccess: false);
    }
  }

  Future<void> _sendMessage(String rawText) async {
    final text = rawText.trim();
    if (text.isEmpty) return;
    _chatCtrl.clear();
    FocusScope.of(context).unfocus();

    setState(() {
      _messages.add({'role': 'user', 'text': text});
      _isLoadingReply = true;
    });

    final playerState = ref.read(audioPlayerProvider);
    final notifier = ref.read(audioPlayerProvider.notifier);
    final curSong = playerState.currentSong;
    final songSummary = curSong != null ? '《${curSong.title}》- ${curSong.artist}' : '当前未播放歌曲';

    final reply = await _llm.chatWithModel(
      userMessage: text,
      currentSongSummary: songSummary,
      localSongTitles: playerState.allSongs.map((s) => s.title).toList(),
    );

    String cleanReply = reply;
    if (reply.startsWith('[ACTION:NEXT]')) {
      notifier.nextSong();
      cleanReply = reply.replaceFirst('[ACTION:NEXT]', '').trim();
    } else if (reply.startsWith('[ACTION:PREV]')) {
      notifier.previousSong();
      cleanReply = reply.replaceFirst('[ACTION:PREV]', '').trim();
    } else if (reply.startsWith('[ACTION:PAUSE]')) {
      if (playerState.isPlaying) notifier.togglePlayPause();
      cleanReply = reply.replaceFirst('[ACTION:PAUSE]', '').trim();
    } else if (reply.startsWith('[STYLE:VINYL]')) {
      notifier.setVisualStyle(PlayerVisualStyle.vinyl);
      cleanReply = reply.replaceFirst('[STYLE:VINYL]', '').trim();
    } else if (reply.startsWith('[STYLE:FULLSCREEN]')) {
      notifier.setVisualStyle(PlayerVisualStyle.fullscreen);
      cleanReply = reply.replaceFirst('[STYLE:FULLSCREEN]', '').trim();
    } else if (reply.startsWith('[STYLE:GLASS]')) {
      notifier.setVisualStyle(PlayerVisualStyle.glassCard);
      cleanReply = reply.replaceFirst('[STYLE:GLASS]', '').trim();
    } else if (reply.startsWith('[PLAY_SONG:')) {
      final endIdx = reply.indexOf(']');
      if (endIdx != -1) {
        final keyword = reply.substring(11, endIdx).trim();
        cleanReply = reply.substring(endIdx + 1).trim();
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
    }

    if (_llm.enableVoiceTts && cleanReply.isNotEmpty) {
      await _tts.speak(cleanReply);
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
        height: 620,
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
                const Row(
                  children: [
                    Icon(Icons.auto_awesome, color: Color(0xFF00D676)),
                    SizedBox(width: 8),
                    Text(
                      'AI 音乐伴侣 & 语音点歌台',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ],
                ),
                TextButton.icon(
                  onPressed: () => setState(() => _showConfigPanel = !_showConfigPanel),
                  icon: const Icon(Icons.settings_ethernet, size: 16, color: Color(0xFF00D676)),
                  label: Text(
                    _showConfigPanel ? '返回对话' : '配置大模型 API',
                    style: const TextStyle(color: Color(0xFF00D676), fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const Divider(color: Colors.white12),
            if (_showConfigPanel)
              Expanded(child: _buildApiConfigView())
            else
              Expanded(child: _buildChatListView()),
            const SizedBox(height: 8),
            Row(
              children: [
                GestureDetector(
                  onTap: _toggleVoiceInput,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: _isListening ? Colors.redAccent : const Color(0xFF00D676).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      _isListening ? Icons.mic : Icons.mic_none,
                      color: _isListening ? Colors.white : const Color(0xFF00D676),
                      size: 20,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _chatCtrl,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: const InputDecoration(
                      hintText: '输入或语音说：“我想听稻香”、“下一首”...',
                      hintStyle: TextStyle(color: Colors.white38, fontSize: 12),
                      border: InputBorder.none,
                    ),
                    onSubmitted: _sendMessage,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send_rounded, color: Color(0xFF00D676)),
                  onPressed: () => _sendMessage(_chatCtrl.text),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildApiConfigView() {
    final preset = _currentPreset;
    return ListView(
      children: [
        const Text(
          '1. 选择大模型厂商预设：',
          style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: UniversalLlmService.presets.map((p) {
            final selected = _llm.providerId == p.id;
            return ChoiceChip(
              label: Text(p.name, style: TextStyle(fontSize: 11, color: selected ? Colors.black : Colors.white)),
              selected: selected,
              selectedColor: const Color(0xFF00D676),
              backgroundColor: Colors.white10,
              onSelected: (_) {
                setState(() {
                  _llm.providerId = p.id;
                  _baseUrlCtrl.text = p.defaultBaseUrl;
                  _modelCtrl.text = p.defaultModel;
                });
              },
            );
          }).toList(),
        ),
        const SizedBox(height: 12),

        // API Key 区域（带专门的「一键粘贴」按钮，无需弹出手机键盘长按）
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('2. API Key (点击右侧按钮直接粘贴)：', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
            Row(
              children: [
                TextButton.icon(
                  style: TextButton.styleFrom(
                    backgroundColor: const Color(0xFF00D676).withOpacity(0.2),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  ),
                  onPressed: () => _pasteIntoController(_apiKeyCtrl, 'API Key'),
                  icon: const Icon(Icons.content_paste_rounded, size: 14, color: Color(0xFF00D676)),
                  label: const Text('📋 一键粘贴 Key', style: TextStyle(color: Color(0xFF00D676), fontSize: 11, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 4),
                IconButton(
                  tooltip: '显示/隐藏密码',
                  icon: Icon(_obscureApiKey ? Icons.visibility_off : Icons.visibility, size: 18, color: Colors.white54),
                  onPressed: () => setState(() => _obscureApiKey = !_obscureApiKey),
                ),
                IconButton(
                  tooltip: '清空',
                  icon: const Icon(Icons.clear_rounded, size: 18, color: Colors.white54),
                  onPressed: () => setState(() => _apiKeyCtrl.clear()),
                ),
              ],
            ),
          ],
        ),
        TextField(
          controller: _apiKeyCtrl,
          obscureText: _obscureApiKey,
          style: const TextStyle(color: Colors.white, fontSize: 12),
          decoration: InputDecoration(
            hintText: '复制你的 API Key 后，直接点上方「📋 一键粘贴 Key」',
            hintStyle: const TextStyle(color: Colors.white38, fontSize: 11),
            filled: true,
            fillColor: Colors.white.withOpacity(0.06),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
          ),
        ),
        const SizedBox(height: 12),

        // 模型名称区域（带已开通模型一键点选 + 一键粘贴）
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Expanded(
              child: Text(
                '3. 模型名称 / Model ID (点下方绿色标签自动填入)：',
                style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
            TextButton.icon(
              style: TextButton.styleFrom(
                backgroundColor: Colors.white10,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              ),
              onPressed: () => _pasteIntoController(_modelCtrl, '模型名称'),
              icon: const Icon(Icons.content_paste_rounded, size: 13, color: Color(0xFF00D676)),
              label: const Text('粘贴', style: TextStyle(color: Color(0xFF00D676), fontSize: 11)),
            ),
          ],
        ),
        TextField(
          controller: _modelCtrl,
          style: const TextStyle(color: Color(0xFF00D676), fontSize: 12, fontWeight: FontWeight.bold),
          decoration: InputDecoration(
            hintText: '如 doubao-seed-evolving 或 doubao-seed-2-1-turbo-260628',
            hintStyle: const TextStyle(color: Colors.white38, fontSize: 11),
            filled: true,
            fillColor: Colors.white.withOpacity(0.06),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
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
                backgroundColor: isCurr ? const Color(0xFF00D676) : Colors.white10,
                label: Text(
                  '${m.label} (${m.modelId})',
                  style: TextStyle(
                    fontSize: 10.5,
                    color: isCurr ? Colors.black : Colors.white,
                    fontWeight: isCurr ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                onPressed: () {
                  setState(() {
                    _modelCtrl.text = m.modelId;
                  });
                },
              );
            }).toList(),
          ),
        ],
        const SizedBox(height: 12),

        // Base URL 区域
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('4. API Base URL (自动兼容方舟标准与套餐地址)：', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
            TextButton.icon(
              style: TextButton.styleFrom(
                backgroundColor: Colors.white10,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              ),
              onPressed: () => _pasteIntoController(_baseUrlCtrl, 'Base URL'),
              icon: const Icon(Icons.content_paste_rounded, size: 13, color: Color(0xFF00D676)),
              label: const Text('粘贴', style: TextStyle(color: Color(0xFF00D676), fontSize: 11)),
            ),
          ],
        ),
        TextField(
          controller: _baseUrlCtrl,
          style: const TextStyle(color: Colors.white, fontSize: 12),
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.white.withOpacity(0.06),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
          ),
        ),
        const SizedBox(height: 14),

        // 测试与保存按钮
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
                          _showResultDialog('请先粘贴 API Key', '你还没有填入 API Key！请先复制你的 Key，然后点击上方「📋 一键粘贴 Key」按钮。', isSuccess: false);
                          return;
                        }
                        setState(() => _isTestingApi = true);
                        await _llm.saveConfig(
                          providerId: _llm.providerId,
                          baseUrl: _baseUrlCtrl.text,
                          apiKey: _apiKeyCtrl.text,
                          modelName: _modelCtrl.text,
                          enableVoiceTts: _llm.enableVoiceTts,
                        );
                        final testRes = await _llm.chatWithModel(
                          userMessage: '你好，请用一句话介绍你自己。',
                          currentSongSummary: '测试连通性',
                          localSongTitles: const [],
                        );
                        if (!mounted) return;
                        setState(() {
                          _isTestingApi = false;
                          _modelCtrl.text = _llm.modelName;
                          _baseUrlCtrl.text = _llm.baseUrl;
                        });
                        final isErr = testRes.startsWith('API ');
                        _showResultDialog(
                          isErr ? '❌ API 连接未通过' : '✅ 大模型 API 连通成功！',
                          isErr ? testRes : '当前生效模型：${_llm.modelName}\n\n模型回复：\n$testRes',
                          isSuccess: !isErr,
                        );
                      },
                icon: Icon(_isTestingApi ? Icons.hourglass_top : Icons.wifi_tethering, size: 16),
                label: Text(_isTestingApi ? '正在连接大模型...' : '⚡ 测试 API 连通性', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
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
                  await _llm.saveConfig(
                    providerId: _llm.providerId,
                    baseUrl: _baseUrlCtrl.text,
                    apiKey: _apiKeyCtrl.text,
                    modelName: _modelCtrl.text,
                    enableVoiceTts: _llm.enableVoiceTts,
                  );
                  if (!mounted) return;
                  setState(() {
                    _modelCtrl.text = _llm.modelName;
                    _showConfigPanel = false;
                  });
                },
                child: const Text('保存配置并返回对话', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildChatListView() {
    return ListView.builder(
      itemCount: _messages.length + (_isLoadingReply ? 1 : 0),
      itemBuilder: (context, idx) {
        if (idx == _messages.length) {
          return const Padding(
            padding: EdgeInsets.all(12),
            child: Text('AI 正在思考...', style: TextStyle(color: Color(0xFF00D676), fontSize: 12)),
          );
        }
        final msg = _messages[idx];
        final isUser = msg['role'] == 'user';
        return Align(
          alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 5),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isUser ? const Color(0xFF00D676) : const Color(0xFF172432),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              msg['text'] ?? '',
              style: TextStyle(
                color: isUser ? Colors.black : Colors.white,
                fontSize: 13,
                fontWeight: isUser ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        );
      },
    );
  }
}
