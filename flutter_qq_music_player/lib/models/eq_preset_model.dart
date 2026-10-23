/// 5段均衡器音效预设模型 (60Hz, 230Hz, 910Hz, 3.6kHz, 14kHz)
class EqPresetModel {
  final String id;
  final String name;
  final String subtitle;
  final List<double> gains; // 范围 -12.0 dB ~ +12.0 dB

  const EqPresetModel({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.gains,
  });

  static const List<String> bandLabels = [
    '60Hz (超低频)',
    '230Hz (低频)',
    '910Hz (中频)',
    '3.6kHz (中高频)',
    '14kHz (高频)',
  ];

  static const List<EqPresetModel> builtinPresets = [
    EqPresetModel(
      id: 'flat',
      name: '原声直通',
      subtitle: '不经过频段修饰的纯净无损原声',
      gains: [0.0, 0.0, 0.0, 0.0, 0.0],
    ),
    EqPresetModel(
      id: 'pop',
      name: 'QQ流行人声',
      subtitle: '突出人声结像与中频温暖细节',
      gains: [-1.5, 2.5, 4.5, 2.0, -1.0],
    ),
    EqPresetModel(
      id: 'bass',
      name: '超重低音',
      subtitle: '澎湃下潜，适合电子乐与节奏说唱',
      gains: [8.0, 5.5, 0.0, 1.5, 3.0],
    ),
    EqPresetModel(
      id: 'rock',
      name: '现场摇滚',
      subtitle: '强化底鼓冲击感与电吉他高频泛音',
      gains: [5.0, 3.0, -2.0, 3.5, 6.0],
    ),
    EqPresetModel(
      id: 'classical',
      name: '古典交响',
      subtitle: '开阔声场，延伸弦乐高频空气感',
      gains: [3.5, 2.0, -1.0, 2.5, 5.0],
    ),
    EqPresetModel(
      id: 'vocal',
      name: '清澈人声',
      subtitle: '弱化轰头低频，贴耳细腻女声/民谣',
      gains: [-3.0, -1.0, 5.0, 4.0, 1.5],
    ),
  ];
}
