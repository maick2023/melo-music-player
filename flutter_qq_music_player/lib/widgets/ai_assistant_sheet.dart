import 'package:flutter/material.dart';
import '../services/universal_llm_service.dart';
import '../services/voice_assistant_service.dart';

/// 仿 QQ 音乐 AI 音乐伴侣与多模型 API 网关配置抽屉
class AiAssistantSheet extends StatefulWidget {
  final String currentSongSummary;
  final void Function(AiPlayerCommand command) onExecuteCommand;

  const AiAssistantSheet({
    super.key,
    required this.currentSongSummary,
    required this.onExecuteCommand,
  });

  @override
  State<AiAssistantSheet> createState() => _AiAssistantSheetState();
}

class _AiAssistantSheetState extends State<AiAssistantSheet> {
  final UniversalLlmService _llmService = UniversalLlmService();
  final VoiceAssistantService _voiceService = VoiceAssistantService();
  final TextEditingController _inputController = TextEditingController();
  final TextEditingController _baseUrlController = TextEditingController();
  final TextEditingController _apiKeyController = TextEditingController();
  final TextEditingController _modelController = TextEditingController();

  bool _showConfigPanel = false;
  bool _isSending = false;
  final List<Map<String, String>> _messages = [
    {
      'role': 'ai',
      'text': '你好！我是悦听 AI 音乐助手，已支持接入 DeepSeek、火山引擎(豆包)、通义千问、OpenAI GPT、Gemini 与 Meta Llama。你可以直接按住麦克风对我说：“我想听周杰伦的稻香”、“切换到黑胶模式”或聊聊这首歌的故事！',
    },
  ];

  @override
  void initState() {
    super.initState();
    _initServices();
  }

  Future<void> _initServices() async {
    await _llmService.loadSavedConfig();
    await _voiceService.initVoiceEngine();
    setState(() {
      _baseUrlController.text = _llmService.baseUrl;
      _apiKeyController.text = _llmService.apiKey;
      _modelController.text = _llmService.modelName;
    });
  }

  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty || _isSending) return;
    setState(() {
      _messages.add({'role': 'user', 'text': text.trim()});
      _isSending = true;
    });
    _inputController.clear();

    final cmd = await _llmService.sendChatWithMusicIntent(
      userText: text,
      currentSongSummary: widget.currentSongSummary,
    );

    if (!mounted) return;
    setState(() {
      _messages.add({'role': 'ai', 'text': cmd.replyText});
      _isSending = false;
    });

    widget.onExecuteCommand(cmd);
    await _voiceService.speakReply(cmd.replyText);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.82,
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 20),
      decoration: const BoxDecoration(
        color: Color(0xFF101924),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.auto_awesome_rounded, color: Color(0xFF00E676)),
                  SizedBox(width: 8),
                  Text(
                    'AI 音乐伴侣 & 语音点歌台',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              TextButton.icon(
                onPressed: () =>
                    setState(() => _showConfigPanel = !_showConfigPanel),
                icon: const Icon(
                  Icons.settings_ethernet_rounded,
                  size: 16,
                  color: Color(0xFF00E676),
                ),
                label: Text(
                  _showConfigPanel ? '返回对话' : '配置大模型 API',
                  style: const TextStyle(color: Color(0xFF00E676), fontSize: 12),
                ),
              ),
            ],
          ),
          const Divider(color: Colors.white12),
          if (_showConfigPanel)
            Expanded(
              child: ListView(
                children: [
                  const Text(
                    '选择预设大模型服务商（一键填入标准接口地址）：',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: LlmProviderPreset.builtinProviders.map((p) {
                      final active = _llmService.providerId == p.id;
                      return ChoiceChip(
                        label: Text(p.name),
                        selected: active,
                        selectedColor: const Color(0xFF00D676),
                        onSelected: (_) {
                          setState(() {
                            _llmService.providerId = p.id;
                            _baseUrlController.text = p.baseUrl;
                            _modelController.text = p.defaultModel;
                          });
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _baseUrlController,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: const InputDecoration(
                      labelText: 'API Base URL (兼容任何 OpenAI 规范地址)',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _modelController,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: const InputDecoration(
                      labelText: '模型名称 / 火山引擎 Endpoint ID (如 deepseek-chat / ep-xxxx)',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _apiKeyController,
                    obscureText: true,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: const InputDecoration(
                      labelText: 'API Key (加密保存在手机本地)',
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(
                            Icons.network_check_rounded,
                            color: Color(0xFF00E676),
                            size: 16,
                          ),
                          label: const Text(
                            '测试 API 连通性',
                            style: TextStyle(color: Color(0xFF00E676), fontSize: 12),
                          ),
                          onPressed: () async {
                            await _llmService.saveConfig(
                              providerId: _llmService.providerId,
                              baseUrl: _baseUrlController.text,
                              apiKey: _apiKeyController.text,
                              modelName: _modelController.text,
                            );
                            final testCmd = await _llmService.sendChatWithMusicIntent(
                              userText: '请用一句话介绍你自己并确认连接成功',
                              currentSongSummary: widget.currentSongSummary,
                            );
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('大模型响应：${testCmd.replyText}')),
                              );
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF00D676),
                            foregroundColor: Colors.black,
                          ),
                          onPressed: () async {
                            await _llmService.saveConfig(
                              providerId: _llmService.providerId,
                              baseUrl: _baseUrlController.text,
                              apiKey: _apiKeyController.text,
                              modelName: _modelController.text,
                            );
                            setState(() => _showConfigPanel = false);
                          },
                          child: const Text('保存配置并返回对话'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                itemCount: _messages.length,
                itemBuilder: (context, idx) {
                  final m = _messages[idx];
                  final isUser = m['role'] == 'user';
                  return Align(
                    alignment:
                        isUser ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isUser
                            ? const Color(0xFF00D676)
                            : const Color(0xFF1A2634),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        m['text'] ?? '',
                        style: TextStyle(
                          color: isUser ? Colors.black : Colors.white,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              IconButton(
                tooltip: '语音对讲点歌',
                icon: Icon(
                  _voiceService.isListening
                      ? Icons.mic_rounded
                      : Icons.mic_none_rounded,
                  color: const Color(0xFF00E676),
                ),
                onPressed: () async {
                  if (_voiceService.isListening) {
                    await _voiceService.stopListening();
                    setState(() {});
                  } else {
                    await _voiceService.startListening(
                      onResult: (words, isFinal) {
                        _inputController.text = words;
                        if (isFinal && words.isNotEmpty) {
                          _sendMessage(words);
                        }
                      },
                    );
                    setState(() {});
                  }
                },
              ),
              Expanded(
                child: TextField(
                  controller: _inputController,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: const InputDecoration(
                    hintText: '输入或语音说：“我想听稻香”、“下一首”、“赏析这首歌”...',
                    border: InputBorder.none,
                  ),
                  onSubmitted: _sendMessage,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.send_rounded, color: Color(0xFF00E676)),
                onPressed: () => _sendMessage(_inputController.text),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
